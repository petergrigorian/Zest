//
//  ZestApp.swift
//  Zest
//

import SwiftUI
import AppKit
import Carbon
import CoreGraphics


// MARK: - Native Global Hot Keys

private extension Notification.Name {
    static let zestCarbonShowZest = Notification.Name("zest.hotkey.showZest")
    static let zestCarbonPreviousInput = Notification.Name("zest.hotkey.previousInput")
    static let zestCarbonNextInput = Notification.Name("zest.hotkey.nextInput")
    static let zestCarbonLayoutFixLeader = Notification.Name("zest.hotkey.layoutFixLeader")
    static let zestCarbonLayoutFixTarget = Notification.Name("zest.hotkey.layoutFixTarget")
    static let zestLayoutFixDigitTapped = Notification.Name("zest.layoutFix.digitTapped")
}

private enum ZestRegisteredHotKeyID: UInt32 {
    case showZest = 1
    case previousInputSource = 2
    case nextInputSource = 3
    case layoutFixLeader = 4
}

private let zestHotKeySignature: OSType = 0x5A455354 // 'ZEST'

private let zestLayoutFixDigitKeyCodes: Set<UInt16> = [18, 19, 20, 21, 23, 22, 26, 28, 25]

// Layout Fix only needs raw 1–9 key interception for the short armed window.
// Keep this callback stateless and bounce the key code back to the main actor.
private let zestLayoutFixDigitTapCallback: CGEventTapCallBack = { _, type, event, _ in
    guard type == .keyDown else {
        return Unmanaged.passUnretained(event)
    }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

    if zestLayoutFixDigitKeyCodes.contains(keyCode) || keyCode == 53 {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .zestLayoutFixDigitTapped,
                object: nil,
                userInfo: ["keyCode": NSNumber(value: keyCode)]
            )
        }
        // Swallow the target digit / Escape so the selected text is not altered
        // before Layout Fix replaces it.
        return nil
    }

    return Unmanaged.passUnretained(event)
}

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
    guard hotKeyID.signature == zestHotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }

    let name: Notification.Name
    switch hotKeyID.id {
    case ZestRegisteredHotKeyID.showZest.rawValue:
        name = .zestCarbonShowZest
    case ZestRegisteredHotKeyID.previousInputSource.rawValue:
        name = .zestCarbonPreviousInput
    case ZestRegisteredHotKeyID.nextInputSource.rawValue:
        name = .zestCarbonNextInput
    case ZestRegisteredHotKeyID.layoutFixLeader.rawValue:
        name = .zestCarbonLayoutFixLeader
    case 100...299:
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .zestCarbonLayoutFixTarget,
                object: nil,
                userInfo: ["hotKeyID": hotKeyID.id]
            )
        }
        return noErr
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
    private var layoutFixLeaderHotKey: EventHotKeyRef?
    private var layoutFixTargetHotKeys: [EventHotKeyRef] = []
    private var layoutFixTargetByHotKeyID: [UInt32: ZestLayoutFixTarget] = [:]
    private var layoutFixTargetByKeyCode: [UInt16: ZestLayoutFixTarget] = [:]
    private var layoutFixDigitTap: CFMachPort?
    private var layoutFixDigitTapSource: CFRunLoopSource?
    private var layoutFixSourceApplication: NSRunningApplication?
    private var layoutFixCaptureTask: Task<Void, Never>?
    private var layoutFixArmTimeout: DispatchWorkItem?
    private var hotKeyObservers: [NSObjectProtocol] = []
    private let saturnHUD = ZestSaturnHUDController()
    private let layoutFixHUD = ZestLayoutFixHUDController.shared
    private let rapidInputSourceManager = InputSourceManager()
    private var menuBarController: ZestMenuBarController?
    let settingsManager = ZestSettingsManager()
    private var keyboardAssistantController: ZestKeyboardAssistantController?
    private var onboardingWindowController: ZestOnboardingWindowController?
    private var postUpdateWelcomeController: ZestPostUpdateWelcomeController?
    private var layoutFixServicesProvider: ZestLayoutFixServicesProvider?

    // Global key monitors see every key press on the Mac. Keep the tiny hot
    // path allocation-free: shortcuts are decoded only when defaults change,
    // not three times for every character the user types.
    private var cachedRapidSwitchingEnabled = true
    private var cachedPreviousShortcut: ZestKeyboardShortcut?
    private var cachedNextShortcut: ZestKeyboardShortcut?
    private var cachedShowZestShortcut: ZestKeyboardShortcut = .defaultShowZest
    private var cachedLayoutFixEnabled = true
    private var cachedLayoutFixLeaderShortcut = ZestKeyboardShortcut(
        keyCode: 37, command: false, option: false, control: true, shift: true
    )
    private var cachedLayoutFixTargets: [ZestLayoutFixTarget] = []
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
        
        ZestSettingsBackupService.shared
            .ensureSchemaVersion()

        ZestUpdateManager.shared
            .start()

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

        let forceOnboarding = arguments.contains("--show-onboarding")
        if !settingsManager.hasCompletedOnboarding || forceOnboarding {
            ZestPostUpdateTracker.shared.seedCurrentBuildIfNeeded()
            DispatchQueue.main.async { onboarding.show(force: forceOnboarding) }
        } else if ZestPostUpdateTracker.shared.shouldShowAfterUpdate(
            hasCompletedOnboarding: settingsManager.hasCompletedOnboarding
        ) {
            let postUpdate = ZestPostUpdateWelcomeController(
                settingsManager: settingsManager,
                onDismiss: { [weak self] in
                    self?.finishLaunchFeedback(afterUpdate: true)
                }
            )
            postUpdateWelcomeController = postUpdate
            DispatchQueue.main.async { postUpdate.show() }
        } else {
            finishLaunchFeedback(afterUpdate: false)
        }

        // Accessibility is checked silently at launch. Zest only asks macOS to
        // show its permission UI after an explicit user action in onboarding,
        // Settings, or an Accessibility-dependent feature.
        ZestAccessibilityService.shared.refreshStatus()
        textContextManager.startAutomaticMonitoring()

        // Native macOS Services are now the primary transport for Layout Fix.
        // The source application owns the selection and hands it to Zest through
        // the Services pasteboard, then reads Zest's returned text back into the
        // same selection. This avoids AX selection scraping and synthetic Copy/Paste.
        let servicesProvider = ZestLayoutFixServicesProvider(settingsManager: settingsManager)
        layoutFixServicesProvider = servicesProvider
        NSApp.servicesProvider = servicesProvider
        NSUpdateDynamicServices()
        print("⌨️ LAYOUT FIX SERVICES → provider registered")

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


    private func finishLaunchFeedback(afterUpdate: Bool) {
        Task { @MainActor in
            let notifications = ZestNotificationService.shared
            await notifications.presentLaunchPermissionExplanationIfNeeded()

            if afterUpdate {
                await notifications.deliverUpdateInstalled(
                    version: ZestPostUpdateTracker.shared.currentVersion,
                    build: ZestPostUpdateTracker.shared.currentBuild
                )
            }

            if settingsManager.notifyWhenZestStarts {
                await notifications.deliverLaunchNotification()
            }
        }
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
            center.addObserver(
                forName: .zestAccessibilityStatusDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard ZestAccessibilityService.shared.isTrusted else { return }
                    self?.textContextManager.startAutomaticMonitoring()
                }
            }
        )

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
        hotKeyObservers.append(
            center.addObserver(forName: .zestCarbonLayoutFixLeader, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.armLayoutFixTargets() }
            }
        )
        hotKeyObservers.append(
            center.addObserver(forName: .zestLayoutFixConfigurationDidSave, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshShortcutCache()
                    self?.registerConfiguredHotKeys()
                    print("⌨️ LAYOUT FIX HOTKEYS REBOUND AFTER SAVE")
                }
            }
        )
        hotKeyObservers.append(
            center.addObserver(forName: .zestCarbonLayoutFixTarget, object: nil, queue: .main) { [weak self] note in
                let id: UInt32?
                if let raw = note.userInfo?["hotKeyID"] as? UInt32 {
                    id = raw
                } else if let number = note.userInfo?["hotKeyID"] as? NSNumber {
                    id = number.uint32Value
                } else {
                    id = nil
                }
                guard let id else { return }
                Task { @MainActor in self?.performLayoutFixTarget(hotKeyID: id) }
            }
        )
        hotKeyObservers.append(
            center.addObserver(forName: .zestLayoutFixDigitTapped, object: nil, queue: .main) { [weak self] note in
                guard let number = note.userInfo?["keyCode"] as? NSNumber else { return }
                let keyCode = UInt16(number.uint16Value)
                Task { @MainActor in
                    if keyCode == 53 {
                        self?.clearLayoutFixTargetHotKeys()
                    } else {
                        self?.performLayoutFixTarget(keyCode: keyCode)
                    }
                }
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

        cachedLayoutFixEnabled =
            defaults.object(forKey: "zest.settings.layoutFixEnabled") == nil
            ? true
            : defaults.bool(forKey: "zest.settings.layoutFixEnabled")
        cachedLayoutFixLeaderShortcut =
            decoded("zest.settings.layoutFixLeaderShortcut")
            ?? ZestKeyboardShortcut(
                keyCode: 37,
                command: false,
                option: false,
                control: true,
                shift: true
            )
        if let data = defaults.data(forKey: "zest.settings.layoutFixTargets"),
           let decodedTargets = try? JSONDecoder().decode([ZestLayoutFixTarget].self, from: data) {
            cachedLayoutFixTargets = decodedTargets
        } else {
            cachedLayoutFixTargets = []
        }
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

        // v25: Layout Fix selection transport is provided by native macOS
        // Services. Do not register the legacy leader hotkey here; it cannot
        // invoke another application's Services responder chain and would only
        // route users back into the retired AX/clipboard capture experiment.
        layoutFixLeaderHotKey = nil
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
        if let layoutFixLeaderHotKey { UnregisterEventHotKey(layoutFixLeaderHotKey) }
        clearLayoutFixTargetHotKeys()
        showZestHotKey = nil
        previousInputHotKey = nil
        nextInputHotKey = nil
        layoutFixLeaderHotKey = nil
    }

    private func registerRawHotKey(
        keyCode: UInt16,
        modifiers: UInt32,
        id: UInt32
    ) -> EventHotKeyRef? {
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: zestHotKeySignature, id: id)
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status != noErr {
            print("⌨️ LAYOUT FIX TARGET HOTKEY ERROR → keyCode", keyCode, "modifiers", modifiers, "status", status)
            return nil
        }
        return reference
    }

    private func armLayoutFixTargets() {
        guard cachedLayoutFixEnabled else { return }

        clearLayoutFixTargetHotKeys()

        // The leader stage must always be visible first. Context capture is a
        // downstream concern and must never be allowed to make the global
        // shortcut appear dead.
        layoutFixHUD.showArmed()
        print("⌨️ LAYOUT FIX LEADER → fired; targets:", cachedLayoutFixTargets.count)

        guard !cachedLayoutFixTargets.isEmpty else {
            layoutFixHUD.showFailure(message: "Configure targets")
            return
        }

        layoutFixCaptureTask?.cancel()
        layoutFixCaptureTask = nil

        if let application = NSWorkspace.shared.frontmostApplication,
           application.bundleIdentifier != Bundle.main.bundleIdentifier {
            layoutFixSourceApplication = application

            // Freeze the selection at leader time while the source application
            // still owns focus. The number stage chooses only the destination.
            layoutFixCaptureTask = Task { @MainActor in
                await ZestKeyboardLayoutFixService.shared
                    .primeExternalSelectionBeforeActivation(from: application)
            }

            print("⌨️ LAYOUT FIX SOURCE →", application.localizedName ?? "<unknown>")
        } else {
            // Do not abort the armed state. The service also remembers the last
            // external editor and the target stage can fall back to that context.
            layoutFixSourceApplication = nil
            print("⌨️ LAYOUT FIX SOURCE → frontmost app unavailable; keeping armed state")
        }

        let leaderModifiers = carbonModifiers(for: cachedLayoutFixLeaderShortcut)

        for (index, target) in cachedLayoutFixTargets.enumerated() {
            layoutFixTargetByKeyCode[target.triggerKeyCode] = target

            // Carbon registrations remain as a fallback. The temporary event tap
            // below is the primary target-key path because it can swallow the digit
            // and preserve the selected text.
            let bareID = UInt32(100 + index)
            if let ref = registerRawHotKey(
                keyCode: target.triggerKeyCode,
                modifiers: 0,
                id: bareID
            ) {
                layoutFixTargetHotKeys.append(ref)
                layoutFixTargetByHotKeyID[bareID] = target
            }

            let heldID = UInt32(200 + index)
            if let ref = registerRawHotKey(
                keyCode: target.triggerKeyCode,
                modifiers: leaderModifiers,
                id: heldID
            ) {
                layoutFixTargetHotKeys.append(ref)
                layoutFixTargetByHotKeyID[heldID] = target
            }
        }

        installLayoutFixDigitTap()

        let timeout = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.layoutFixHUD.showFailure(message: "Timed out")
                self?.clearLayoutFixTargetHotKeys()
            }
        }
        layoutFixArmTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: timeout)
    }

    private func installLayoutFixDigitTap() {
        stopLayoutFixDigitTap()

        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: zestLayoutFixDigitTapCallback,
            userInfo: nil
        ) else {
            print("⌨️ LAYOUT FIX DIGIT TAP → unavailable; Carbon target fallback remains active")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        layoutFixDigitTap = tap
        layoutFixDigitTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("⌨️ LAYOUT FIX DIGIT TAP → armed")
    }

    private func stopLayoutFixDigitTap() {
        if let tap = layoutFixDigitTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = layoutFixDigitTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        layoutFixDigitTap = nil
        layoutFixDigitTapSource = nil
    }

    private func performLayoutFixTarget(hotKeyID: UInt32) {
        guard let target = layoutFixTargetByHotKeyID[hotKeyID] else { return }
        performLayoutFixTarget(target: target)
    }

    private func performLayoutFixTarget(keyCode: UInt16) {
        guard let target = layoutFixTargetByKeyCode[keyCode] else { return }
        performLayoutFixTarget(target: target)
    }

    private func performLayoutFixTarget(target: ZestLayoutFixTarget) {
        let application = layoutFixSourceApplication ?? NSWorkspace.shared.frontmostApplication
        guard let application,
              application.bundleIdentifier != Bundle.main.bundleIdentifier
        else {
            layoutFixHUD.showFailure(message: "No source app")
            clearLayoutFixTargetHotKeys()
            return
        }

        rapidInputSourceManager.refresh()
        let sources = rapidInputSourceManager.sources
        let preferredSourceID = rapidInputSourceManager.currentSource?.id
        let targetSource = rapidInputSourceManager.source(withID: target.inputSourceID)
        let targetCode = targetSource?.shortLabel ?? "…"
        let targetName = targetSource?.name ?? "Layout"

        // Transition immediately from the armed ellipsis to the requested source.
        layoutFixHUD.showPending(targetCode: targetCode, targetName: targetName)
        clearLayoutFixTargetHotKeys(preserveHUD: true)

        Task { @MainActor in
            // If leader-time clipboard capture is still completing, wait for it
            // before attempting the mapping. This keeps the selected text frozen
            // across the leader -> digit transition.
            if let captureTask = layoutFixCaptureTask {
                await captureTask.value
                layoutFixCaptureTask = nil
            }

            guard let result = await ZestKeyboardLayoutFixService.shared.performShortcutFix(
                target: target,
                from: application,
                installedSources: sources,
                preferredSourceID: preferredSourceID
            ) else {
                layoutFixHUD.showFailure(message: "No selected text")
                return
            }

            if let targetSource {
                rapidInputSourceManager.select(targetSource)
            }

            layoutFixHUD.show(
                targetCode: result.targetCode,
                targetName: result.targetName
            )
        }
    }

    private func clearLayoutFixTargetHotKeys(preserveHUD: Bool = false) {
        layoutFixArmTimeout?.cancel()
        layoutFixArmTimeout = nil
        stopLayoutFixDigitTap()

        for ref in layoutFixTargetHotKeys {
            UnregisterEventHotKey(ref)
        }
        layoutFixTargetHotKeys.removeAll()
        layoutFixTargetByHotKeyID.removeAll()
        layoutFixTargetByKeyCode.removeAll()
        layoutFixSourceApplication = nil

        if !preserveHUD {
            // The HUD owns its own dismissal timer. Nothing else to do here.
        }
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
