import SwiftUI
import AppKit
import QuartzCore
import ApplicationServices

// MARK: - Keyboard Assistant Host

/// Presents the runtime Zest control beside the caret of the currently focused
/// text field without activating Zest or stealing keyboard focus from the app
/// the user is typing in.
@MainActor
private final class ZestInspectorPanel: NSPanel {
    // A Character Viewer-style panel: it may own keyboard focus without making
    // Zest the active/main application and without surfacing the development window.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ZestKeyboardAssistantController: NSObject {
    private let textContextManager: TextContextManager
    private let fontLibraryManager: FontLibraryManager
    private let settingsManager: ZestSettingsManager

    private var panel: NSPanel?
    private var outsideClickMonitor: Any?
    private var insideStageClickMonitor: Any?
    private var escapeMonitor: Any?
    private var caretDebugPanel: NSPanel?
    private var rawPointerDebugPanel: NSPanel?
    private var pagesPointerMonitor: Any?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var activeSpaceObserver: NSObjectProtocol?
    private var keyboardFocusObserver: NSObjectProtocol?
    private weak var previousApplication: NSRunningApplication?
    private var runtimeControlScreenFrame: CGRect = .null
    private var runtimePopupScreenFrame: CGRect?

    // Pages does not publish trustworthy live insertion geometry through AX on the
    // versions we are targeting. Treat the user's actual document click as the
    // authoritative seed for Pages instead of trying to repair stale AX rectangles.
    private var lastPagesDocumentClick: NSPoint?
    private var lastPagesDocumentClickTime: TimeInterval = 0

    // Give runtime feature panels enough transparent window real estate to expand
    // without being clipped by the NSPanel boundary. The actual Zest control remains
    // the same visual control, centered inside a larger transparent 1040 × 760
    // SwiftUI stage so tall feature panels are never cropped by the host bounds.
    private let panelSize = NSSize(width: 1400, height: 1000)
    private let runtimeCanvasSize = NSSize(width: 1400, height: 1000)
    private let caretGap: CGFloat = 12
    private let visibleControlHalfSize: CGFloat = 105
    private var pendingCaretAnchor: NSRect?
    private var runtimeDragStartOrigin: NSPoint?
    private var runtimeDragStartMouse: NSPoint?

    // Moving the native NSPanel does not require republishing SwiftUI screen
    // geometry unless a feature popup is actually using edge avoidance.
    // Keeping this bridge asleep during ordinary Zest dragging removes a large
    // AppKit -> notification -> SwiftUI invalidation loop from the hottest path.
    private var runtimePopupIsPresented = false
    private var runtimeSummonOrigin: NSPoint?
    private var runtimeResetPlaceholderPanel: NSPanel?

