//
//  ZestApp.swift
//  Zest
//

import SwiftUI
import AppKit
import Carbon


// MARK: - Native Global Hot Keys

private extension Notification.Name {
    static let zestCarbonShowZest = Notification.Name("zest.hotkey.showZest")
    static let zestCarbonPreviousInput = Notification.Name("zest.hotkey.previousInput")
    static let zestCarbonNextInput = Notification.Name("zest.hotkey.nextInput")
}

private enum ZestRegisteredHotKeyID: UInt32 {
    case showZest = 1
    case previousInputSource = 2
    case nextInputSource = 3
}

private let zestHotKeySignature: OSType = 0x5A455354 // 'ZEST'

// Carbon invokes this callback from the application event loop. Keep it free of
// app state and bounce back onto the main queue through notifications.
private let zestCarbonHotKeyHandler: EventHandlerUPP = { _, event, _ in
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID(signature: 0, id: 0)
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let name: Notification.Name
    switch hotKeyID.id {
    case ZestRegisteredHotKeyID.showZest.rawValue:
        name = .zestCarbonShowZest
    case ZestRegisteredHotKeyID.previousInputSource.rawValue:
        name = .zestCarbonPreviousInput
    case ZestRegisteredHotKeyID.nextInputSource.rawValue:
        name = .zestCarbonNextInput
    default:
        return OSStatus(eventNotHandledErr)
    }

    DispatchQueue.main.async {
        NotificationCenter.default.post(name: name, object: nil)
    }
    return noErr
}


// MARK: - App Delegate