    init(
        textContextManager: TextContextManager,
        fontLibraryManager: FontLibraryManager,
        settingsManager: ZestSettingsManager
    ) {
        self.textContextManager = textContextManager
        self.fontLibraryManager = fontLibraryManager
        self.settingsManager = settingsManager
        super.init()
        installPagesPointerTracker()
        installContextDismissObservers()
        keyboardFocusObserver = NotificationCenter.default.addObserver(
            forName: .zestRuntimeKeyboardFocusRequested, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel else { return }
                // Do NOT activate NSApp here. Activating the accessory app is what
                // surfaced the old full-screen Zest development window. A
                // nonactivating NSPanel that canBecomeKey can receive text input
                // while the external editor remains the active application.
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    deinit {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let insideStageClickMonitor { NSEvent.removeMonitor(insideStageClickMonitor) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let pagesPointerMonitor { NSEvent.removeMonitor(pagesPointerMonitor) }
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
        }
        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
        }
        if let keyboardFocusObserver { NotificationCenter.default.removeObserver(keyboardFocusObserver) }
    }

    func toggle() {
        if panel?.isVisible == true {
            // The summon shortcut is also a true "return to editor" shortcut.
            // Merely hiding our panel leaves the accessory application active;
            // if Settings already exists macOS can then surface that window.
            // Always hand foreground ownership back to the app that summoned Zest.
            dismissAndRestorePreviousApplication(replayClickAt: nil)
        } else {
            showBesideCurrentCaret()
        }
    }

    func showBesideCurrentCaret() {
        showBesideCurrentCaret(afterHotkeyRetry: 0)
    }

    /// Pages is summoned with ⇧⌃Z. If we probe its editor while those physical
    /// modifiers are still down, Pages can interpret our synthetic arrow probe as
    /// a modified navigation command and never publish the real insertion geometry.
    /// Wait for the summon chord to be released before touching the Pages editor.
    private func showBesideCurrentCaret(afterHotkeyRetry retry: Int) {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let isPages = frontApp.map(isPagesApplication) ?? false
        if isPages && pagesSummonModifiersAreStillDown() && retry < 8 {
            print("⏳ PAGES CARET: waiting for summon modifiers to release…", retry + 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) { [weak self] in
                self?.showBesideCurrentCaret(afterHotkeyRetry: retry + 1)
            }
            return
        }

        let panel = panel ?? makePanel()
        self.panel = panel

        let isIWork = frontApp.map(isIWorkApplication) ?? false
        if let frontApp {
            print("🧭 FRONT APP:", frontApp.localizedName ?? "<nil>",
                  "bundle:", frontApp.bundleIdentifier ?? "<nil>",
                  "executable:", frontApp.executableURL?.lastPathComponent ?? "<nil>",
                  "iWorkBypass:", isIWork)
        }

        // Keynote keeps the proven raw-pointer route. Pages now treats the mouse
        // only as a bootstrap seed. Its final anchor is resolved from the current
        // insertion point first, so moving the caret with the keyboard or typing no
        // longer leaves Zest attached to an old physical click.
        // Keynote still uses the raw pointer route. Pages must never visualize or
        // consume the current mouse position: doing so made the purple diagnostic
        // look like a caret candidate even when the resolver had already rejected it.
        let rawIWorkPointer = (isIWork && !isPages) ? NSEvent.mouseLocation : nil
        if let rawIWorkPointer, settingsManager.showCaretIndicator {
            showRawPointerDebugMarker(at: rawIWorkPointer)
            print("🟣 IWORK RAW POINTER AT SUMMON:", NSStringFromPoint(rawIWorkPointer))
        } else {
            rawPointerDebugPanel?.orderOut(nil)
        }

        let anchor: NSRect
        if isPages {
            if let livePagesCaret = currentCaretRect() {
                anchor = livePagesCaret
                print("🍊 PAGES FINAL ANCHOR → CARET RESOLVER:", NSStringFromRect(anchor))
            } else if let seed = pagesPointerCaretRect() {
                anchor = seed
                print("🟠 PAGES FINAL ANCHOR → CLICK SEED FALLBACK:", NSStringFromRect(anchor))
            } else {
                // Never substitute the *current* physical mouse position for a Pages
                // insertion caret. If Pages gives us no caret and no document-click
                // bootstrap, use the neutral fallback rather than lying about the cursor.
                anchor = fallbackAnchorRect()
                print("⚠️ PAGES FINAL ANCHOR → NEUTRAL FALLBACK (mouse rejected):", NSStringFromRect(anchor))
            }
        } else if let rawIWorkPointer {
            anchor = NSRect(x: rawIWorkPointer.x, y: rawIWorkPointer.y - 9, width: 2, height: 18)
            print("🍊 IWORK FINAL ANCHOR (NO AX):", NSStringFromRect(anchor))
        } else {
            anchor = currentCaretRect() ?? fallbackAnchorRect()
        }
        pendingCaretAnchor = anchor
        if settingsManager.showCaretIndicator {
            showCaretDebugMarker(at: anchor)
        } else {
            hideCaretDebugMarker()
        }

        // Remember the editor before Zest takes foreground ownership. Runtime
        // panels are inspector-style: Zest may become key/frontmost for search,
        // while Emoji/Symbol/Clipboard insertion still belongs to this editor.
        if let frontApp, !isZestApplication(frontApp) {
            previousApplication = frontApp
            ZestTextInserter.rememberExternalTarget(frontApp)

            // Layout Fix is shortcut-first in 0.1.2. Summoning the ordinary
            // Zest assistant must never copy or disturb the user's selection.
            // Keep only a lightweight AX context snapshot for the optional manual
            // Layout Fix tile; the global Layout Fix shortcut performs its own
            // capture while the editor remains frontmost.
            ZestKeyboardLayoutFixService.shared.captureExternalContext(from: frontApp)
        }

        presentAssistantPanel(panel, beside: anchor, isIWork: isIWork)
    }

    private func presentAssistantPanel(
        _ panel: NSPanel,
        beside anchor: NSRect,
        isIWork: Bool
    ) {
        // The keyboard host has deterministic geometry. Placement is calculated
        // only after any pre-summon Layout Fix selection capture has completed.
        let summonOrigin = origin(
            for: panelSize,
            beside: anchor,
            gap: isIWork ? 6 : caretGap
        )
        runtimeSummonOrigin = summonOrigin
        panel.setFrameOrigin(summonOrigin)
        panel.alphaValue = 0

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func activeLayoutUsesLayoutFix() -> Bool {
        if settingsManager.menuBarPinnedFeatures.contains(.layoutFix) {
            return true
        }

        switch settingsManager.formFactor {
        case .orangeSlice:
            return settingsManager.sliceAssignments.values.contains(.layoutFix)
        case .centerOnly:
            return settingsManager.centerOnlyTwoFeatures.contains(.layoutFix)
                || settingsManager.centerOnlyFourFeatures.contains(.layoutFix)
                || settingsManager.centerOnlyThreeFeatures.contains(.layoutFix)
        case .turntable:
            return false
        case .tripleSquare:
            return settingsManager.tripleFeatures.contains(.layoutFix)
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.11
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            DispatchQueue.main.async {
                panel?.orderOut(nil)
                panel?.alphaValue = 1
                self?.hideCaretDebugMarker()
            }
        }
    }

    private func prepareToOpenSettings() {
        // The assistant is deliberately non-activating while the user types.
        // Settings is the explicit exception: dismiss the assistant and bring
        // Zest forward before SwiftUI opens the Settings scene.
        // Hide the floating assistant first, but let ContentView create the
        // Settings scene before activating Zest. Activating an accessory app
        // *before* the window exists can leave macOS on the current Space with
        // no key window to follow.
        hide()
    }

    private func makePanel() -> NSPanel {
        let panel = ZestInspectorPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        // The assistant stays non-activating, but it must still participate in
        // AppKit's pointer tracking. SwiftUI `.onHover` is backed by tracking
        // areas and does not require Zest to become the foreground application.
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none

        let root = ZStack {
            Color.clear
            ContentView(
                textContextManager: textContextManager,
                fontLibraryManager: fontLibraryManager,
                settingsManager: settingsManager,
                onOpenSettings: { [weak self] in
                    self?.prepareToOpenSettings()
                },
                forceVibrantRendering: true,
                onRuntimeHostFrameChange: { _ in },
                onRuntimeControlFrameChange: { [weak self] frame in
                    self?.runtimeControlScreenFrame = frame
                },
                onRuntimePopupFrameChange: { [weak self] frame in
                    self?.runtimePopupScreenFrame = frame
                },
                onRuntimeDrag: { [weak self] translation, ended in
                    self?.moveRuntimePanel(by: translation, ended: ended)
                },
                onRuntimePopupPresentationChange: { [weak self] presented in
                    // The keyboard assistant now owns one stable presentation stage.
                    // Never resize/recenter the native panel when a feature opens.
                    // We only remember whether popup edge-avoidance currently needs
                    // live desktop geometry while the native panel is being dragged.
                    self?.runtimePopupIsPresented = presented
                }
            )
            .frame(width: runtimeCanvasSize.width, height: runtimeCanvasSize.height)
        }
        .frame(width: panelSize.width, height: panelSize.height)
        // A non-activating keyboard assistant must keep the foreground app active.
        // Force SwiftUI controls/materials to render in their active visual state so
        // Zest does not look disabled merely because its NSPanel is non-key.
        .environment(\.controlActiveState, .active)
        .background(Color.clear)

        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: panelSize)
        panel.contentView = host

        installDismissMonitors()
        return panel
    }

    private func moveRuntimePanel(by translation: CGSize, ended: Bool) {
        guard let panel else { return }

        // Do not drive the native window from SwiftUI's cumulative translation.
        // Once the window itself moves, that coordinate space moves too and the
        // gesture starts fighting the panel (the visible stutter from the last build).
        // NSEvent.mouseLocation is stable desktop screen-space, just like native
        // macOS window dragging.
        if runtimeDragStartOrigin == nil {
            runtimeDragStartOrigin = panel.frame.origin
            runtimeDragStartMouse = NSEvent.mouseLocation
            showRuntimeResetPlaceholder()
        }
        guard let start = runtimeDragStartOrigin, let mouseStart = runtimeDragStartMouse else { return }
        let mouseNow = NSEvent.mouseLocation
        let proposed = NSPoint(
            x: start.x + (mouseNow.x - mouseStart.x),
            y: start.y + (mouseNow.y - mouseStart.y)
        )
        panel.setFrameOrigin(clampedPanelOrigin(proposed, size: panel.frame.size))

        // NSWindow movement does not invalidate SwiftUI global GeometryReaders.
        // Broadcast the real desktop-space runtime canvas after every native drag
        // step so popup edge avoidance follows Zest instead of its summon position.
        publishRuntimeCanvasFrame()

        // The orange dot is a caret diagnostic, not a tether. Once the user has
        // deliberately repositioned Zest it becomes misleading, so retire it.
        caretDebugPanel?.orderOut(nil)

        if ended {
            if let resetOrigin = runtimeSummonOrigin {
                let dx = panel.frame.origin.x - resetOrigin.x
                let dy = panel.frame.origin.y - resetOrigin.y
                let distance = hypot(dx, dy)
                if distance <= 125 {
                    panel.setFrameOrigin(resetOrigin)
                    publishRuntimeCanvasFrame()
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            }
            hideRuntimeResetPlaceholder()
            runtimeDragStartOrigin = nil
            runtimeDragStartMouse = nil
        }
    }

    private func showRuntimeResetPlaceholder() {
        guard let summonOrigin = runtimeSummonOrigin else { return }

        // The reset ghost belongs to the *visible Zest control*, not to the center
        // of its much larger transparent runtime host. ContentView intentionally
        // shifts every runtime form factor 120 pt to the right inside that host,
        // so mirror that exact transform here. This makes the ghost sit precisely
        // where Zest was summoned — the same visual idea as Spotlight's drag-home
        // preview rather than a generic drop zone elsewhere on screen.
        let visibleControlCenter = NSPoint(
            x: summonOrigin.x + panelSize.width / 2 + 120,
            y: summonOrigin.y + panelSize.height / 2
        )

        let formFactor = settingsManager.runtimeFormFactor
        let size: NSSize
        switch formFactor {
        case .orangeSlice:
            size = NSSize(width: 224, height: 224)
        case .tripleSquare:
            // Extra breathing room is intentional: the hosting NSPanel must include
            // the complete silhouette AND the blur radius of the outer shadow. The
            // previous 250x196 host showed the full glass shape but could still shave
            // a few pixels off the shadow near a bezel.
            size = NSSize(width: 282, height: 224)
        case .centerOnly, .turntable:
            size = NSSize(width: 150, height: 150)
        }

        var frame = NSRect(
            x: visibleControlCenter.x - size.width / 2,
            y: visibleControlCenter.y - size.height / 2,
            width: size.width,
            height: size.height
        )

        // The reset ghost is a visual destination, so unlike the live panel it must
        // never be allowed to hang through a display bezel. Clamp the *whole* ghost
        // window (including the new shadow allowance) into the visible screen.
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(visibleControlCenter) }) ?? NSScreen.main {
            let visible = screen.visibleFrame.insetBy(dx: 6, dy: 6)
            frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.minX, visible.maxX - frame.width))
            frame.origin.y = min(max(frame.origin.y, visible.minY), max(visible.minY, visible.maxY - frame.height))
        }

        // Rebuild the tiny ghost each drag so a just-changed accent, form factor,
        // or Center Only page is reflected immediately.
        runtimeResetPlaceholderPanel?.orderOut(nil)

        let p = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let root = ZestRuntimeResetGhost(
            formFactor: formFactor,
            centerOnlyPage: settingsManager.runtimeCenterOnlyPage,
            accent: settingsManager.accentColor,
            accentBright: settingsManager.accentBrightColor,
            accentDeep: settingsManager.accentDeepColor
        )
        .frame(width: size.width, height: size.height)
        .environment(\.controlActiveState, .active)

        p.contentView = NSHostingView(rootView: root)
        runtimeResetPlaceholderPanel = p
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            p.animator().alphaValue = 1
        }
    }

    private func hideRuntimeResetPlaceholder() {
        runtimeResetPlaceholderPanel?.orderOut(nil)
        runtimeResetPlaceholderPanel?.alphaValue = 1
    }

    private func publishRuntimeCanvasFrame() {
        guard let panel else { return }
        let canvasOrigin = NSPoint(
            x: panel.frame.midX - runtimeCanvasSize.width / 2,
            y: panel.frame.midY - runtimeCanvasSize.height / 2
        )
        let frame = NSRect(origin: canvasOrigin, size: runtimeCanvasSize)
        NotificationCenter.default.post(
            name: .zestRuntimeCanvasScreenFrameDidChange,
            object: nil,
            userInfo: ["x": frame.origin.x, "y": frame.origin.y, "w": frame.width, "h": frame.height]
        )
    }

    // Feature popups render into the permanent transparent stage.
    // Keeping the native window geometry immutable while a popup is presented is
    // deliberate: popup animation and runtime dragging now share one coordinate space.

    private func clampedPanelOrigin(_ origin: NSPoint, size: NSSize) -> NSPoint {
        let current = panel?.frame ?? NSRect(origin: origin, size: size)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(current) })
            ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 6
        return NSPoint(
            x: min(max(origin.x, visible.minX - size.width + 90), visible.maxX - 90),
            y: min(max(origin.y, visible.minY - size.height + 90), visible.maxY - 90)
        )
    }

    /// Zest is a transient editing assistant, not a window that should travel with
    /// the user.  The panel deliberately keeps `canJoinAllSpaces` so it can appear
    /// inside native full-screen apps, but the moment macOS changes application or
    /// Space we tear the visible assistant down synchronously.  Watching workspace
    /// notifications instead of Command-Tab itself also covers Mission Control,
    /// trackpad Space swipes, Dock activation and programmatic app switching.
    private func installContextDismissObservers() {
        let center = NSWorkspace.shared.notificationCenter

        workspaceActivationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication

                // Becoming foreground is now part of the inspector contract.
                // Only leaving Zest for another application dismisses the runtime.
                if let application, self.isZestApplication(application) { return }
                self.hide()
            }
        }

        activeSpaceObserver = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismissImmediatelyForContextTransition(reason: "active Space changed")
            }
        }
    }

    private func isZestApplication(_ application: NSRunningApplication) -> Bool {
        application.processIdentifier == ProcessInfo.processInfo.processIdentifier
            || application.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    private func dismissImmediatelyForContextTransition(reason: String) {
        guard let panel, panel.isVisible else { return }

        // No fade here. During a Space animation even a 100 ms fade can make a
        // canJoinAllSpaces panel visibly surf into the destination desktop.
        panel.orderOut(nil)
        panel.alphaValue = 1
        runtimeDragStartOrigin = nil
        runtimeDragStartMouse = nil
        pendingCaretAnchor = nil
        hideCaretDebugMarker()
        print("🍊 ZEST DISMISSED →", reason)
    }

    private func installDismissMonitors() {
        guard outsideClickMonitor == nil else { return }

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                let point = NSEvent.mouseLocation
                // A click that truly reaches another application's window is enough:
                // restore that app immediately and let the workspace observer finish
                // the fade. The transparent host itself is handled by the local monitor.
                if !panel.frame.contains(point) {
                    self.dismissAndRestorePreviousApplication(replayClickAt: nil)
                }
            }
        }

        insideStageClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else { return event }
            let screenPoint = NSEvent.mouseLocation

            // Turntable controls deliberately extend their physical badges behind the
            // main disk. The SwiftUI-reported bounds can briefly lag the non-activating
            // NSPanel during summon/animation, which made a real badge click look like a
            // click in the transparent stage and caused Zest to dismiss before the
            // Button action could run. Give the complete Turntable hardware a stable
            // AppKit-owned interaction envelope, derived from the panel position rather
            // than asynchronous SwiftUI geometry. The visual control itself is centered
            // in the runtime stage and then placed +120 pt on X in ContentView.
            let turntableHit: Bool = {
                guard self.settingsManager.runtimeFormFactor == .turntable else { return false }
                let hardwareCenter = CGPoint(x: panel.frame.midX + 120, y: panel.frame.midY)
                let hardwareEnvelope = CGRect(
                    x: hardwareCenter.x - 170,
                    y: hardwareCenter.y - 110,
                    width: 340,
                    height: 220
                )
                return hardwareEnvelope.contains(screenPoint)
            }()

            let controlHit = turntableHit
                || self.runtimeControlScreenFrame.insetBy(dx: -4, dy: -4).contains(screenPoint)
            let popupHit = self.runtimePopupScreenFrame?.insetBy(dx: -4, dy: -4).contains(screenPoint) ?? false
            guard !controlHit && !popupHit else { return event }

            // The native host is intentionally much larger than the visible glass so
            // popups have room to animate. A click in that transparent acreage must
            // behave exactly like clicking through an inspector: dismiss Zest, restore
            // the editor, and replay the click once the editor owns the foreground.
            self.dismissAndRestorePreviousApplication(replayClickAt: screenPoint)
            return nil
        }

        // The global shortcut remains the primary toggle. Escape is a convenient
        // local dismissal when Zest itself happens to receive an event.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, self?.panel?.isVisible == true {
                self?.dismissAndRestorePreviousApplication(replayClickAt: nil)
                return nil
            }
            return event
        }
    }


    private func dismissAndRestorePreviousApplication(replayClickAt screenPoint: NSPoint?) {
        guard panel?.isVisible == true else { return }
        hide()
        guard let application = previousApplication, !application.isTerminated else { return }
        application.activate(options: [.activateIgnoringOtherApps])

        guard let screenPoint else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) {
            // NSEvent uses AppKit's bottom-left desktop coordinates; CGEvent uses
            // Quartz's top-left global coordinates. Mirror through the primary
            // display's top edge before replaying the click into the restored app.
            let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 0
            let quartzPoint = CGPoint(x: screenPoint.x, y: desktopTop - screenPoint.y)
            let source = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: quartzPoint, mouseButton: .left)
            let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: quartzPoint, mouseButton: .left)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }


    // MARK: - Caret Debug Probe

    /// Temporary development probe. The orange dot is drawn at the exact AppKit
    /// coordinate Zest believes is the insertion caret. It never activates Zest.
    /// Once Pages is proven, this can be removed without touching placement logic.
    private func showCaretDebugMarker(at anchor: NSRect) {
        let diameter: CGFloat = 8
        let rect = NSRect(
            x: anchor.midX - diameter / 2,
            y: anchor.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
        let marker = caretDebugPanel ?? NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        caretDebugPanel = marker
        marker.level = .popUpMenu
        marker.isOpaque = false
        marker.backgroundColor = .clear
        marker.hasShadow = false
        marker.ignoresMouseEvents = true
        marker.hidesOnDeactivate = false
        marker.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let dot = NSView(frame: NSRect(origin: .zero, size: rect.size))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        dot.layer?.cornerRadius = diameter / 2
        dot.layer?.borderWidth = 1.5
        dot.layer?.borderColor = NSColor.white.cgColor
        marker.contentView = dot
        marker.setFrame(rect, display: true)
        marker.orderFrontRegardless()
    }

    private func hideCaretDebugMarker() {
        caretDebugPanel?.orderOut(nil)
        rawPointerDebugPanel?.orderOut(nil)
    }

    /// Purple = the raw physical pointer sampled synchronously when ⇧⌃Z fires.
    /// Orange = the final anchor handed to the Zest placement code. In the iWork
    /// ground-zero test these should overlap almost perfectly.
    private func showRawPointerDebugMarker(at point: NSPoint) {
        let diameter: CGFloat = 14
        let rect = NSRect(
            x: point.x - diameter / 2,
            y: point.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        let marker = rawPointerDebugPanel ?? NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        rawPointerDebugPanel = marker
        marker.level = .popUpMenu
        marker.isOpaque = false
        marker.backgroundColor = .clear
        marker.hasShadow = false
        marker.ignoresMouseEvents = true
        marker.hidesOnDeactivate = false
        marker.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let ring = NSView(frame: NSRect(origin: .zero, size: rect.size))
        ring.wantsLayer = true
        ring.layer?.backgroundColor = NSColor.clear.cgColor
        ring.layer?.cornerRadius = diameter / 2
        ring.layer?.borderWidth = 3
        ring.layer?.borderColor = NSColor.systemPurple.cgColor
        marker.contentView = ring
        marker.setFrame(rect, display: true)
        marker.orderFrontRegardless()
    }

    // MARK: - iWork routing

    /// iWork has used more than one bundle-ID spelling across releases/distribution
    /// channels. Never make the pointer bypass depend on one exact identifier again.
    /// Pages/Keynote are recognized from bundle ID first, then the running app name
    /// and executable as hard fallbacks. Numbers is intentionally excluded for now.
    private func isIWorkApplication(_ app: NSRunningApplication) -> Bool {
        let bundle = (app.bundleIdentifier ?? "").lowercased()
        let name = (app.localizedName ?? "").lowercased()
        let executable = (app.executableURL?.lastPathComponent ?? "").lowercased()

        let bundleMatch = bundle.contains("pages") || bundle.contains("keynote")
        let nameMatch = name == "pages" || name == "keynote"
        let executableMatch = executable == "pages" || executable == "keynote"
        return bundleMatch || nameMatch || executableMatch
    }

    private func isPagesApplication(_ app: NSRunningApplication) -> Bool {
        let bundle = (app.bundleIdentifier ?? "").lowercased()
        let name = (app.localizedName ?? "").lowercased()
        let executable = (app.executableURL?.lastPathComponent ?? "").lowercased()
        return bundle.contains("pages") || name == "pages" || executable == "pages"
    }

    private func pagesSummonModifiersAreStillDown() -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let relevant: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
        return !flags.intersection(relevant).isEmpty
    }

    // MARK: - Pages pointer-bootstrap resolver

    private func installPagesPointerTracker() {
        guard pagesPointerMonitor == nil else { return }
        pagesPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      let frontApp = NSWorkspace.shared.frontmostApplication,
                      self.isPagesApplication(frontApp)
                else { return }

                let point = NSEvent.mouseLocation
                guard self.isPlausiblePagesDocumentPoint(point) else {
                    print("🍊 PAGES POINTER ignored non-document click:", NSStringFromPoint(point))
                    return
                }

                self.lastPagesDocumentClick = point
                self.lastPagesDocumentClickTime = ProcessInfo.processInfo.systemUptime
                print("🍊 PAGES POINTER seed:", NSStringFromPoint(point))
            }
        }
    }

    /// Reject obvious toolbar/inspector/chrome clicks. We deliberately keep this
    /// geometric and permissive: Pages' AX hierarchy is exactly what proved stale.
    /// The white document/canvas occupies the central body below the toolbar and
    /// left of the Format inspector, so a real text click should live here.
    private func isPlausiblePagesDocumentPoint(_ point: NSPoint) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXFocusedWindowAttribute as CFString, &windowValue
        ) == .success, let windowValue else { return true }

        let window = unsafeBitCast(windowValue, to: AXUIElement.self)
        guard let axFrame = frame(of: window) else { return true }
        let wf = appKitRect(fromAccessibilityRect: axFrame)

        // Keep title/toolbar and the right-most inspector out of the seed zone.
        let bodyTop = wf.maxY - 72
        let inspectorCutoff = wf.minX + wf.width * 0.84
        return point.x >= wf.minX + 8
            && point.x <= inspectorCutoff
            && point.y >= wf.minY + 8
            && point.y <= bodyTop
    }

    private func pagesPointerCaretRect() -> NSRect? {
        guard let point = lastPagesDocumentClick else { return nil }
        // The click itself is the only live screen-space fact Pages has given us
        // consistently. Use it directly. A tiny vertical caret rectangle keeps all
        // existing placement/debug-marker code unchanged.
        return NSRect(x: point.x, y: point.y - 9, width: 2, height: 18)
    }

    // MARK: Caret geometry

    private func currentCaretRect() -> NSRect? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier
        else { return nil }

        let application = AXUIElementCreateApplication(app.processIdentifier)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success, let focusedValue else { return nil }

        let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)

        // Pages allocation philosophy: physical clicks are bootstrap seeds only.
        // Every summon first forces Pages to publish geometry for the insertion point
        // by briefly selecting one neighbouring glyph and immediately collapsing the
        // selection again. This is the only candidate allowed to outrank the click.
        if isPagesApplication(app) {
            if let liveCaret = pagesCaretByTemporarySelection(
                in: application,
                pid: app.processIdentifier
            ) {
                // Pages can finish a pagination/reflow one frame *after* it has
                // already published the temporary selection. This is most visible
                // when Return creates a new page: the first rectangle is valid for
                // the pre-reflow layout, then the page moves underneath us. Give
                // Pages a short settle window and probe once more. We only replace
                // the first result when the second probe actually moved, so normal
                // summons keep the proven geometry unchanged.
                let stabilized = pagesStabilizedCaretAfterReflow(
                    first: liveCaret,
                    application: application,
                    pid: app.processIdentifier,
                    tableContext: pagesFocusedContextContainsTable(in: application)
                )
                let converted = appKitRect(fromAccessibilityRect: stabilized)
                print("🎯 PAGES CARET → LIVE TEMPORARY SELECTION:", NSStringFromRect(converted))
                return converted
            }

            // Passive Pages AX comes second. It is validated against document geometry
            // by the resolver and can therefore recover cases where the selection probe
            // cannot select a neighbouring glyph (for example some table boundaries).
            if let pagesCaret = pagesDocumentCaret(in: application) {
                let converted = appKitRect(fromAccessibilityRect: pagesCaret)
                print("🍊 PAGES CARET → PASSIVE AX:", NSStringFromRect(converted))
                return converted
            }

            // Last resort: use the last plausible document click. Crucially, we never
            // sample the *current* mouse location here, because the mouse may have been
            // moved far away from the text insertion point since the click.
            if let pointerCaret = pagesPointerCaretRect() {
                print("🟠 PAGES CARET → BOOTSTRAP CLICK FALLBACK:", NSStringFromRect(pointerCaret),
                      "age:", String(format: "%.2f", ProcessInfo.processInfo.systemUptime - lastPagesDocumentClickTime))
                return pointerCaret
            }

            print("⚠️ PAGES CARET: live probe + passive AX + click seed unavailable")
            return nil
        }

        // First ask the focused editor for its actual insertion range. For a
        // collapsed selection many WebKit/Electron controls return no bounds,
        // so probe the neighbouring glyph and reconstruct the caret edge.
        if let range = selectedRange(of: focused),
           let caret = validatedCaretBounds(in: focused, selectedRange: range) {
            return appKitRect(fromAccessibilityRect: caret)
        }

        // Some editors expose the selection on a parent text area rather than
        // the focused descendant. Walk a few AX parents before giving up.
        var element = focused
        for _ in 0..<4 {
            guard let parent = parent(of: element) else { break }
            if let range = selectedRange(of: parent),
               let caret = validatedCaretBounds(in: parent, selectedRange: range) {
                return appKitRect(fromAccessibilityRect: caret)
            }
            element = parent
        }

        // Empty-line WebKit fallback. After Return/Shift-Return the collapsed
        // insertion range can have no zero-length bounds and no following glyph.
        // Anchoring to the whole text area produced the infamous "new empty row"
        // placement. Instead, use the preceding glyph as a line-height reference
        // and advance one line in AX's top-left coordinate system.
        if let range = selectedRange(of: focused), range.length == 0, range.location > 0,
           let previous = bounds(for: CFRange(location: range.location - 1, length: 1), in: focused),
           previous.height > 0, previous.height < 120 {
            let inferred = CGRect(
                x: previous.minX,
                y: previous.maxY,
                width: 2,
                height: max(previous.height, 18)
            )
            if let elementFrame = frame(of: focused), elementFrame.insetBy(dx: -12, dy: -12).intersects(inferred) {
                return appKitRect(fromAccessibilityRect: inferred)
            }
        }

        // A whole editor rectangle is not a caret. If the browser exposes no live
        // insertion geometry, return nil and let the neutral summon fallback win
        // rather than attaching Zest to a random edge/centre of the text field.
        return nil
    }



    // MARK: - Pages live selection probe

    /// Pages can expose a frozen insertion range while still publishing geometry for
    /// an actively painted selection. We exploit that difference for one frame:
    /// Shift-Right selects the glyph immediately after the caret, its bounds reveal
    /// the caret's left edge, and plain Left collapses back to the original caret.
    /// At end-of-text we mirror the operation with Shift-Left / Right and use the
    /// selected glyph's right edge. No text is inserted, deleted, or left selected.
    private func pagesCaretByTemporarySelection(
        in application: AXUIElement,
        pid: pid_t
    ) -> CGRect? {
        guard let source = CGEventSource(stateID: .privateState) else { return nil }

        func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            else { return }
            down.flags = flags
            up.flags = flags
            down.postToPid(pid)
            up.postToPid(pid)
        }

        // Snapshot the stale geometry before touching the editor. We only accept a
        // candidate whose range/geometry becomes an actual non-empty selection.
        let before = pagesSelectionCandidates(in: application)

        // 124 = Right Arrow. Select one glyph to the right of the insertion point.
        postKey(124, flags: .maskShift)
        let afterRight = pagesWaitForChangedSelection(before: before, in: application)

        if let live = afterRight {
            // Plain Left collapses a forward selection onto its original left edge.
            postKey(123)
            usleep(8_000)
            let caret = CGRect(
                x: live.bounds.minX,
                y: live.bounds.minY,
                width: 2,
                height: max(18, live.bounds.height)
            )
            print("🍊 PAGES LIVE PROBE forward selection:", NSStringFromRect(live.bounds))
            return caret
        }

        // Shift-Right may do nothing at the end of a story. Ensure any attempted
        // selection is collapsed, then probe the glyph immediately to the left.
        postKey(123)
        usleep(8_000)
        let beforeLeft = pagesSelectionCandidates(in: application)
        postKey(123, flags: .maskShift)
        let afterLeft = pagesWaitForChangedSelection(before: beforeLeft, in: application)

        if let live = afterLeft {
            // Plain Right collapses a backward selection onto its original right edge.
            postKey(124)
            usleep(8_000)
            let caret = CGRect(
                x: live.bounds.maxX,
                y: live.bounds.minY,
                width: 2,
                height: max(18, live.bounds.height)
            )
            print("🍊 PAGES LIVE PROBE backward selection:", NSStringFromRect(live.bounds))
            return caret
        }

        // Restore the insertion point after the failed left probe as well.
        postKey(124)
        usleep(8_000)
        print("⚠️ PAGES LIVE PROBE: Pages did not publish temporary selection geometry")
        return nil
    }

    /// Pages may paginate asynchronously after a newline. The first temporary
    /// selection can therefore describe the old page position even though it is a
    /// genuine caret. Re-probe after a small layout-settle interval and prefer the
    /// newer rectangle only when the rendered insertion point actually moved.
    private func pagesStabilizedCaretAfterReflow(
        first: CGRect,
        application: AXUIElement,
        pid: pid_t,
        tableContext: Bool
    ) -> CGRect {
        usleep(42_000)
        guard let second = pagesCaretByTemporarySelection(in: application, pid: pid) else {
            print("🍊 PAGES REFLOW CHECK → first caret retained (second probe unavailable)")
            return first
        }

        let dx = abs(second.midX - first.midX)
        let dy = abs(second.midY - first.midY)
        var settled = first
        if dx > 2.0 || dy > 2.0 {
            print("🔄 PAGES REFLOW SETTLED → updated caret",
                  "Δx:", String(format: "%.1f", dx),
                  "Δy:", String(format: "%.1f", dy),
                  "from:", NSStringFromRect(first),
                  "to:", NSStringFromRect(second))
            settled = second
        } else {
            print("🍊 PAGES REFLOW CHECK → caret stable",
                  "Δx:", String(format: "%.1f", dx),
                  "Δy:", String(format: "%.1f", dy))
        }

        // Inline tables are the one Pages layout context that can settle later than
        // ordinary body text, especially when the table touches a pagination boundary.
        // Keep the proven two-probe path everywhere else; table/cell editing alone gets
        // one final delayed confirmation so a page-break reflow cannot leave Zest on
        // the table's pre-pagination rectangle.
        if tableContext {
            usleep(72_000)
            if let third = pagesCaretByTemporarySelection(in: application, pid: pid) {
                let tdx = abs(third.midX - settled.midX)
                let tdy = abs(third.midY - settled.midY)
                if tdx > 2.0 || tdy > 2.0 {
                    print("📊 PAGES TABLE REFLOW → final caret confirmation",
                          "Δx:", String(format: "%.1f", tdx),
                          "Δy:", String(format: "%.1f", tdy))
                    return third
                }
            }
        }
        return settled
    }

    private func pagesFocusedContextContainsTable(in application: AXUIElement) -> Bool {
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXFocusedUIElementAttribute as CFString, &focusedValue
        ) == .success, let focusedValue else { return false }

        var element = unsafeBitCast(focusedValue, to: AXUIElement.self)
        for _ in 0..<14 {
            var roleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
               let role = roleValue as? String {
                let lower = role.lowercased()
                if lower.contains("table") || lower.contains("cell") || lower.contains("row") { return true }
            }
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element, kAXParentAttribute as CFString, &parentValue
            ) == .success, let parentValue else { break }
            element = unsafeBitCast(parentValue, to: AXUIElement.self)
        }
        return false
    }

    private struct PagesSelectionCandidate {
        let element: AXUIElement
        let range: CFRange
        let bounds: CGRect
        let frame: CGRect
    }

    private func pagesSelectionCandidates(in application: AXUIElement) -> [PagesSelectionCandidate] {
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXFocusedWindowAttribute as CFString, &windowValue
        ) == .success, let windowValue else { return [] }
        let window = unsafeBitCast(windowValue, to: AXUIElement.self)
        let windowFrame = frame(of: window)

        var result: [PagesSelectionCandidate] = []
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 1400 {
            let (element, depth) = queue.removeFirst()
            visited += 1

            if let range = selectedRange(of: element), range.length > 0,
               let ef = frame(of: element),
               let b = bounds(for: range, in: element),
               b.width > 0, b.height > 0,
               b.width < 800, b.height < 300,
               !pagesIsInspectorGeometry(ef, caret: b, windowFrame: windowFrame) {
                result.append(PagesSelectionCandidate(element: element, range: range, bounds: b, frame: ef))
            }

            guard depth < 10 else { continue }
            var childrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element, kAXChildrenAttribute as CFString, &childrenValue
            ) == .success, let children = childrenValue as? [AXUIElement] {
                for child in children { queue.append((child, depth + 1)) }
            }
        }
        return result
    }

    /// Pages' accessibility bridge is not frame-synchronous. On large documents it
    /// can take well over the old fixed 24 ms pause to expose the temporary selection.
    /// Poll a few short intervals and stop immediately once fresh geometry appears.
    private func pagesWaitForChangedSelection(
        before: [PagesSelectionCandidate],
        in application: AXUIElement
    ) -> PagesSelectionCandidate? {
        let waits: [useconds_t] = [12_000, 18_000, 28_000, 42_000, 60_000]
        for delay in waits {
            usleep(delay)
            let snapshot = pagesSelectionCandidates(in: application)
            if let changed = pagesChangedSelection(before: before, after: snapshot) {
                print("⚡️ PAGES LIVE PROBE published after", delay, "µs poll")
                return changed
            }
        }
        return nil
    }

    private func pagesChangedSelection(
        before: [PagesSelectionCandidate],
        after: [PagesSelectionCandidate]
    ) -> PagesSelectionCandidate? {
        // A one-character live probe is overwhelmingly more useful than Pages'
        // persistent inspector/document selections. Prefer it, and require either a
        // changed range or changed geometry relative to the pre-probe snapshot.
        let ranked = after.sorted {
            let l = abs($0.range.length - 1)
            let r = abs($1.range.length - 1)
            if l != r { return l < r }
            return $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height
        }

        for candidate in ranked {
            let unchanged = before.contains { old in
                CFEqual(old.element, candidate.element)
                    && old.range.location == candidate.range.location
                    && old.range.length == candidate.range.length
                    && abs(old.bounds.minX - candidate.bounds.minX) < 0.5
                    && abs(old.bounds.minY - candidate.bounds.minY) < 0.5
            }
            if !unchanged { return candidate }
        }
        return nil
    }

    /// Pages 14/15 can expose a stale AXSelectedTextRange / text-marker range until
    /// the editor itself processes a navigation event. Refresh that internal state
    /// without activating Zest and without inheriting the hotkey modifiers.
    ///
    /// This is deliberately Pages-only. Safari, Telegram and normal AppKit editors
    /// keep using the pure Accessibility path above.
    private func pagesRefreshLiveInsertionPoint(pid: pid_t) {
        guard let source = CGEventSource(stateID: .privateState) else { return }

        func postKey(_ keyCode: CGKeyCode) {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            else { return }
            down.flags = []
            up.flags = []
            down.postToPid(pid)
            up.postToPid(pid)
        }

        // 123 = Left Arrow, 124 = Right Arrow. A very short pause gives Pages'
        // editor/AX bridge time to publish the new insertion marker after each key.
        postKey(123)
        usleep(12_000)
        postKey(124)
        usleep(18_000)

        print("🍊 PAGES LIVE REFRESH: synthetic Left/Right handshake completed")
    }

    private func pagesDocumentCaret(in application: AXUIElement) -> CGRect? {
        // Pages does not reliably keep AXSelectedTextRange / AXBoundsForRange in
        // sync with the visible insertion point. Before touching the legacy range
        // path, probe the live text-marker API. Text markers are opaque AX objects
        // owned by Pages and, unlike CFRange, can track the rendered insertion point
        // through scrolling and zooming.
        if let markerCaret = pagesTextMarkerCaret(in: application) {
            print("🍊 PAGES TEXT MARKER CARET:", NSStringFromRect(markerCaret))
            return markerCaret
        }

        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXFocusedWindowAttribute as CFString, &windowValue
        ) == .success, let windowValue else { return nil }

        let window = unsafeBitCast(windowValue, to: AXUIElement.self)
        let windowFrame = frame(of: window)

        // IMPORTANT: Pages often leaves several document text areas in the AX tree,
        // each with a perfectly plausible but stale AXSelectedTextRange. A whole-window
        // scan therefore cannot tell us which range is the live insertion point.
        //
        // The live editor is, however, still represented by the focused AX lineage.
        // Resolve that lineage FIRST and only use the broad candidate scan as a
        // last-resort diagnostic fallback. This is deliberately separate from the
        // Format inspector: candidates on the right side of the Pages window are
        // rejected before their range is considered.
        var focusedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            application, kAXFocusedUIElementAttribute as CFString, &focusedValue
        ) == .success, let focusedValue {
            var element = unsafeBitCast(focusedValue, to: AXUIElement.self)
            for level in 0..<12 {
                if let caret = pagesLiveCaretCandidate(element, windowFrame: windowFrame) {
                    print("🍊 PAGES LIVE CARET lineage level:", level,
                          "caret:", NSStringFromRect(caret))
                    return caret
                }
                guard let next = parent(of: element) else { break }
                element = next
            }

            // Some Pages versions focus a document/canvas group whose editable text
            // area is a descendant rather than a parent. Search only this focused
            // branch before touching the rest of the window.
            var focusedBranch: [(depth: Int, element: AXUIElement)] = [(0, unsafeBitCast(focusedValue, to: AXUIElement.self))]
            var branchVisited = 0
            while !focusedBranch.isEmpty, branchVisited < 350 {
                let item = focusedBranch.removeFirst()
                branchVisited += 1
                if item.depth > 7 { continue }
                if let caret = pagesLiveCaretCandidate(item.element, windowFrame: windowFrame) {
                    print("🍊 PAGES LIVE CARET focused subtree depth:", item.depth,
                          "caret:", NSStringFromRect(caret))
                    return caret
                }
                var childrenValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(
                    item.element, kAXChildrenAttribute as CFString, &childrenValue
                ) == .success, let children = childrenValue as? [AXUIElement] {
                    for child in children { focusedBranch.append((item.depth + 1, child)) }
                }
            }
        }

        // Diagnostic fallback. This keeps older Pages builds usable, but unlike the
        // previous resolver it no longer gives AXFocused a fake scoring advantage:
        // if we reach this path we already proved the focused lineage did not expose
        // the live text range. Prefer large document text areas and collapsed ranges.
        var candidates: [(score: Double, caret: CGRect)] = []
        var visited = 0

        func walk(_ element: AXUIElement, depth: Int) {
            guard depth <= 9, visited < 1200 else { return }
            visited += 1

            if let range = selectedRange(of: element),
               let caret = validatedCaretBounds(in: element, selectedRange: range),
               let elementFrame = frame(of: element),
               !pagesIsInspectorGeometry(elementFrame, caret: caret, windowFrame: windowFrame) {
                let role = stringAttribute(kAXRoleAttribute, of: element) ?? ""
                let area = max(1, elementFrame.width * elementFrame.height)
                var score = log(area) * 20
                if role == (kAXTextAreaRole as String) { score += 300 }
                if boolAttribute(kAXEnabledAttribute, of: element) == true { score += 40 }
                if elementFrame.width >= 420 { score += 200 }
                if elementFrame.height >= 300 { score += 140 }
                if range.length == 0 { score += 180 }
                if let wf = windowFrame {
                    if elementFrame.width < wf.width * 0.22 { score -= 220 }
                    if !wf.insetBy(dx: -8, dy: -8).intersects(caret) { score -= 500 }
                }
                print("🍊 PAGES AX FALLBACK", role,
                      "score:", Int(score),
                      "frame:", NSStringFromRect(elementFrame),
                      "caret:", NSStringFromRect(caret),
                      "range:", range.location, range.length)
                candidates.append((score, caret))
            }

            var childrenValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element, kAXChildrenAttribute as CFString, &childrenValue
            ) == .success, let children = childrenValue as? [AXUIElement] else { return }
            for child in children { walk(child, depth: depth + 1) }
        }

        walk(window, depth: 0)

        // Do NOT return the broad whole-window winner in Pages. In current Pages
        // builds this routinely resolves to a stale AXStaticText page/header node
        // (for example a 950×52 frame with range 0,0). That geometry is valid AX,
        // but it is not the live insertion point. Returning it is worse than having
        // no AX answer because it steals priority from our last real document click.
        if let diagnostic = candidates.max(by: { $0.score < $1.score }) {
            print("⚠️ PAGES AX FALLBACK rejected stale broad candidate:", NSStringFromRect(diagnostic.caret))
        }
        return nil
    }


    /// Pages-specific live-caret probe. We intentionally use attribute names as
    /// strings because the text-marker API is surfaced dynamically by AX clients
    /// and is not represented by a convenient Swift constant. No assumptions are
    /// made about the marker payload; it is passed back to the same AX element.
    private func pagesTextMarkerCaret(in application: AXUIElement) -> CGRect? {
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXFocusedWindowAttribute as CFString, &windowValue
        ) == .success, let windowValue else { return nil }
        let window = unsafeBitCast(windowValue, to: AXUIElement.self)
        let windowFrame = frame(of: window)

        var focusedValue: CFTypeRef?
        let focused: AXUIElement?
        if AXUIElementCopyAttributeValue(
            application, kAXFocusedUIElementAttribute as CFString, &focusedValue
        ) == .success, let focusedValue {
            focused = unsafeBitCast(focusedValue, to: AXUIElement.self)
        } else {
            focused = nil
        }

        // Focus lineage first, then the focused window. The marker attribute is
        // cheap to test and this keeps the normal Pages summon path responsive.
        var roots: [AXUIElement] = []
        if let focused {
            var node: AXUIElement? = focused
            for _ in 0..<12 {
                guard let current = node else { break }
                roots.append(current)
                node = parent(of: current)
            }
        }
        roots.append(window)

        var visited = 0
        var queue: [(AXUIElement, Int)] = roots.map { ($0, 0) }
        while !queue.isEmpty, visited < 900 {
            let (element, depth) = queue.removeFirst()
            visited += 1

            if let rect = textMarkerCaretBounds(in: element),
               let ef = frame(of: element),
               !pagesIsInspectorGeometry(ef, caret: rect, windowFrame: windowFrame) {
                let role = stringAttribute(kAXRoleAttribute, of: element) ?? ""
                print("🍊 PAGES MARKER candidate", role,
                      "depth:", depth,
                      "frame:", NSStringFromRect(ef),
                      "caret:", NSStringFromRect(rect))
                return rect
            }

            guard depth < 9 else { continue }
            var childrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element, kAXChildrenAttribute as CFString, &childrenValue
            ) == .success, let children = childrenValue as? [AXUIElement] {
                for child in children { queue.append((child, depth + 1)) }
            }
        }
        print("⚠️ PAGES TEXT MARKER: no live marker candidate; using legacy range diagnostics")
        return nil
    }

    private func textMarkerCaretBounds(in element: AXUIElement) -> CGRect? {
        let selectedMarkerNames = [
            "AXSelectedTextMarkerRange",
            "AXSelectedTextMarker"
        ]
        let boundsNames = [
            "AXBoundsForTextMarkerRange",
            "AXBoundsForTextMarker"
        ]

        for selectedName in selectedMarkerNames {
            var marker: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element, selectedName as CFString, &marker
            ) == .success, let marker else { continue }

            for boundsName in boundsNames {
                var result: CFTypeRef?
                let error = AXUIElementCopyParameterizedAttributeValue(
                    element, boundsName as CFString, marker, &result
                )
                guard error == .success, let result, CFGetTypeID(result) == AXValueGetTypeID() else { continue }
                var rect = CGRect.zero
                guard AXValueGetValue(unsafeBitCast(result, to: AXValue.self), .cgRect, &rect),
                      rect.origin.x.isFinite, rect.origin.y.isFinite,
                      !rect.isNull, rect.width < 300, rect.height < 300 else { continue }
                return CGRect(
                    x: rect.minX, y: rect.minY,
                    width: max(2, rect.width), height: max(18, rect.height)
                )
            }
        }
        return nil
    }

    private func pagesLiveCaretCandidate(_ element: AXUIElement, windowFrame: CGRect?) -> CGRect? {
        guard let range = selectedRange(of: element),
              let caret = validatedCaretBounds(in: element, selectedRange: range),
              let elementFrame = frame(of: element)
        else { return nil }

        guard !pagesIsInspectorGeometry(elementFrame, caret: caret, windowFrame: windowFrame) else {
            return nil
        }

        let role = stringAttribute(kAXRoleAttribute, of: element) ?? ""
        let isTextRole = role == (kAXTextAreaRole as String)
            || role == (kAXTextFieldRole as String)
            || role == "AXStaticText"

        // Pages' document editor can be surfaced as a text area or as a large
        // document group carrying the selected range. Accept either, but never a
        // tiny formatting control.
        if isTextRole { return caret }
        if let wf = windowFrame,
           elementFrame.width > wf.width * 0.35,
           elementFrame.height > 120 {
            return caret
        }
        return nil
    }

    private func pagesIsInspectorGeometry(
        _ elementFrame: CGRect,
        caret: CGRect,
        windowFrame: CGRect?
    ) -> Bool {
        guard let wf = windowFrame else { return false }
        // Pages' Format inspector occupies the right-most ~20–25% of the window.
        // Keep a generous document-side boundary so zoomed/full-screen layouts do
        // not accidentally turn inspector controls into insertion points.
        let inspectorCutoff = wf.minX + wf.width * 0.75
        if elementFrame.midX > inspectorCutoff || caret.midX > inspectorCutoff {
            return true
        }
        if elementFrame.width < 180 && elementFrame.maxX > inspectorCutoff - 40 {
            return true
        }
        return false
    }

    private func boolAttribute(_ attribute: String, of element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func selectedRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &value
        ) == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range) else { return nil }
        return range
    }

    private func bounds(for range: CFRange, in element: AXUIElement) -> CGRect? {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &result
        ) == .success, let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(unsafeBitCast(result, to: AXValue.self), .cgRect, &rect),
              !rect.isNull, rect.origin.x.isFinite, rect.origin.y.isFinite else { return nil }
        return rect
    }

    /// AXBoundsForRange is unfortunately not equally trustworthy in every app.
    /// Pages in particular can return a geometrically valid rectangle belonging
    /// to its formatting inspector while the actual insertion point is in the
    /// document canvas. Never accept a range rectangle unless it belongs to the
    /// AX element that supplied the selected range.
    private func validatedCaretBounds(in element: AXUIElement, selectedRange: CFRange) -> CGRect? {
        guard let caret = caretBounds(in: element, selectedRange: selectedRange) else { return nil }
        guard let elementFrame = frame(of: element) else { return caret }

        // Carets may sit exactly on the trailing edge of a text object, so allow
        // a small tolerance rather than requiring strict containment.
        let toleranceFrame = elementFrame.insetBy(dx: -12, dy: -12)
        let probe = CGPoint(x: caret.midX, y: caret.midY)
        guard toleranceFrame.contains(probe) else { return nil }
        return caret
    }

    private func caretBounds(in element: AXUIElement, selectedRange: CFRange) -> CGRect? {
        // Native editors generally support the zero-length range directly.
        if let exact = bounds(for: CFRange(location: selectedRange.location, length: 0), in: element),
           exact.width < 40 {
            return CGRect(x: exact.minX, y: exact.minY, width: max(exact.width, 2), height: max(exact.height, 18))
        }

        // Electron/WebKit frequently reject a zero-length AXBoundsForRange.
        // A glyph after the insertion point gives us the caret's left edge.
        if let next = bounds(for: CFRange(location: selectedRange.location, length: 1), in: element),
           next.width < 200 {
            return CGRect(x: next.minX, y: next.minY, width: 2, height: max(next.height, 18))
        }

        // At the end of the field there is no following glyph. Use the right
        // edge of the preceding glyph instead.
        if selectedRange.location > 0,
           let previous = bounds(for: CFRange(location: selectedRange.location - 1, length: 1), in: element),
           previous.width < 200 {
            return CGRect(x: previous.maxX, y: previous.minY, width: 2, height: max(previous.height, 18))
        }
        return nil
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let value else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size)
        else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func appKitRect(fromAccessibilityRect rect: CGRect) -> NSRect {
        // AX/Quartz geometry is display-local with a top-left origin; AppKit
        // windows use a bottom-left origin. Resolve the containing physical
        // display so this also behaves on secondary monitors.
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let displayBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            if displayBounds.intersects(rect) || displayBounds.contains(rect.origin) {
                let x = screen.frame.minX + (rect.minX - displayBounds.minX)
                let y = screen.frame.maxY - (rect.minY - displayBounds.minY) - rect.height
                return NSRect(x: x, y: y, width: max(rect.width, 2), height: max(rect.height, 18))
            }
        }

        let mainMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        return NSRect(x: rect.minX, y: mainMaxY - rect.maxY, width: max(rect.width, 2), height: max(rect.height, 18))
    }

    private func fallbackAnchorRect() -> NSRect {
        let point = NSEvent.mouseLocation
        return NSRect(x: point.x, y: point.y, width: 2, height: 18)
    }

    private func origin(
        for size: NSSize,
        beside anchor: NSRect,
        gap: CGFloat? = nil
    ) -> NSPoint {
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) })
            ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 8
        let placementGap = gap ?? caretGap

        // The 620×360 runtime canvas is centered inside a permanent transparent
        // presentation stage. The visible runtime control is offset +120 on X
        // inside that canvas, so its screen anchor remains deterministic without
        // resizing the NSPanel when feature popups appear.
        let controlCenter = NSPoint(
            x: size.width / 2 + 120,
            y: size.height / 2
        )
        let half: CGFloat = visibleControlHalfSize

        var x = anchor.maxX + placementGap - (controlCenter.x - half)
        if x + controlCenter.x + half > visible.maxX - margin {
            x = anchor.minX - placementGap - (controlCenter.x + half)
        }
        var y = anchor.midY - controlCenter.y

        // Clamp using the visible Zest control, not the transparent host.
        let minX = x + controlCenter.x - half
        let maxX = x + controlCenter.x + half
        if minX < visible.minX + margin { x += (visible.minX + margin) - minX }
        if maxX > visible.maxX - margin { x -= maxX - (visible.maxX - margin) }

        let minY = y + controlCenter.y - half
        let maxY = y + controlCenter.y + half
        if minY < visible.minY + margin { y += (visible.minY + margin) - minY }
        if maxY > visible.maxY - margin { y -= maxY - (visible.maxY - margin) }
        return NSPoint(x: x, y: y)
    }
}


// MARK: - Runtime reset ghost

/// A deliberately non-interactive "home" silhouette shown only while Zest is
/// being dragged. It mirrors the currently selected runtime form factor while
/// staying quieter than the live control, so it reads as a destination rather
/// than a second usable Zest.
private struct ZestRuntimeResetGhost: View {
    let formFactor: ZestFormFactor
    let centerOnlyPage: String
    let accent: Color
    let accentBright: Color
    let accentDeep: Color

    var body: some View {
        ZStack {
            switch formFactor {
            case .orangeSlice:
                orangeSliceGhost
            case .tripleSquare:
                tripleSquareGhost
            case .centerOnly, .turntable:
                centerOnlyGhost
            }
        }
        .opacity(0.82)
    }

    private var orangeSliceGhost: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.075))
                .glassEffect(.regular.tint(accent.opacity(0.18)), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(accent.opacity(0.42), style: StrokeStyle(lineWidth: 1.25, dash: [6, 5]))
                }
                .shadow(color: accentDeep.opacity(0.18), radius: 8, y: 3)

            Circle()
                .stroke(accentBright.opacity(0.34), lineWidth: 18)
                .padding(17)

            resetBadge
        }
        .padding(7)
    }

    private var tripleSquareGhost: some View {
        ZStack(alignment: .bottom) {
            // Mirror the complete Triple Square silhouette: rear Saturn plate,
            // three inset action tiles and the lower settings extrusion.
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(accent.opacity(0.075))
                .frame(width: 199, height: 71)
                .glassEffect(.regular.tint(accent.opacity(0.16)), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(accent.opacity(0.38), style: StrokeStyle(lineWidth: 1.15, dash: [6, 5]))
                }
                .offset(y: -18)

            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(accent.opacity(index == 1 ? 0.15 : 0.10))
                        .glassEffect(
                            .regular.tint(accent.opacity(index == 1 ? 0.24 : 0.18)),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(accent.opacity(0.42), style: StrokeStyle(lineWidth: 1.05, dash: [6, 5]))
                        }
                        .frame(width: 57, height: 57)
                }
            }
            .offset(y: -25)

            Circle()
                .fill(accent.opacity(0.12))
                .glassEffect(.regular.tint(accent.opacity(0.20)), in: Circle())
                .overlay {
                    Circle().strokeBorder(accent.opacity(0.42), style: StrokeStyle(lineWidth: 1.05, dash: [5, 4]))
                }
                .frame(width: 38, height: 38)
                .offset(y: 4)

            resetBadge
                .offset(y: 58)
        }
        .frame(width: 225, height: 174)
        .padding(10)
        .shadow(color: accentDeep.opacity(0.16), radius: 7, y: 3)
    }

    private var centerOnlyGhost: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.085))
                .glassEffect(.regular.tint(accent.opacity(0.19)), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(accent.opacity(0.42), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                }
                .shadow(color: accentDeep.opacity(0.17), radius: 7, y: 3)

            // Hint at the selected Center Only configuration without turning the
            // ghost into a fully rendered/interactive duplicate.
            if centerOnlyPage == "fourFeature" {
                Circle().stroke(accentBright.opacity(0.30), lineWidth: 13).padding(17)
            } else if centerOnlyPage == "twoFeature" {
                Capsule().fill(accentBright.opacity(0.22)).frame(width: 82, height: 34)
            }

            resetBadge
        }
        .padding(7)
    }

    private var resetBadge: some View {
        VStack(spacing: 3) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 22, weight: .semibold))
            Text("Reset")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
        }
        .foregroundStyle(Color.primary.opacity(0.66))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(accent.opacity(0.10))
                .glassEffect(.regular.tint(accent.opacity(0.14)), in: Capsule())
        }
    }
}