@MainActor
final class ZestAppDelegate:
    NSObject,
    NSApplicationDelegate {

    let textContextManager =
        TextContextManager()

    let fontLibraryManager =
        FontLibraryManager()

    private var hotKeyEventHandler: EventHandlerRef?
    private var showZestHotKey: EventHotKeyRef?
    private var previousInputHotKey: EventHotKeyRef?
    private var nextInputHotKey: EventHotKeyRef?
    private var hotKeyObservers: [NSObjectProtocol] = []
    private let saturnHUD = ZestSaturnHUDController()
    private let rapidInputSourceManager = InputSourceManager()
    private var menuBarController: ZestMenuBarController?
    let settingsManager = ZestSettingsManager()
    private var keyboardAssistantController: ZestKeyboardAssistantController?
    private var onboardingWindowController: ZestOnboardingWindowController?

    // Global key monitors see every key press on the Mac. Keep the tiny hot
    // path allocation-free: shortcuts are decoded only when defaults change,
    // not three times for every character the user types.
    private var cachedRapidSwitchingEnabled = true
    private var cachedPreviousShortcut: ZestKeyboardShortcut?
    private var cachedNextShortcut: ZestKeyboardShortcut?
    private var cachedShowZestShortcut: ZestKeyboardShortcut = .defaultShowZest
    private var defaultsObserver: NSObjectProtocol?


    // MARK: - Launch

    func applicationDidFinishLaunching(
        _ notification:
            Notification
    ) {

        // Zest is a normal foreground macOS application for its entire lifetime.
        // Keeping the process .regular makes the running state explicit in the
        // Dock and Command-Tab. The Zest assistant itself remains a separate
        // nonactivating, elevated NSPanel, so it can still float above whatever
        // application the user is working in without stealing that app's focus.
        NSApp.setActivationPolicy(
            .regular
        )

        keyboardAssistantController = ZestKeyboardAssistantController(
            textContextManager: textContextManager,
            fontLibraryManager: fontLibraryManager,
            settingsManager: settingsManager
        )

        // AppKit owns the status item directly. Give the dashboard a direct,
        // permission-independent route into the same runtime assistant so the
        // optional Show Zest tile doubles as a release-debugging escape hatch.
        let menuController = ZestMenuBarController(
            textContextManager: textContextManager,
            fontLibraryManager: fontLibraryManager,
            onShowZest: { [weak self] in
                self?.keyboardAssistantController?.showBesideCurrentCaret()
            }
        )
        menuController.start()
        menuBarController = menuController

        let onboarding = ZestOnboardingWindowController(settingsManager: settingsManager)
        onboardingWindowController = onboarding
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--reset-onboarding") {
            settingsManager.resetOnboardingState()
        }
        if !settingsManager.hasCompletedOnboarding || arguments.contains("--show-onboarding") {
            DispatchQueue.main.async { onboarding.show(force: arguments.contains("--show-onboarding")) }
        }

        textContextManager
            .requestAccessibilityPermission()

        installHotKeyObservers()
        refreshShortcutCache()
        installCarbonHotKeys()

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshShortcutCache()
                self?.registerConfiguredHotKeys()
            }
        }

        print("")
        print("==========================================")
        print("🍊 ZEST DEVELOPMENT")
        print("==========================================")
        print("")
        print("System font library is active.")
        print("Temporary Pages probe shortcut: ⌃⌥Z")
        print("")
        print("Development window mode: NORMAL NSWindow")
        print("Window is freely resizable.")
        print("")
        print("==========================================")
        print("")
    }


    // Keep Zest alive as a menu-bar utility even when every ordinary window is closed
    // or another application becomes active. The NSStatusItem is owned for the full
    // application lifetime by this delegate.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Clicking Zest in the Dock must never lead to an apparently empty app.
    // First-run users return to onboarding; afterwards the Dock icon behaves
    // like an explicit request to open/focus Settings on the current Space.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !settingsManager.hasCompletedOnboarding {
            onboardingWindowController?.show()
            return true
        }

        openAndFocusSettingsFromDock()
        return true
    }

    private func openAndFocusSettingsFromDock() {
        NSApp.activate(ignoringOtherApps: true)

        // SwiftUI's Settings scene is still the owner of the window. Ask
        // AppKit to invoke that scene rather than manufacturing a second one.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            focusSettingsWindow()
        }
    }

    // MARK: - Native Global Shortcuts

    private func installHotKeyObservers() {
        let center = NotificationCenter.default

        hotKeyObservers.append(
            center.addObserver(forName: .zestCarbonShowZest, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.keyboardAssistantController?.toggle() }
            }
        )
        hotKeyObservers.append(
            center.addObserver(forName: .zestCarbonPreviousInput, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.performRapidInputSwitch(direction: -1) }
            }
        )
        hotKeyObservers.append(
            center.addObserver(forName: .zestCarbonNextInput, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.performRapidInputSwitch(direction: 1) }
            }
        )
    }

    private func installCarbonHotKeys() {
        guard hotKeyEventHandler == nil else {
            registerConfiguredHotKeys()
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            zestCarbonHotKeyHandler,
            1,
            &eventType,
            nil,
            &hotKeyEventHandler
        )

        guard status == noErr else {
            print("🍊 HOTKEY ERROR → could not install Carbon handler:", status)
            return
        }

        registerConfiguredHotKeys()
    }

    private func refreshShortcutCache() {
        let defaults = UserDefaults.standard

        func decoded(_ key: String) -> ZestKeyboardShortcut? {
            guard let data = defaults.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(ZestKeyboardShortcut.self, from: data)
        }

        cachedRapidSwitchingEnabled =
            defaults.object(forKey: "zest.settings.rapidInputSourceSwitching") == nil
            ? true
            : defaults.bool(forKey: "zest.settings.rapidInputSourceSwitching")

        cachedPreviousShortcut = decoded("zest.settings.saturnPreviousShortcut")
            ?? ZestKeyboardShortcut(keyCode: 123, command: false, option: true, control: true, shift: false)
        cachedNextShortcut = decoded("zest.settings.saturnNextShortcut")
            ?? ZestKeyboardShortcut(keyCode: 124, command: false, option: true, control: true, shift: false)
        cachedShowZestShortcut = decoded("zest.settings.showZestShortcut") ?? .defaultShowZest
    }

    private func registerConfiguredHotKeys() {
        guard hotKeyEventHandler != nil else { return }
        unregisterHotKeys()

        showZestHotKey = registerHotKey(cachedShowZestShortcut, id: .showZest)

        if cachedRapidSwitchingEnabled {
            if let shortcut = cachedPreviousShortcut {
                previousInputHotKey = registerHotKey(shortcut, id: .previousInputSource)
            }
            if let shortcut = cachedNextShortcut {
                nextInputHotKey = registerHotKey(shortcut, id: .nextInputSource)
            }
        }
    }

    private func registerHotKey(
        _ shortcut: ZestKeyboardShortcut,
        id: ZestRegisteredHotKeyID
    ) -> EventHotKeyRef? {
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: zestHotKeySignature, id: id.rawValue)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            carbonModifiers(for: shortcut),
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        if status != noErr {
            print("🍊 HOTKEY ERROR → \(shortcut.displayString) failed with status", status)
            return nil
        }

        print("🍊 HOTKEY REGISTERED →", shortcut.displayString)
        return reference
    }

    private func carbonModifiers(for shortcut: ZestKeyboardShortcut) -> UInt32 {
        var modifiers: UInt32 = 0
        if shortcut.command { modifiers |= UInt32(cmdKey) }
        if shortcut.option { modifiers |= UInt32(optionKey) }
        if shortcut.control { modifiers |= UInt32(controlKey) }
        if shortcut.shift { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    private func unregisterHotKeys() {
        if let showZestHotKey { UnregisterEventHotKey(showZestHotKey) }
        if let previousInputHotKey { UnregisterEventHotKey(previousInputHotKey) }
        if let nextInputHotKey { UnregisterEventHotKey(nextInputHotKey) }
        showZestHotKey = nil
        previousInputHotKey = nil
        nextInputHotKey = nil
    }

    private func performRapidInputSwitch(direction: Int) {
        guard cachedRapidSwitchingEnabled else { return }
        let shouldShowHUD = !NSApp.isActive

        Task { @MainActor in
            if direction < 0 {
                rapidInputSourceManager.selectPrevious()
            } else {
                rapidInputSourceManager.selectNext()
            }

            try? await Task.sleep(for: .milliseconds(90))
            rapidInputSourceManager.refresh()
            NotificationCenter.default.post(
                name: direction < 0 ? .zestSaturnPrevious : .zestSaturnNext,
                object: nil
            )

            if shouldShowHUD {
                try? await Task.sleep(for: .milliseconds(70))
                saturnHUD.show(direction: direction < 0 ? -1 : 1)
            }
        }
    }


    // MARK: - Termination

    func applicationWillTerminate(
        _ notification:
            Notification
    ) {

        unregisterHotKeys()

        if let hotKeyEventHandler {
            RemoveEventHandler(hotKeyEventHandler)
            self.hotKeyEventHandler = nil
        }

        for observer in hotKeyObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        hotKeyObservers.removeAll()

        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }
}


// MARK: - Saturn Shortcut HUD

@MainActor
private final class ZestSaturnHUDController {
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    func show(direction: Int) {
        hideWorkItem?.cancel()

        let source = Self.currentInputSource()
        let accent = ZestAccent(rawValue: UserDefaults.standard.string(forKey: "zest.settings.accent") ?? "orange") ?? .orange
        let view = ZestSaturnHUDView(
            code: source.code,
            name: source.name,
            direction: direction,
            accent: accent
        )

        let panel = panel ?? makePanel()
        let wasVisible = panel.isVisible && panel.alphaValue > 0.01
        self.panel = panel
        panel.contentView = NSHostingView(rootView: view)

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size = NSSize(width: 270, height: 270)
        let frame = NSRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)

        // Do not blink between rapid successive key presses. Once the HUD is
        // on screen, replace/rotate its content in place and only restart the
        // dismissal timer.
        if !wasVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }

        let work = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.20
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
            self.hideWorkItem = nil
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 270, height: 270),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        return panel
    }

    private static func currentInputSource() -> (code: String, name: String) {
        guard let unmanaged = TISCopyCurrentKeyboardInputSource() else { return ("EN", "Input Source") }
        let source = unmanaged.takeRetainedValue()

        func property(_ key: CFString) -> AnyObject? {
            guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
            return Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
        }

        let name = property(kTISPropertyLocalizedName) as? String ?? "Input Source"
        let languages = property(kTISPropertyInputSourceLanguages) as? [String] ?? []
        let raw = languages.first ?? String(name.prefix(2))
        let code = String(raw.split(separator: "-").first ?? Substring(raw)).uppercased()
        return (code, name)
    }
}

struct ZestSaturnHUDView: View {
    let code: String
    let name: String
    let direction: Int
    let accent: ZestAccent
    @State private var appeared = false

    private var palette: ZestAccentPalette { accent.palette }

    var body: some View {
        ZStack {
            // Rear physical glass / bezel — deliberately mirrors the layered
            // glossy language turntable instead of looking like a flat HUD.
            Circle()
                .fill(palette.deep.opacity(0.16))
                .frame(width: 204, height: 204)
                .glassEffect(.regular.tint(palette.primary.opacity(0.16)), in: Circle())
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.70),
                                    palette.highlight.opacity(0.34),
                                    palette.deep.opacity(0.30)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.15
                        )
                        .padding(2)
                }
                .shadow(color: .black.opacity(0.24), radius: 15, y: 8)
                .shadow(color: palette.primary.opacity(0.16), radius: 8, y: 2)

            Circle()
                .fill(
                    RadialGradient(
                        colors: accent.displayColors.map { $0.opacity(0.30) },
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: 112
                    )
                )
                .frame(width: 188, height: 188)
                .glassEffect(.regular.tint(palette.primary.opacity(0.30)), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.50), lineWidth: 0.9)
                        .padding(1)
                }
                .overlay(alignment: .topLeading) {
                    Ellipse()
                        .fill(Color.white.opacity(0.11))
                        .frame(width: 126, height: 52)
                        .blur(radius: 8)
                        .offset(x: 24, y: 14)
                }

            VStack(spacing: 0) {
                Text(code)
                    .font(.system(size: 35, weight: .bold, design: .rounded))
                    .offset(y: -4)

                Spacer().frame(height: 88)

                Text(name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: 146)
            }
            .foregroundStyle(Color.white.opacity(0.94))
            .shadow(color: .black.opacity(0.14), radius: 1, y: 1)
            .rotationEffect(.degrees(appeared ? 0 : Double(direction) * -42))
            .opacity(appeared ? 1 : 0)

            Circle()
                .fill(palette.deep.opacity(0.18))
                .frame(width: 64, height: 64)
                .glassEffect(.regular.tint(palette.primary.opacity(0.46)), in: Circle())
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.66), palette.highlight.opacity(0.30), palette.deep.opacity(0.34)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
                .overlay {
                    Image(systemName: "keyboard")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.94))
                }
        }
        .frame(width: 270, height: 270)
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                appeared = true
            }
        }
    }
}

// MARK: - App

@main
struct ZestApp: App {

    @NSApplicationDelegateAdaptor(
        ZestAppDelegate.self
    )
    private var appDelegate


    var body: some Scene {

        // The original development canvas has been retired. Zest now lives
        // exclusively in the keyboard-assistant panel, menu bar, and Settings.
        // Keeping a WindowGroup here caused the obsolete white "Zest" window
        // to materialize whenever the accessory app became active.

        Settings {
            ZestSettingsView(
                settingsManager: appDelegate.settingsManager
            )
        }

    }
}
