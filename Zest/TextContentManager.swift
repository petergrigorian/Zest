//
//  TextContextManager.swift
//  Zest
//
//  Automatic Pages Formatting Context
//

import Foundation
import AppKit
import ApplicationServices
import Combine


// MARK: - Text Context Manager

@MainActor
final class TextContextManager: ObservableObject {

    // MARK: Published State

    @Published private(set) var isAccessibilityTrusted = false
    @Published private(set) var applicationName: String?
    @Published private(set) var role: String?

    @Published private(set) var fontSize: Double?
    @Published private(set) var fontName: String?
    @Published private(set) var fontFamily: String?
    @Published private(set) var fontTypeface: String?

    @Published private(set) var hasTextContext = false
    @Published private(set) var statusMessage = "Not checked yet"


    // MARK: Scan Limits

    private let maximumDepth = 12
    private let maximumElements = 1500


    // MARK: Automatic Refresh

    private let automaticRefreshDelay: TimeInterval = 0.28

    private var pendingAutomaticRefresh:
        DispatchWorkItem?


    // MARK: AX Observer State

    private var axObserver: AXObserver?

    private var observedApplicationElement:
        AXUIElement?

    private var observedPID:
        pid_t?

    private var observedApplicationName:
        String?

    private var workspaceActivationObserver:
        NSObjectProtocol?


    // MARK: Pages Font-Size Write Cache

    private var cachedPagesFontSizeField:
        AXUIElement?

    private var cachedPagesFontSizeFieldPID:
        pid_t?


    // MARK: Pages Font-Family Write Cache

    //
    // We cache only the persistent AXPopUpButton.
    //
    // The AXMenu and its AXMenuItems are temporary
    // objects created whenever Pages opens the menu,
    // so those are intentionally never cached.

    private var cachedPagesFontFamilyButton:
        AXUIElement?

    private var cachedPagesFontFamilyButtonPID:
        pid_t?


    // MARK: Pages Typeface Read Cache

    private var cachedPagesTypefaceButton:
        AXUIElement?

    private var cachedPagesTypefaceButtonPID:
        pid_t?


    // MARK: Font Menu Retry

    private let fontMenuRetryDelay:
        TimeInterval = 0.05

    private let fontMenuMaximumAttempts = 10


    // MARK: Notifications

    private let observedNotifications: [String] = [
        kAXFocusedUIElementChangedNotification,
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXValueChangedNotification
    ]


    // MARK: - Permission

    func requestAccessibilityPermission() {

        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt
                .takeUnretainedValue() as String: true
        ]

        isAccessibilityTrusted =
            AXIsProcessTrustedWithOptions(
                options
            )

        print("")
        print("🍊 ACCESSIBILITY CHECK")
        print(
            "Trusted:",
            isAccessibilityTrusted
        )

        statusMessage =
            isAccessibilityTrusted
            ? "Accessibility permission granted"
            : "Accessibility permission required"

        guard isAccessibilityTrusted else {
            return
        }

        startAutomaticMonitoring()
    }


    // MARK: - Start Automatic Monitoring

    func startAutomaticMonitoring() {

        guard AXIsProcessTrusted() else {

            isAccessibilityTrusted = false

            statusMessage =
                "Accessibility permission required"

            return
        }

        isAccessibilityTrusted = true

        installWorkspaceActivationObserver()

        observeFrontmostApplication()

        print("")
        print("==========================================")
        print("🍊 ZEST AUTOMATIC CONTEXT MONITOR")
        print("==========================================")
        print("Automatic monitoring is active.")
        print("Context refresh is debounced to 200 ms.")
        print("Pages uses strict semantic formatting detection.")
        print("Pages automatically reads font size and font family.")
        print("Pages font-size writes use a validated AX cache.")
        print("Pages font-family writes use the semantic AX popup.")
        print("==========================================")
        print("")
    }


    // MARK: - Workspace Observer

    private func installWorkspaceActivationObserver() {

        guard
            workspaceActivationObserver == nil
        else {
            return
        }

        workspaceActivationObserver =
            NSWorkspace.shared
                .notificationCenter
                .addObserver(
                    forName:
                        NSWorkspace
                            .didActivateApplicationNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in

                    guard
                        let application =
                            notification.userInfo?[
                                NSWorkspace
                                    .applicationUserInfoKey
                            ]
                            as? NSRunningApplication
                    else {
                        return
                    }

                    Task { @MainActor in

                        guard let self else {
                            return
                        }

                        if application.bundleIdentifier
                            == Bundle.main.bundleIdentifier
                        {
                            return
                        }

                        self.observe(
                            application:
                                application
                        )
                    }
                }
    }


    // MARK: - Observe Frontmost Application

    private func observeFrontmostApplication() {

        guard
            let application =
                NSWorkspace.shared
                    .frontmostApplication
        else {
            return
        }

        if application.bundleIdentifier
            == Bundle.main.bundleIdentifier
        {
            return
        }

        observe(
            application:
                application
        )
    }


    // MARK: - Observe Application

    private func observe(
        application: NSRunningApplication
    ) {

        let pid =
            application.processIdentifier

        if observedPID == pid {

            scheduleAutomaticRefresh()
            return
        }

        invalidatePagesFontSizeFieldCache(
            reason:
                "Target application changed"
        )

        invalidatePagesFontFamilyButtonCache(
            reason:
                "Target application changed"
        )

        removeCurrentAXObserver()

        pendingAutomaticRefresh?
            .cancel()

        pendingAutomaticRefresh = nil

        let appName =
            application.localizedName
            ?? "Unknown"

        var newObserver:
            AXObserver?

        let creationResult =
            AXObserverCreate(
                pid,
                { _, _, notification, refcon in

                    guard let refcon else {
                        return
                    }

                    let manager =
                        Unmanaged<TextContextManager>
                            .fromOpaque(
                                refcon
                            )
                            .takeUnretainedValue()

                    let notificationName =
                        notification as String

                    Task { @MainActor in

                        manager
                            .receivedAutomaticNotification(
                                notificationName
                            )
                    }
                },
                &newObserver
            )

        guard
            creationResult == .success,
            let newObserver
        else {

            print("")
            print(
                "❌ Could not observe \(appName):",
                axErrorName(
                    creationResult
                )
            )
            print("")

            clearContext(
                message:
                    "Could not observe \(appName)"
            )

            return
        }

        let applicationElement =
            AXUIElementCreateApplication(
                pid
            )

        let refcon =
            Unmanaged
                .passUnretained(self)
                .toOpaque()

        var registeredCount = 0

        for notificationName
            in observedNotifications
        {
            // kAXValueChanged is extremely noisy in editors such as Xcode.
            // Zest 1.x only needs continuous formatting tracking in Pages;
            // generic applications are still refreshed when focus/window
            // context changes, but no longer trigger a 1500-node AX scan on
            // practically every keystroke.
            if notificationName == kAXValueChangedNotification,
               appName != "Pages" {
                continue
            }

            let result =
                AXObserverAddNotification(
                    newObserver,
                    applicationElement,
                    notificationName
                        as CFString,
                    refcon
                )

            if result == .success {
                registeredCount += 1
            }
        }

        let runLoopSource =
            AXObserverGetRunLoopSource(
                newObserver
            )

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            runLoopSource,
            .commonModes
        )

        axObserver =
            newObserver

        observedApplicationElement =
            applicationElement

        observedPID =
            pid

        observedApplicationName =
            appName

        applicationName =
            appName

        print("")
        print(
            "🍊 Monitoring:",
            appName
        )

        print(
            "   AX notifications:",
            registeredCount
        )

        scheduleAutomaticRefresh()
    }


    // MARK: - Receive Automatic Notification

    private func receivedAutomaticNotification(
        _ notificationName: String
    ) {

        switch notificationName {

        case kAXValueChangedNotification,
             kAXFocusedUIElementChangedNotification,
             kAXFocusedWindowChangedNotification,
             kAXMainWindowChangedNotification:

            scheduleAutomaticRefresh()

        default:
            break
        }
    }


    // MARK: - Debounce

    private func scheduleAutomaticRefresh() {

        pendingAutomaticRefresh?
            .cancel()

        let workItem =
            DispatchWorkItem { [weak self] in
                // This work item is always scheduled on DispatchQueue.main,
                // so creating another MainActor Task here only adds churn.
                MainActor.assumeIsolated {
                    self?.performAutomaticRefresh()
                }
            }

        pendingAutomaticRefresh =
            workItem

        DispatchQueue.main
            .asyncAfter(
                deadline:
                    .now()
                    + automaticRefreshDelay,
                execute:
                    workItem
            )
    }


    // MARK: - Automatic Refresh

    private func performAutomaticRefresh() {

        pendingAutomaticRefresh = nil

        guard AXIsProcessTrusted() else {

            clearContext(
                message:
                    "Accessibility permission required"
            )

            return
        }

        guard
            let pid =
                observedPID
        else {
            return
        }

        guard
            NSRunningApplication(
                processIdentifier:
                    pid
            )
            != nil
        else {

            invalidatePagesFontSizeFieldCache(
                reason:
                    "Observed application closed"
            )

            invalidatePagesFontFamilyButtonCache(
                reason:
                    "Observed application closed"
            )

            invalidatePagesTypefaceButtonCache(
                reason:
                    "Observed application closed"
            )

            removeCurrentAXObserver()

            clearContext(
                message:
                    "Observed application closed"
            )

            return
        }

        let applicationElement =
            AXUIElementCreateApplication(
                pid
            )

        guard
            let window =
                copyAXElement(
                    from:
                        applicationElement,
                    attribute:
                        kAXFocusedWindowAttribute
                )
                ??
                copyAXElement(
                    from:
                        applicationElement,
                    attribute:
                        kAXMainWindowAttribute
                )
        else {

            clearContext(
                message:
                    "No active text context"
            )

            return
        }

        // =========================================
        // APPLICATION CLASSIFICATION
        // =========================================

        let isPages =
            observedApplicationName
                == "Pages"

        // =========================================
        // FORMATTING CONTEXT
        // =========================================

        // Pages exposes stable semantic controls in its Format inspector.
        // Once discovered, use the cached AX elements directly instead of
        // recursively walking up to ~1500 AX nodes three separate times on
        // every value-change notification. This is the hot path while typing.
        if isPages {

            guard
                let sizeField =
                    resolvePagesFontSizeField(
                        in: window,
                        pid: pid
                    ),
                let rawSize =
                    stringValue(
                        from: sizeField
                    ),
                let parsedSize =
                    parsePointSize(
                        rawSize
                    )
            else {

                clearContext(
                    message:
                        "Pages font-size field unavailable"
                )

                return
            }

            var detectedFontFamily:
                String?

            if let familyButton =
                resolvePagesFontFamilyButton(
                    in: window,
                    pid: pid
                ),
               let rawFamily =
                stringValue(
                    from: familyButton
                )
            {
                let normalized =
                    normalizeFontName(
                        rawFamily
                    )

                if !normalized.isEmpty {
                    detectedFontFamily =
                        normalized
                }
            }

            var detectedTypeface:
                String?

            if let typefaceButton =
                resolvePagesTypefaceButton(
                    in: window,
                    pid: pid
                ),
               let rawTypeface =
                stringValue(
                    from: typefaceButton
                )
            {
                let normalized =
                    normalizeFontName(
                        rawTypeface
                    )

                if !normalized.isEmpty {
                    detectedTypeface =
                        normalized
                }
            }

            let candidate =
                PointSizeFieldCandidate(
                    element: sizeField,
                    role: roleName(of: sizeField),
                    rawValue: rawSize,
                    size: parsedSize,
                    enabled: true,
                    focused: false,
                    title: nil,
                    description: nil,
                    help: "Set the font size.",
                    ancestorTrail: []
                )

            publishAutomaticCandidate(
                candidate,
                detectedFontFamily:
                    detectedFontFamily,
                detectedTypeface:
                    detectedTypeface
            )

            return
        }

        // Non-Pages applications keep the generic discovery path.
        var scannedCount = 0

        var matches:
            [PointSizeFieldCandidate] = []

        scanForPointSizeFields(
            window,
            depth: 0,
            scannedCount:
                &scannedCount,
            matches:
                &matches
        )

        guard
            let winner =
                bestCandidate(
                    from: matches
                )
        else {

            clearContext(
                message:
                    "No font-size context"
            )

            return
        }

        let detectedFontFamily:
            String? = nil

        let detectedTypeface:
            String? = nil

        // =========================================
        // PUBLISH
        // =========================================

        publishAutomaticCandidate(
            winner,
            detectedFontFamily: detectedFontFamily,
            detectedTypeface: detectedTypeface
        )
    }


    // MARK: - Publish Automatic Result

    private func publishAutomaticCandidate(
        _ candidate: PointSizeFieldCandidate,
        detectedFontFamily: String?,
        detectedTypeface: String?
    ) {

        let previousSize =
            fontSize

        let previousFontFamily =
            fontFamily

        fontSize =
            candidate.size

        fontFamily = detectedFontFamily
        fontTypeface = detectedTypeface
        fontName = detectedFontFamily

        role =
            candidate.role

        hasTextContext =
            true

        applicationName =
            observedApplicationName

        if let detectedFontFamily {

            statusMessage =
                "\(detectedFontFamily), \(formatSize(candidate.size)) pt"

        } else {

            statusMessage =
                "Font size: \(formatSize(candidate.size)) pt"
        }

        if previousSize
            != candidate.size
        {
            print(
                "🍊 AUTO SIZE → \(formatSize(candidate.size)) pt"
            )
        }

        if previousFontFamily
            != detectedFontFamily
        {

            if let detectedFontFamily {

                print(
                    "🍊 AUTO FONT → \(detectedFontFamily)"
                )

            } else if previousFontFamily != nil {

                print(
                    "🍊 AUTO FONT → —"
                )
            }
        }
    }


    // MARK: - Production Pages Font-Family Setter

    func setFontFamily(
        _ requestedFamily:
            String
    ) {

        let requested =
            normalizeFontName(
                requestedFamily
            )

        print("")
        print("==========================================")
        print("🍊 ZEST SET FONT FAMILY")
        print("==========================================")
        print(
            "Requested family:",
            "\"\(requested)\""
        )
        print("")

        guard
            !requested.isEmpty
        else {

            print(
                "❌ Requested font family is empty."
            )

            finishFontFamilyWrite()
            return
        }

        guard AXIsProcessTrusted() else {

            print(
                "❌ Accessibility permission is not active."
            )

            finishFontFamilyWrite()
            return
        }

        guard
            let targetPID =
                observedPID,
            let targetApplication =
                NSRunningApplication(
                    processIdentifier:
                        targetPID
                )
        else {

            print(
                "❌ No remembered target application is available."
            )

            finishFontFamilyWrite()
            return
        }

        let appName =
            targetApplication.localizedName
            ?? observedApplicationName
            ?? "Unknown"

        print(
            "Target application:",
            appName
        )

        print(
            "Target PID:",
            targetPID
        )

        guard
            targetApplication.bundleIdentifier ==
                "com.apple.Pages"
            || appName == "Pages"
        else {

            print(
                "❌ The remembered target application is not Pages."
            )

            finishFontFamilyWrite()
            return
        }


        // =========================================
        // SILENT SELECTED-TEXT FONT FAMILY PATH
        // =========================================
        //
        // Zest's current development window is activating.
        // Restore Pages first so its selection + Copy command
        // are available to PagesSilentFontWriter.
        //
        // IMPORTANT:
        // We intentionally do NOT continue into the visible
        // AX popup fallback from this invocation. Otherwise
        // Pages' own font dropdown briefly flashes onscreen.
        // =========================================

        print("")
        print("🍊 SILENT FONT FAMILY REQUEST")
        print("Requested:", requested)
        print("PID:", targetPID)
        print("Restoring Pages focus before silent write...")

        targetApplication.activate(options: [])

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.10
        ) { [weak self] in

            Task { @MainActor in

                guard let self else {
                    return
                }

                let silentResult =
                    PagesSilentFontWriter.apply(
                        family:
                            requested,
                        pid:
                            targetPID
                    )

                switch silentResult {

                case .applied(
                    let canonicalFamily
                ):

                    print("")
                    print(
                        "⚡️ SILENT FONT FAMILY WRITE COMPLETE"
                    )

                    print(
                        "Pages selection now uses:",
                        "\"\(canonicalFamily)\""
                    )

                    self.fontFamily =
                        canonicalFamily

                    self.fontName =
                        canonicalFamily

                    self.hasTextContext =
                        true

                    self.applicationName =
                        self.observedApplicationName

                    self.updateStatusMessage()

                    self.scheduleAutomaticRefresh()

                    self.finishFontFamilyWrite()


                case .noSelection:

                    print("")
                    print(
                        "🧪 SILENT FONT FAMILY STOP → writer reported no selection"
                    )

                    print(
                        "🧪 Visible Pages popup fallback intentionally DISABLED"
                    )

                    self.scheduleAutomaticRefresh()

                    self.finishFontFamilyWrite()


                case .failed(
                    let reason
                ):

                    print("")
                    print(
                        "❌ SILENT FONT FAMILY STOP → \(reason)"
                    )

                    print(
                        "🧪 Visible Pages popup fallback intentionally DISABLED"
                    )

                    self.scheduleAutomaticRefresh()

                    self.finishFontFamilyWrite()
                }
            }
        }

        return


        // =========================================
        // EXISTING AX POPUP FALLBACK
        //
        // Used for:
        //
        // 1. collapsed caret / typing font
        // 2. any silent-backend safety failure
        //
        // Nothing below changes the existing
        // proven fallback architecture.
        // =========================================

        let applicationElement =
            AXUIElementCreateApplication(
                targetPID
            )

        guard
            let window =
                copyAXElement(
                    from:
                        applicationElement,
                    attribute:
                        kAXFocusedWindowAttribute
                )
                ??
                copyAXElement(
                    from:
                        applicationElement,
                    attribute:
                        kAXMainWindowAttribute
                )
        else {

            print(
                "❌ Could not obtain the active Pages window."
            )

            finishFontFamilyWrite()
            return
        }

        guard
            let fontFamilyButton =
                resolvePagesFontFamilyButton(
                    in:
                        window,
                    pid:
                        targetPID
                )
        else {

            print(
                "❌ Could not resolve the Pages font-family control."
            )

            finishFontFamilyWrite()
            return
        }

        guard
            let currentRaw =
                stringValue(
                    from:
                        fontFamilyButton
                )
        else {

            invalidatePagesFontFamilyButtonCache(
                reason:
                    "Cached font-family button could not provide AXValue"
            )

            print(
                "❌ Could not read the current Pages font family."
            )

            finishFontFamilyWrite()
            return
        }

        let current =
            normalizeFontName(
                currentRaw
            )

        print(
            "Current family:",
            "\"\(current)\""
        )

        if fontNamesMatch(
            current,
            requested
        ) {

            print("")
            print(
                "✅ Already using the requested font family."
            )

            fontFamily =
                current

            fontName =
                current

            updateStatusMessage()

            scheduleAutomaticRefresh()

            finishFontFamilyWrite()
            return
        }


        // =========================================
        // OPEN PAGES FONT MENU
        // =========================================

        let actions =
            actionNames(
                of:
                    fontFamilyButton
            )

        guard
            actions.contains(
                kAXShowMenuAction
            )
        else {

            invalidatePagesFontFamilyButtonCache(
                reason:
                    "Font-family button no longer exposes AXShowMenu"
            )

            print(
                "❌ Pages font-family button does not expose AXShowMenu."
            )

            print(
                "Available actions:",
                actions
            )

            finishFontFamilyWrite()
            return
        }

        print("")
        print(
            "▶️ Opening Pages font menu..."
        )

        let showResult =
            AXUIElementPerformAction(
                fontFamilyButton,
                kAXShowMenuAction
                    as CFString
            )

        print(
            "AXShowMenu:",
            axErrorName(
                showResult
            )
        )

        guard
            showResult ==
                .success
        else {

            invalidatePagesFontFamilyButtonCache(
                reason:
                    "AXShowMenu failed"
            )

            finishFontFamilyWrite()
            return
        }


        // Pages creates the menu asynchronously.
        // Keep the existing production polling path.

        waitForPagesFontMenu(
            under:
                fontFamilyButton,
            requestedFamily:
                requested,
            attempt:
                1
        )
    }


    // MARK: - Wait for Pages Font Menu

    private func waitForPagesFontMenu(
        under fontFamilyButton:
            AXUIElement,
        requestedFamily:
            String,
        attempt:
            Int
    ) {

        if let menu =
            directChild(
                of:
                    fontFamilyButton,
                role:
                    "AXMenu"
            )
        {

            applyFontFamily(
                requestedFamily,
                from:
                    menu,
                using:
                    fontFamilyButton
            )

            return
        }

        guard
            attempt < fontMenuMaximumAttempts
        else {

            print("")
            print(
                "❌ Pages opened the font popup, but its AXMenu"
            )

            print(
                "   did not appear before the timeout."
            )

            finishFontFamilyWrite()

            return
        }

        DispatchQueue.main
            .asyncAfter(
                deadline:
                    .now()
                    + fontMenuRetryDelay
            ) { [weak self] in

                Task { @MainActor in

                    self?
                        .waitForPagesFontMenu(
                            under:
                                fontFamilyButton,
                            requestedFamily:
                                requestedFamily,
                            attempt:
                                attempt + 1
                        )
                }
            }
    }


    // MARK: - Apply Font Family from Open Menu

    private func applyFontFamily(
        _ requestedFamily:
            String,
        from menu:
            AXUIElement,
        using fontFamilyButton:
            AXUIElement
    ) {

        let menuItems =
            copyChildren(
                from:
                    menu
            )

        print(
            "Font menu items:",
            menuItems.count
        )

        var targetItem:
            AXUIElement?

        var canonicalMenuName:
            String?

        for item
            in menuItems
        {

            guard
                roleName(
                    of:
                        item
                )
                == "AXMenuItem"
            else {
                continue
            }

            guard
                let rawTitle =
                    copyString(
                        from:
                            item,
                        attribute:
                            kAXTitleAttribute
                    )
            else {
                continue
            }

            let title =
                normalizeFontName(
                    rawTitle
                )

            guard
                !title.isEmpty
            else {
                continue
            }

            if fontNamesMatch(
                title,
                requestedFamily
            ) {

                let enabled =
                    copyBool(
                        from:
                            item,
                        attribute:
                            kAXEnabledAttribute
                    )
                    ?? true

                guard enabled else {

                    print(
                        "❌ Matching font menu item is disabled:",
                        title
                    )

                    cancelMenu(
                        menu
                    )

                    finishFontFamilyWrite()
                    return
                }

                targetItem =
                    item

                canonicalMenuName =
                    title

                break
            }
        }

        guard
            let targetItem
        else {

            print("")
            print(
                "❌ Font family was not found in Pages:"
            )

            print(
                "\"\(requestedFamily)\""
            )

            cancelMenu(
                menu
            )

            finishFontFamilyWrite()
            return
        }

        let resolvedFamily =
            canonicalMenuName
            ?? requestedFamily

        print(
            "🎯 Matched Pages font:",
            "\"\(resolvedFamily)\""
        )

        let targetActions =
            actionNames(
                of:
                    targetItem
            )

        print(
            "Menu item actions:",
            targetActions
        )

        guard
            targetActions.contains(
                kAXPressAction
            )
        else {

            print(
                "❌ Matching font item does not expose AXPress."
            )

            cancelMenu(
                menu
            )

            finishFontFamilyWrite()
            return
        }

        let pressResult =
            AXUIElementPerformAction(
                targetItem,
                kAXPressAction
                    as CFString
            )

        print(
            "AXPress:",
            axErrorName(
                pressResult
            )
        )

        guard
            pressResult == .success
        else {

            cancelMenu(
                menu
            )

            finishFontFamilyWrite()
            return
        }


        // Give Pages a very short moment to update the
        // popup value, then verify the result.

        DispatchQueue.main
            .asyncAfter(
                deadline:
                    .now()
                    + 0.10
            ) { [weak self] in

                Task { @MainActor in

                    self?
                        .verifyFontFamilyWrite(
                            requestedFamily:
                                requestedFamily,
                            fontFamilyButton:
                                fontFamilyButton
                        )
                }
            }
    }


    // MARK: - Verify Font-Family Write

    private func verifyFontFamilyWrite(
        requestedFamily:
            String,
        fontFamilyButton:
            AXUIElement
    ) {

        guard
            let rawResult =
                stringValue(
                    from:
                        fontFamilyButton
                )
        else {

            invalidatePagesFontFamilyButtonCache(
                reason:
                    "Could not read font-family popup after AXPress"
            )

            print("")
            print(
                "⚠️ AXPress succeeded, but Zest could not read"
            )

            print(
                "   the resulting font family back from Pages."
            )

            scheduleAutomaticRefresh()

            finishFontFamilyWrite()
            return
        }

        let result =
            normalizeFontName(
                rawResult
            )

        print(
            "Read-back family:",
            "\"\(result)\""
        )

        guard
            fontNamesMatch(
                result,
                requestedFamily
            )
        else {

            print("")
            print(
                "⚠️ Pages reports a different font after AXPress."
            )

            print(
                "Expected:",
                "\"\(requestedFamily)\""
            )

            print(
                "Actual:",
                "\"\(result)\""
            )

            scheduleAutomaticRefresh()

            finishFontFamilyWrite()
            return
        }


        // =========================================
        // FAST LOCAL PUBLISH
        // =========================================

        fontFamily =
            result

        fontName =
            result

        hasTextContext =
            true

        applicationName =
            observedApplicationName

        updateStatusMessage()

        print("")
        print(
            "⚡️ FONT FAMILY WRITE COMPLETE"
        )

        print(
            "Pages now reports:",
            "\"\(result)\""
        )

        scheduleAutomaticRefresh()

        finishFontFamilyWrite()
    }


    // MARK: - Font-Family Status

    private func updateStatusMessage() {

        if
            let fontFamily,
            let fontSize
        {

            statusMessage =
                "\(fontFamily), \(formatSize(fontSize)) pt"

        } else if let fontFamily {

            statusMessage =
                "Font: \(fontFamily)"

        } else if let fontSize {

            statusMessage =
                "Font size: \(formatSize(fontSize)) pt"
        }
    }


    // MARK: - Finish Font-Family Write

    private func finishFontFamilyWrite() {

        print("")
        print("==========================================")
        print("🍊 END SET FONT FAMILY")
        print("==========================================")
        print("")
    }


    // MARK: - Cancel Menu

    private func cancelMenu(
        _ menu:
            AXUIElement
    ) {

        let actions =
            actionNames(
                of:
                    menu
            )

        guard
            actions.contains(
                kAXCancelAction
            )
        else {
            return
        }

        _ =
            AXUIElementPerformAction(
                menu,
                kAXCancelAction
                    as CFString
            )
    }


    // MARK: - Direct Child by Role

    private func directChild(
        of element:
            AXUIElement,
        role targetRole:
            String
    ) -> AXUIElement? {

        copyChildren(
            from:
                element
        )
        .first {

            roleName(
                of:
                    $0
            )
            == targetRole
        }
    }


    // MARK: - Resolve Pages Font-Family Button

    private func resolvePagesFontFamilyButton(
        in window:
            AXUIElement,
        pid:
            pid_t
    ) -> AXUIElement? {

        if cachedPagesFontFamilyButtonPID
            == pid,
           let cachedButton =
                cachedPagesFontFamilyButton
        {

            if isValidPagesFontFamilyButton(
                cachedButton
            ) {

                print(
                    "⚡️ Using cached Pages font-family button."
                )

                return cachedButton
            }

            invalidatePagesFontFamilyButtonCache(
                reason:
                    "Cached font-family AX element became invalid"
            )
        }

        if cachedPagesFontFamilyButton != nil
            ||
            cachedPagesFontFamilyButtonPID != nil
        {

            invalidatePagesFontFamilyButtonCache(
                reason:
                    "Cached font-family PID does not match target PID"
            )
        }

        print(
            "🔎 Discovering Pages font-family button..."
        )

        var scannedCount = 0

        guard
            let button =
                findPagesFontFamilyButton(
                    in:
                        window,
                    depth:
                        0,
                    scannedCount:
                        &scannedCount
                )
        else {

            print(
                "Scanned AX elements:",
                scannedCount
            )

            return nil
        }

        guard
            isValidPagesFontFamilyButton(
                button
            )
        else {

            print(
                "❌ Discovered font-family button failed validation."
            )

            return nil
        }

        cachedPagesFontFamilyButton =
            button

        cachedPagesFontFamilyButtonPID =
            pid

        print(
            "Scanned AX elements:",
            scannedCount
        )

        print(
            "🍊 Font-family button discovered and cached."
        )

        return button
    }


    // MARK: - Validate Pages Font-Family Button

    private func isValidPagesFontFamilyButton(
        _ button:
            AXUIElement
    ) -> Bool {

        guard
            roleName(
                of:
                    button
            )
            == "AXPopUpButton"
        else {
            return false
        }

        let help =
            copyString(
                from:
                    button,
                attribute:
                    kAXHelpAttribute
            )?
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
            .lowercased()
            ?? ""

        guard
            help
                == "choose the font family."
        else {
            return false
        }

        guard
            let rawValue =
                stringValue(
                    from:
                        button
                )
        else {
            return false
        }

        return
            !normalizeFontName(
                rawValue
            )
            .isEmpty
    }


    // MARK: - Invalidate Font-Family Cache

    private func invalidatePagesFontFamilyButtonCache(
        reason:
            String
    ) {

        let hadCache =
            cachedPagesFontFamilyButton != nil
            ||
            cachedPagesFontFamilyButtonPID != nil

        cachedPagesFontFamilyButton = nil
        cachedPagesFontFamilyButtonPID = nil

        if hadCache {

            print(
                "♻️ Pages font-family cache cleared:",
                reason
            )
        }
    }


    // MARK: - Pages Typeface Reader / Writer

    private func resolvePagesTypefaceButton(
        in window:
            AXUIElement,
        pid:
            pid_t
    ) -> AXUIElement? {

        if cachedPagesTypefaceButtonPID
            == pid,
           let cachedButton =
                cachedPagesTypefaceButton
        {
            let help =
                copyString(
                    from: cachedButton,
                    attribute:
                        kAXHelpAttribute
                )?
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .lowercased()
                ?? ""

            if roleName(of: cachedButton)
                == "AXPopUpButton",
               help == "choose the typeface."
            {
                return cachedButton
            }

            invalidatePagesTypefaceButtonCache(
                reason:
                    "Cached typeface AX element became invalid"
            )
        }

        var scannedCount = 0

        guard
            let button =
                findPagesTypefaceButton(
                    in: window,
                    depth: 0,
                    scannedCount:
                        &scannedCount
                )
        else {
            return nil
        }

        cachedPagesTypefaceButton =
            button

        cachedPagesTypefaceButtonPID =
            pid

        return button
    }


    private func invalidatePagesTypefaceButtonCache(
        reason:
            String
    ) {

        let hadCache =
            cachedPagesTypefaceButton != nil
            ||
            cachedPagesTypefaceButtonPID != nil

        cachedPagesTypefaceButton = nil
        cachedPagesTypefaceButtonPID = nil

        if hadCache {
            print(
                "♻️ Pages typeface cache cleared:",
                reason
            )
        }
    }


    private func findPagesTypefaceButton(
        in element: AXUIElement,
        depth: Int,
        scannedCount: inout Int
    ) -> AXUIElement? {
        guard depth <= maximumDepth, scannedCount < maximumElements else { return nil }
        scannedCount += 1

        if roleName(of: element) == "AXPopUpButton" {
            let help = copyString(from: element, attribute: kAXHelpAttribute)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            if help == "choose the typeface." { return element }
        }

        for child in copyChildren(from: element) {
            if let match = findPagesTypefaceButton(
                in: child,
                depth: depth + 1,
                scannedCount: &scannedCount
            ) { return match }
        }
        return nil
    }

    func setTypeface(_ requestedTypeface: String) {
        let requested = normalizeFontName(requestedTypeface)

        guard !requested.isEmpty,
              AXIsProcessTrusted(),
              let pid = observedPID,
              let family = fontFamily
        else {
            print("❌ SILENT TYPEFACE → missing context")
            return
        }

        print("")
        print("🍊 SILENT TYPEFACE REQUEST")
        print("Requested:", requested)
        print("Family:", family)
        print("PID:", pid)

        guard let pages = NSRunningApplication(processIdentifier: pid) else {
            print("❌ SILENT TYPEFACE → Pages application unavailable")
            return
        }

        // Zest's normal development window is activating.
        // Give Pages focus back before the silent writer attempts its
        // invisible Copy-based selection bridge.
        pages.activate(options: [])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            Task { @MainActor in
                guard let self else { return }

                let silentResult = PagesSilentFontWriter.apply(
                    typeface: requested,
                    family: family,
                    pid: pid
                )

                switch silentResult {

                case .applied:
                    print("⚡️ SILENT TYPEFACE WRITE COMPLETE → \(requested)")

                    self.fontTypeface = requested
                    self.hasTextContext = true
                    self.applicationName = self.observedApplicationName

                    self.updateStatusMessage()
                    self.scheduleAutomaticRefresh()

                case .noSelection:
                    print("🧪 SILENT TYPEFACE STOP → writer reported no selection")
                    print("🧪 Pages popup fallback intentionally DISABLED")

                    self.scheduleAutomaticRefresh()

                case .failed(let reason):
                    print("❌ SILENT TYPEFACE STOP → \(reason)")
                    print("🧪 Pages popup fallback intentionally DISABLED")

                    self.scheduleAutomaticRefresh()
                }
            }
        }
    }

    private func setTypefaceUsingPagesPopup(
        _ requested: String,
        pid: pid_t
    ) {
        let app = AXUIElementCreateApplication(pid)
        guard let window = copyAXElement(from: app, attribute: kAXFocusedWindowAttribute)
                ?? copyAXElement(from: app, attribute: kAXMainWindowAttribute)
        else { return }

        var scanned = 0
        guard let button = findPagesTypefaceButton(
            in: window,
            depth: 0,
            scannedCount: &scanned
        ) else {
            print("❌ Pages typeface control unavailable")
            return
        }

        let result = AXUIElementPerformAction(button, kAXShowMenuAction as CFString)
        guard result == .success else {
            print("❌ Could not open Pages typeface menu:", axErrorName(result))
            return
        }

        waitForPagesTypefaceMenu(under: button, requested: requested, attempt: 1)
    }

    private func waitForPagesTypefaceMenu(
        under button: AXUIElement,
        requested: String,
        attempt: Int
    ) {
        if let menu = directChild(of: button, role: "AXMenu") {
            applyTypeface(requested, from: menu, using: button)
            return
        }

        guard attempt < fontMenuMaximumAttempts else {
            print("❌ Pages typeface menu timed out")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + fontMenuRetryDelay) { [weak self] in
            Task { @MainActor in
                self?.waitForPagesTypefaceMenu(
                    under: button,
                    requested: requested,
                    attempt: attempt + 1
                )
            }
        }
    }

    private func applyTypeface(
        _ requested: String,
        from menu: AXUIElement,
        using button: AXUIElement
    ) {
        for item in copyChildren(from: menu) {
            guard roleName(of: item) == "AXMenuItem",
                  let rawTitle = copyString(from: item, attribute: kAXTitleAttribute)
            else { continue }

            let title = normalizeFontName(rawTitle)
            if fontNamesMatch(title, requested) {
                let press = AXUIElementPerformAction(item, kAXPressAction as CFString)
                guard press == .success else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        if let raw = self.stringValue(from: button) {
                            self.fontTypeface = self.normalizeFontName(raw)
                        }
                        self.scheduleAutomaticRefresh()
                    }
                }
                return
            }
        }
        cancelMenu(menu)
        print("❌ Typeface not found in Pages menu:", requested)
    }

    // MARK: - Pages BIU Commands

    func toggleBold() {
        sendPagesFormattingShortcut(
            keyCode: 11,
            name: "Bold"
        )
    }

    func toggleItalic() {
        sendPagesFormattingShortcut(
            keyCode: 34,
            name: "Italic"
        )
    }

    func toggleUnderline() {
        sendPagesFormattingShortcut(
            keyCode: 32,
            name: "Underline"
        )
    }

    private func sendPagesFormattingShortcut(
        keyCode: CGKeyCode,
        name: String
    ) {
        guard let pid = observedPID,
              let target = NSRunningApplication(
                  processIdentifier: pid
              )
        else {
            print("❌ Native Pages \(name) → no target application")
            return
        }

        guard target.bundleIdentifier == "com.apple.Pages" else {
            print("❌ Native Pages \(name) → target is not Pages")
            return
        }

        print("")
        print("🍊 Native Pages \(name) command")
        print("Target PID:", pid)

        // Restore Pages as the active application first.
        // This is necessary while Zest uses the normal activating
        // development window.
        target.activate(options: [])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in

            guard let source = CGEventSource(
                stateID: .hidSystemState
            ) else {
                print("❌ Native Pages \(name) → could not create event source")
                return
            }

            guard
                let keyDown = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: keyCode,
                    keyDown: true
                ),
                let keyUp = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: keyCode,
                    keyDown: false
                )
            else {
                print("❌ Native Pages \(name) → could not create keyboard event")
                return
            }

            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)

            print("⚡️ Native Pages \(name) command sent")

            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.16
            ) {
                Task { @MainActor in
                    self?.scheduleAutomaticRefresh()
                }
            }
        }
    }

    // MARK: - Pages Font-Family Reader

    private func findPagesFontFamilyButton(
        in element:
            AXUIElement,
        depth:
            Int,
        scannedCount:
            inout Int
    ) -> AXUIElement? {

        guard
            depth <= maximumDepth,
            scannedCount < maximumElements
        else {
            return nil
        }

        scannedCount += 1

        let elementRole =
            roleName(
                of:
                    element
            )

        if elementRole
            == "AXPopUpButton"
        {

            let help =
                copyString(
                    from:
                        element,
                    attribute:
                        kAXHelpAttribute
                )?
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .lowercased()
                ?? ""

            if help
                == "choose the font family."
            {
                return element
            }
        }

        for child
            in copyChildren(
                from:
                    element
            )
        {

            if let match =
                findPagesFontFamilyButton(
                    in:
                        child,
                    depth:
                        depth + 1,
                    scannedCount:
                        &scannedCount
                )
            {
                return match
            }

            guard
                scannedCount
                    < maximumElements
            else {
                return nil
            }
        }

        return nil
    }


    // MARK: - Font Name Matching

    private func fontNamesMatch(
        _ lhs:
            String,
        _ rhs:
            String
    ) -> Bool {

        normalizeFontName(
            lhs
        )
        .compare(
            normalizeFontName(
                rhs
            ),
            options: [
                .caseInsensitive,
                .diacriticInsensitive
            ]
        )
        == .orderedSame
    }


    // MARK: - Normalize Font Name

    private func normalizeFontName(
        _ raw:
            String
    ) -> String {

        var scalars =
            Array(
                raw.unicodeScalars
            )

        while
            let first =
                scalars.first,
            shouldStripFontEdgeScalar(
                first
            )
        {
            scalars.removeFirst()
        }

        while
            let last =
                scalars.last,
            shouldStripFontEdgeScalar(
                last
            )
        {
            scalars.removeLast()
        }

        return String(
            String.UnicodeScalarView(
                scalars
            )
        )
        .trimmingCharacters(
            in:
                .whitespacesAndNewlines
        )
    }


    // MARK: - Font Edge Scalar

    private func shouldStripFontEdgeScalar(
        _ scalar:
            UnicodeScalar
    ) -> Bool {

        if CharacterSet
            .whitespacesAndNewlines
            .contains(
                scalar
            )
        {
            return true
        }

        if CharacterSet
            .controlCharacters
            .contains(
                scalar
            )
        {
            return true
        }

        if CharacterSet
            .illegalCharacters
            .contains(
                scalar
            )
        {
            return true
        }

        if scalar.properties
            .generalCategory
            == .format
        {
            return true
        }

        return false
    }


    // MARK: - Pages Font Diagnostic Probe

    func probePagesFontControl() {

        guard
            let pid =
                observedPID
        else {

            print("")
            print("==========================================")
            print("🍊 ZEST PAGES FONT PROBE")
            print("==========================================")
            print("")
            print("❌ No remembered target application.")
            print("")
            print("Activate Pages first, then run the shortcut.")
            print("")
            print("==========================================")
            print("")

            return
        }

        PagesFontProbe.run(
            pid:
                pid,
            applicationName:
                observedApplicationName
        )
    }


    // MARK: - Production Pages Font-Size Setter

    @discardableResult
    func setFontSize(
        _ target:
            Int
    ) -> Bool {

        print("")
        print("==========================================")
        print("🍊 ZEST SET FONT SIZE")
        print("==========================================")
        print(
            "Requested target:",
            "\(target) pt"
        )
        print("")

        guard
            (1...1000).contains(
                target
            )
        else {

            print(
                "❌ Target is outside Pages' 1...1000 pt range."
            )

            print("==========================================")
            print("")

            return false
        }

        guard AXIsProcessTrusted() else {

            print(
                "❌ Accessibility permission is not active."
            )

            print("==========================================")
            print("")

            return false
        }

        guard
            let targetPID =
                observedPID,
            let targetApplication =
                NSRunningApplication(
                    processIdentifier:
                        targetPID
                )
        else {

            print(
                "❌ No remembered target application is available."
            )

            print("==========================================")
            print("")

            return false
        }

        let appName =
            targetApplication.localizedName
            ?? observedApplicationName
            ?? "Unknown"

        print(
            "Target application:",
            appName
        )

        print(
            "Target PID:",
            targetPID
        )

        guard appName == "Pages" else {

            print(
                "❌ The remembered target application is not Pages."
            )

            print("==========================================")
            print("")

            return false
        }

        let applicationElement =
            AXUIElementCreateApplication(
                targetPID
            )

        guard
            let window =
                copyAXElement(
                    from:
                        applicationElement,
                    attribute:
                        kAXFocusedWindowAttribute
                )
                ??
                copyAXElement(
                    from:
                        applicationElement,
                    attribute:
                        kAXMainWindowAttribute
                )
        else {

            print(
                "❌ Could not obtain the active Pages window."
            )

            print("==========================================")
            print("")

            return false
        }

        guard
            let field =
                resolvePagesFontSizeField(
                    in:
                        window,
                    pid:
                        targetPID
                )
        else {

            print("")
            print(
                "❌ Could not resolve the Pages font-size field."
            )

            print(
                "No formatting action was performed."
            )

            print("==========================================")
            print("")

            return false
        }

        guard
            let currentRawValue =
                stringValue(
                    from:
                        field
                ),
            let currentSize =
                parsePointSize(
                    currentRawValue
                )
        else {

            invalidatePagesFontSizeFieldCache(
                reason:
                    "Cached field could not provide its current value"
            )

            print("")
            print(
                "❌ Could not read the current Pages font size."
            )

            print("==========================================")
            print("")

            return false
        }

        print(
            "Current:",
            "\(formatSize(currentSize)) pt"
        )

        print(
            "Target:",
            "\(target) pt"
        )

        if Int(
            currentSize.rounded()
        )
            == target
        {

            print("")
            print(
                "✅ Already at the requested size."
            )

            print(
                "No formatting action was necessary."
            )

            print("==========================================")
            print("")

            scheduleAutomaticRefresh()

            return true
        }

        var valueSettable:
            DarwinBoolean = false

        let settableResult =
            AXUIElementIsAttributeSettable(
                field,
                kAXValueAttribute
                    as CFString,
                &valueSettable
            )

        guard
            settableResult == .success,
            valueSettable.boolValue
        else {

            invalidatePagesFontSizeFieldCache(
                reason:
                    "Cached field is no longer writable"
            )

            print("")
            print(
                "❌ Pages font-size field AXValue is not settable."
            )

            print(
                "Settable query:",
                axErrorName(
                    settableResult
                )
            )

            print("==========================================")
            print("")

            return false
        }

        let actions =
            actionNames(
                of:
                    field
            )

        guard
            actions.contains(
                kAXConfirmAction
            )
        else {

            invalidatePagesFontSizeFieldCache(
                reason:
                    "Cached field no longer exposes AXConfirm"
            )

            print("")
            print(
                "❌ Pages font-size field does not expose AXConfirm."
            )

            print(
                "Available actions:",
                actions
            )

            print("==========================================")
            print("")

            return false
        }

        let focusResult =
            AXUIElementSetAttributeValue(
                field,
                kAXFocusedAttribute
                    as CFString,
                kCFBooleanTrue
            )

        print(
            "Focus result:",
            axErrorName(
                focusResult
            )
        )

        let targetString =
            "\(target) pt"

        print("")
        print(
            "▶️ Direct write:",
            "\"\(targetString)\""
        )

        let writeResult =
            AXUIElementSetAttributeValue(
                field,
                kAXValueAttribute
                    as CFString,
                targetString
                    as CFString
            )

        guard
            writeResult == .success
        else {

            invalidatePagesFontSizeFieldCache(
                reason:
                    "Direct AXValue write failed"
            )

            print(
                "❌ Direct AXValue write failed:",
                axErrorName(
                    writeResult
                )
            )

            print("==========================================")
            print("")

            scheduleAutomaticRefresh()

            return false
        }

        let confirmResult =
            AXUIElementPerformAction(
                field,
                kAXConfirmAction
                    as CFString
            )

        guard
            confirmResult == .success
        else {

            invalidatePagesFontSizeFieldCache(
                reason:
                    "AXConfirm failed"
            )

            print(
                "❌ AXConfirm failed:",
                axErrorName(
                    confirmResult
                )
            )

            print("==========================================")
            print("")

            scheduleAutomaticRefresh()

            return false
        }

        let finalRawValue =
            stringValue(
                from:
                    field
            )

        let finalSize =
            finalRawValue.flatMap {
                parsePointSize(
                    $0
                )
            }

        print(
            "Immediate field read-back:",
            finalRawValue ?? "nil"
        )

        if let finalSize {

            print(
                "Immediate parsed size:",
                formatSize(
                    finalSize
                ),
                "pt"
            )
        }

        fontSize =
            Double(
                target
            )

        role =
            "AXTextField"

        hasTextContext =
            true

        applicationName =
            observedApplicationName

        updateStatusMessage()

        print("")
        print(
            "⚡️ DIRECT FONT SIZE WRITE COMPLETE"
        )

        print(
            "\(formatSize(currentSize)) pt → \(target) pt"
        )

        print(
            "No AXIncrement / AXDecrement actions were used."
        )

        print("==========================================")
        print("")

        scheduleAutomaticRefresh()

        if let finalSize {

            return
                Int(
                    finalSize.rounded()
                )
                == target
        }

        return true
    }


    // MARK: - Resolve Pages Font-Size Field

    private func resolvePagesFontSizeField(
        in window:
            AXUIElement,
        pid:
            pid_t
    ) -> AXUIElement? {

        if cachedPagesFontSizeFieldPID
            == pid,
           let cachedField =
                cachedPagesFontSizeField
        {

            if isValidPagesFontSizeField(
                cachedField
            ) {

                print(
                    "⚡️ Using cached Pages font-size field."
                )

                return cachedField
            }

            invalidatePagesFontSizeFieldCache(
                reason:
                    "Cached AX element became invalid"
            )
        }

        if cachedPagesFontSizeField != nil
            ||
            cachedPagesFontSizeFieldPID != nil
        {

            invalidatePagesFontSizeFieldCache(
                reason:
                    "Cached PID does not match target PID"
            )
        }

        print(
            "🔎 Discovering Pages font-size field..."
        )

        var scannedCount = 0

        var matches:
            [AXUIElement] = []

        scanForStrictPagesFontSizeFields(
            window,
            depth:
                0,
            scannedCount:
                &scannedCount,
            matches:
                &matches
        )

        print(
            "Scanned AX elements:",
            scannedCount
        )

        print(
            "Strict font-size text fields:",
            matches.count
        )

        guard
            matches.count == 1
        else {

            print(
                "❌ Expected exactly one semantic Pages font-size field."
            )

            return nil
        }

        let field =
            matches[0]

        guard
            isValidPagesFontSizeField(
                field
            )
        else {

            print(
                "❌ Discovered Pages font-size field failed validation."
            )

            return nil
        }

        cachedPagesFontSizeField =
            field

        cachedPagesFontSizeFieldPID =
            pid

        print(
            "🍊 Font-size field discovered and cached."
        )

        return field
    }


    // MARK: - Validate Cached Pages Size Field

    private func isValidPagesFontSizeField(
        _ field:
            AXUIElement
    ) -> Bool {

        let fieldRole =
            roleName(
                of:
                    field
            )

        guard
            fieldRole == "AXTextField"
        else {
            return false
        }

        let fieldHelp =
            copyString(
                from:
                    field,
                attribute:
                    kAXHelpAttribute
            )?
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
            .lowercased()
            ?? ""

        guard
            fieldHelp
                == "set the font size."
        else {
            return false
        }

        guard
            let rawValue =
                stringValue(
                    from:
                        field
                ),
            parsePointSize(
                rawValue
            )
            != nil
        else {
            return false
        }

        return true
    }


    // MARK: - Invalidate Pages Size Cache

    private func invalidatePagesFontSizeFieldCache(
        reason:
            String
    ) {

        let hadCache =
            cachedPagesFontSizeField != nil
            ||
            cachedPagesFontSizeFieldPID != nil

        cachedPagesFontSizeField = nil
        cachedPagesFontSizeFieldPID = nil

        if hadCache {

            print(
                "♻️ Pages font-size cache cleared:",
                reason
            )
        }
    }


    // MARK: - Strict Pages Size Scanner

    private func scanForStrictPagesFontSizeFields(
        _ element:
            AXUIElement,
        depth:
            Int,
        scannedCount:
            inout Int,
        matches:
            inout [AXUIElement]
    ) {

        guard
            depth <= maximumDepth,
            scannedCount < maximumElements
        else {
            return
        }

        scannedCount += 1

        let elementRole =
            roleName(
                of:
                    element
            )

        if elementRole
            == "AXTextField"
        {

            let help =
                copyString(
                    from:
                        element,
                    attribute:
                        kAXHelpAttribute
                )?
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .lowercased()
                ?? ""

            if help
                == "set the font size."
            {

                matches.append(
                    element
                )
            }
        }

        for child
            in copyChildren(
                from:
                    element
            )
        {

            scanForStrictPagesFontSizeFields(
                child,
                depth:
                    depth + 1,
                scannedCount:
                    &scannedCount,
                matches:
                    &matches
            )

            guard
                scannedCount
                    < maximumElements
            else {
                return
            }
        }
    }
    
    // MARK: - Strict Pages Font-Size Candidate

    private func strictPagesFontSizeCandidate(
        from matches:
            [PointSizeFieldCandidate]
    ) -> PointSizeFieldCandidate? {

        let strictMatches =
            matches.filter {

                let help =
                    $0.help?
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                        .lowercased()
                    ?? ""

                return
                    $0.role
                        == "AXTextField"
                    &&
                    help
                        == "set the font size."
            }

        return strictMatches.max {

            score(
                $0
            )
            <
            score(
                $1
            )
        }
    }


    // MARK: - AX Actions

    private func actionNames(
        of element:
            AXUIElement
    ) -> [String] {

        var names:
            CFArray?

        let result =
            AXUIElementCopyActionNames(
                element,
                &names
            )

        guard
            result == .success,
            let names
        else {
            return []
        }

        return (names as NSArray)
            .compactMap {
                $0 as? String
            }
    }


    // MARK: - Manual Diagnostic Refresh

    func refresh() {

        resetContext()

        print("")
        print("==========================================")
        print("🍊 ZEST FORMAT CONTEXT")
        print("==========================================")
        print("")

        isAccessibilityTrusted =
            AXIsProcessTrusted()

        print(
            "1. Accessibility trusted:",
            isAccessibilityTrusted
        )

        guard isAccessibilityTrusted else {

            fail(
                "Accessibility permission is not active"
            )

            return
        }

        guard
            let frontmostApplication =
                NSWorkspace.shared
                    .frontmostApplication
        else {

            fail(
                "Could not determine frontmost application"
            )

            return
        }

        applicationName =
            frontmostApplication
                .localizedName

        print(
            "2. Application:",
            applicationName
                ?? "nil"
        )

        let pid =
            frontmostApplication
                .processIdentifier

        let applicationElement =
            AXUIElementCreateApplication(
                pid
            )

        guard
            let window =
                copyAXElement(
                    from:
                        applicationElement,
                    attribute:
                        kAXFocusedWindowAttribute
                )
                ??
                copyAXElement(
                    from:
                        applicationElement,
                    attribute:
                        kAXMainWindowAttribute
                )
        else {

            fail(
                "Could not obtain application window"
            )

            return
        }

        print(
            "3. Window:",
            copyString(
                from:
                    window,
                attribute:
                    kAXTitleAttribute
            )
            ?? "Untitled"
        )

        var scannedCount = 0

        var matches:
            [PointSizeFieldCandidate] = []

        scanForPointSizeFields(
            window,
            depth: 0,
            scannedCount:
                &scannedCount,
            matches:
                &matches
        )

        print("")
        print(
            "4. AX elements scanned:",
            scannedCount
        )

        print(
            "5. Point-size-looking fields:",
            matches.count
        )

        print("")

        guard
            !matches.isEmpty
        else {

            fail(
                "No point-size field was found"
            )

            return
        }

        for (
            index,
            candidate
        ) in matches.enumerated() {

            print(
                "---------- SIZE CANDIDATE \(index + 1) ----------"
            )

            print(
                "Role:",
                candidate.role
            )

            print(
                "Raw value:",
                "\"\(candidate.rawValue)\""
            )

            print(
                "Parsed:",
                candidate.size
            )

            print(
                "Enabled:",
                candidate.enabled
            )

            print(
                "Focused:",
                candidate.focused
            )

            if let title =
                candidate.title
            {
                print(
                    "Title:",
                    title
                )
            }

            if let description =
                candidate.description
            {
                print(
                    "Description:",
                    description
                )
            }

            if let help =
                candidate.help
            {
                print(
                    "Help:",
                    help
                )
            }

            print(
                "Ancestor trail:",
                candidate
                    .ancestorTrail
                    .joined(
                        separator:
                            " → "
                    )
            )

            print("")
        }

        let isPages =
            frontmostApplication
                .localizedName
                == "Pages"

        let winner:
            PointSizeFieldCandidate?

        if isPages {

            winner =
                strictPagesFontSizeCandidate(
                    from:
                        matches
                )

        } else {

            winner =
                bestCandidate(
                    from:
                        matches
                )
        }

        guard let winner else {

            clearContext(
                message:
                    isPages
                    ? "Pages font-size field unavailable"
                    : "No font-size context"
            )

            return
        }
        
        let winnerScore =
            score(
                winner
            )

        print(
            "6. BEST CANDIDATE SCORE:",
            winnerScore
        )

        print(
            "7. Raw value:",
            "\"\(winner.rawValue)\""
        )

        print(
            "8. Parsed font size:",
            winner.size
        )

        fontSize =
            winner.size

        role =
            winner.role

        hasTextContext =
            true

        if isPages {

            var familyScanCount = 0

            if let familyButton =
                findPagesFontFamilyButton(
                    in:
                        window,
                    depth:
                        0,
                    scannedCount:
                        &familyScanCount
                ),
               let rawFamily =
                stringValue(
                    from:
                        familyButton
                )
            {

                let normalizedFamily =
                    normalizeFontName(
                        rawFamily
                    )

                if !normalizedFamily.isEmpty {

                    fontFamily =
                        normalizedFamily

                    fontName =
                        normalizedFamily
                }
            }
        }

        if isPages {
            var typefaceScanCount = 0
            if let typefaceButton = findPagesTypefaceButton(
                in: window, depth: 0, scannedCount: &typefaceScanCount
            ), let rawTypeface = stringValue(from: typefaceButton) {
                let normalized = normalizeFontName(rawTypeface)
                fontTypeface = normalized.isEmpty ? nil : normalized
            }
        }

        updateStatusMessage()

        print("")
        print(
            "🍊 SIZE = \(formatSize(winner.size)) pt"
        )

        if let fontFamily {

            print(
                "🍊 FONT = \(fontFamily)"
            )
        }

        print(
            "Status:",
            statusMessage
        )

        print(
            "=========================================="
        )

        print("")
    }


    // MARK: - Candidate

    private struct PointSizeFieldCandidate {

        let element:
            AXUIElement

        let role:
            String

        let rawValue:
            String

        let size:
            Double

        let enabled:
            Bool

        let focused:
            Bool

        let title:
            String?

        let description:
            String?

        let help:
            String?

        let ancestorTrail:
            [String]
    }


    // MARK: - Scan Point Sizes

    private func scanForPointSizeFields(
        _ element:
            AXUIElement,
        depth:
            Int,
        scannedCount:
            inout Int,
        matches:
            inout [PointSizeFieldCandidate]
    ) {

        guard
            depth <= maximumDepth,
            scannedCount < maximumElements
        else {
            return
        }

        scannedCount += 1

        if let rawValue =
            stringValue(
                from:
                    element
            ),
           let size =
            parsePointSize(
                rawValue
            )
        {

            let candidate =
                PointSizeFieldCandidate(

                    element:
                        element,

                    role:
                        roleName(
                            of:
                                element
                        ),

                    rawValue:
                        rawValue,

                    size:
                        size,

                    enabled:
                        copyBool(
                            from:
                                element,
                            attribute:
                                kAXEnabledAttribute
                        )
                        ?? true,

                    focused:
                        copyBool(
                            from:
                                element,
                            attribute:
                                kAXFocusedAttribute
                        )
                        ?? false,

                    title:
                        copyString(
                            from:
                                element,
                            attribute:
                                kAXTitleAttribute
                        ),

                    description:
                        copyString(
                            from:
                                element,
                            attribute:
                                kAXDescriptionAttribute
                        ),

                    help:
                        copyString(
                            from:
                                element,
                            attribute:
                                kAXHelpAttribute
                        ),

                    ancestorTrail:
                        ancestorTrail(
                            from:
                                element,
                            maximumLevels:
                                6
                        )
                )

            matches.append(
                candidate
            )
        }

        for child
            in copyChildren(
                from:
                    element
            )
        {

            scanForPointSizeFields(
                child,
                depth:
                    depth + 1,
                scannedCount:
                    &scannedCount,
                matches:
                    &matches
            )

            guard
                scannedCount
                    < maximumElements
            else {
                return
            }
        }
    }


    // MARK: - Best Candidate

    private func bestCandidate(
        from matches:
            [PointSizeFieldCandidate]
    ) -> PointSizeFieldCandidate? {

        let semanticWinner =
            matches
                .filter {

                    let help =
                        $0.help?
                            .lowercased()
                        ?? ""

                    return
                        help.contains(
                            "font"
                        )
                        &&
                        help.contains(
                            "size"
                        )
                }
                .max {

                    score(
                        $0
                    )
                    <
                    score(
                        $1
                    )
                }

        if let semanticWinner {
            return semanticWinner
        }

        return matches.max {

            score(
                $0
            )
            <
            score(
                $1
            )
        }
    }


    // MARK: - Candidate Ranking

    private func score(
        _ candidate:
            PointSizeFieldCandidate
    ) -> Int {

        var score = 0

        let role =
            candidate.role
                .lowercased()

        let title =
            candidate.title?
                .lowercased()
            ?? ""

        let description =
            candidate.description?
                .lowercased()
            ?? ""

        let help =
            candidate.help?
                .lowercased()
            ?? ""

        let trail =
            candidate
                .ancestorTrail
                .joined(
                    separator:
                        " "
                )
                .lowercased()

        if role == "axtextfield" {
            score += 50
        }

        if candidate.enabled {
            score += 10
        }

        if candidate.size >= 5,
           candidate.size <= 300
        {
            score += 20
        }

        if candidate.size == 0 {
            score -= 100
        }

        let combined =
            [
                title,
                description,
                help,
                trail
            ]
            .joined(
                separator:
                    " "
            )

        if combined.contains(
            "font"
        ) {
            score += 100
        }

        if combined.contains(
            "font size"
        ) {
            score += 150
        }

        if combined.contains(
            "text"
        ) {
            score += 20
        }

        if combined.contains(
            "character"
        ) {
            score += 15
        }

        if combined.contains(
            "before paragraph"
        ) {
            score -= 100
        }

        if combined.contains(
            "after paragraph"
        ) {
            score -= 100
        }

        if combined.contains(
            "spacing"
        ) {
            score -= 80
        }

        if combined.contains(
            "indent"
        ) {
            score -= 80
        }

        if combined.contains(
            "margin"
        ) {
            score -= 80
        }

        if combined.contains(
            "paragraph"
        ) {
            score -= 25
        }

        return score
    }


    // MARK: - Parse Point Size

    private func parsePointSize(
        _ rawValue:
            String
    ) -> Double? {

        let trimmed =
            rawValue
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        let pattern =
            #"^([0-9]+(?:[.,][0-9]+)?)\s*pt$"#

        guard
            let regex =
                try? NSRegularExpression(
                    pattern:
                        pattern,
                    options:
                        [.caseInsensitive]
                )
        else {
            return nil
        }

        let nsRange =
            NSRange(
                trimmed.startIndex
                    ..<
                trimmed.endIndex,
                in:
                    trimmed
            )

        guard
            let match =
                regex.firstMatch(
                    in:
                        trimmed,
                    options:
                        [],
                    range:
                        nsRange
                ),
            match.numberOfRanges
                >= 2,
            let valueRange =
                Range(
                    match.range(
                        at:
                            1
                    ),
                    in:
                        trimmed
                )
        else {
            return nil
        }

        let numberString =
            String(
                trimmed[
                    valueRange
                ]
            )
            .replacingOccurrences(
                of:
                    ",",
                with:
                    "."
            )

        return Double(
            numberString
        )
    }


    // MARK: - String Value

    private func stringValue(
        from element:
            AXUIElement
    ) -> String? {

        var value:
            CFTypeRef?

        let result =
            AXUIElementCopyAttributeValue(
                element,
                kAXValueAttribute
                    as CFString,
                &value
            )

        guard
            result == .success,
            let value
        else {
            return nil
        }

        if let string =
            value as? String
        {
            return string
        }

        if let number =
            value as? NSNumber
        {
            return number.stringValue
        }

        return nil
    }


    // MARK: - Ancestor Trail

    private func ancestorTrail(
        from element:
            AXUIElement,
        maximumLevels:
            Int
    ) -> [String] {

        var trail:
            [String] = []

        var current:
            AXUIElement? =
                element

        var level = 0

        while
            let element =
                current,
            level < maximumLevels
        {

            var description =
                roleName(
                    of:
                        element
                )

            if let title =
                copyString(
                    from:
                        element,
                    attribute:
                        kAXTitleAttribute
                ),
               !title.isEmpty
            {
                description +=
                    "[\(title)]"
            }

            if let axDescription =
                copyString(
                    from:
                        element,
                    attribute:
                        kAXDescriptionAttribute
                ),
               !axDescription.isEmpty
            {
                description +=
                    "{\(axDescription)}"
            }

            trail.append(
                description
            )

            current =
                copyAXElement(
                    from:
                        element,
                    attribute:
                        kAXParentAttribute
                )

            level += 1
        }

        return trail
    }


    // MARK: - Children

    private func copyChildren(
        from element:
            AXUIElement
    ) -> [AXUIElement] {

        var value:
            CFTypeRef?

        let result =
            AXUIElementCopyAttributeValue(
                element,
                kAXChildrenAttribute
                    as CFString,
                &value
            )

        guard
            result == .success,
            let array =
                value as? [Any]
        else {
            return []
        }

        var children:
            [AXUIElement] = []

        for rawChild
            in array
        {

            let cfChild =
                rawChild
                    as CFTypeRef

            guard
                CFGetTypeID(
                    cfChild
                )
                ==
                AXUIElementGetTypeID()
            else {
                continue
            }

            children.append(
                unsafeBitCast(
                    cfChild,
                    to:
                        AXUIElement.self
                )
            )
        }

        return children
    }


    // MARK: - AX Element

    private func copyAXElement(
        from element:
            AXUIElement,
        attribute:
            String
    ) -> AXUIElement? {

        var value:
            CFTypeRef?

        let result =
            AXUIElementCopyAttributeValue(
                element,
                attribute
                    as CFString,
                &value
            )

        guard
            result == .success,
            let value,
            CFGetTypeID(
                value
            )
            ==
            AXUIElementGetTypeID()
        else {
            return nil
        }

        return unsafeBitCast(
            value,
            to:
                AXUIElement.self
        )
    }


    // MARK: - String Attribute

    private func copyString(
        from element:
            AXUIElement,
        attribute:
            String
    ) -> String? {

        var value:
            CFTypeRef?

        let result =
            AXUIElementCopyAttributeValue(
                element,
                attribute
                    as CFString,
                &value
            )

        guard
            result == .success,
            let value
        else {
            return nil
        }

        return value
            as? String
    }


    // MARK: - Bool Attribute

    private func copyBool(
        from element:
            AXUIElement,
        attribute:
            String
    ) -> Bool? {

        var value:
            CFTypeRef?

        let result =
            AXUIElementCopyAttributeValue(
                element,
                attribute
                    as CFString,
                &value
            )

        guard
            result == .success,
            let number =
                value as? NSNumber
        else {
            return nil
        }

        return number.boolValue
    }


    // MARK: - Role

    private func roleName(
        of element:
            AXUIElement
    ) -> String {

        copyString(
            from:
                element,
            attribute:
                kAXRoleAttribute
        )
        ?? "Unknown"
    }


    // MARK: - Format Size

    private func formatSize(
        _ value:
            Double
    ) -> String {

        if value.rounded()
            == value
        {
            return String(
                Int(
                    value
                )
            )
        }

        return String(
            format:
                "%.1f",
            value
        )
    }


    // MARK: - Remove Observer

    private func removeCurrentAXObserver() {

        pendingAutomaticRefresh?
            .cancel()

        pendingAutomaticRefresh = nil

        invalidatePagesFontSizeFieldCache(
            reason:
                "AX observer removed"
        )

        invalidatePagesFontFamilyButtonCache(
            reason:
                "AX observer removed"
        )

        invalidatePagesTypefaceButtonCache(
            reason:
                "AX observer removed"
        )

        guard
            let axObserver,
            let applicationElement =
                observedApplicationElement
        else {

            self.axObserver = nil

            observedApplicationElement = nil
            observedPID = nil
            observedApplicationName = nil

            return
        }

        for notificationName
            in observedNotifications
        {

            AXObserverRemoveNotification(
                axObserver,
                applicationElement,
                notificationName
                    as CFString
            )
        }

        let runLoopSource =
            AXObserverGetRunLoopSource(
                axObserver
            )

        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            runLoopSource,
            .commonModes
        )

        self.axObserver = nil

        observedApplicationElement = nil
        observedPID = nil
        observedApplicationName = nil
    }


    // MARK: - Clear Context

    private func clearContext(
        message:
            String
    ) {

        let previousSize =
            fontSize

        let previousFontFamily =
            fontFamily

        let hadContext =
            hasTextContext
            ||
            previousSize != nil
            ||
            previousFontFamily != nil

        fontSize = nil
        fontName = nil
        fontFamily = nil
        fontTypeface = nil

        role = nil

        hasTextContext = false

        statusMessage =
            message

        guard hadContext else {
            return
        }

        if previousSize != nil {

            print(
                "🍊 AUTO SIZE → —"
            )
        }

        if previousFontFamily != nil {

            print(
                "🍊 AUTO FONT → —"
            )
        }
    }


    // MARK: - AX Error Name

    private func axErrorName(
        _ error:
            AXError
    ) -> String {

        switch error {

        case .success:
            return "success"

        case .failure:
            return "failure"

        case .illegalArgument:
            return "illegalArgument"

        case .invalidUIElement:
            return "invalidUIElement"

        case .invalidUIElementObserver:
            return "invalidUIElementObserver"

        case .cannotComplete:
            return "cannotComplete"

        case .attributeUnsupported:
            return "attributeUnsupported"

        case .actionUnsupported:
            return "actionUnsupported"

        case .notificationUnsupported:
            return "notificationUnsupported"

        case .notImplemented:
            return "notImplemented"

        case .notificationAlreadyRegistered:
            return "notificationAlreadyRegistered"

        case .notificationNotRegistered:
            return "notificationNotRegistered"

        case .apiDisabled:
            return "apiDisabled"

        case .noValue:
            return "noValue"

        case .parameterizedAttributeUnsupported:
            return "parameterizedAttributeUnsupported"

        case .notEnoughPrecision:
            return "notEnoughPrecision"

        @unknown default:

            return
                "unknown(\(error.rawValue))"
        }
    }


    // MARK: - Failure

    private func fail(
        _ message:
            String
    ) {

        statusMessage =
            message

        print("")
        print(
            "❌ ZEST FORMAT CONTEXT FAILED"
        )

        print(
            message
        )

        print(
            "=========================================="
        )

        print("")
    }


    // MARK: - Reset

    private func resetContext() {

        applicationName = nil
        role = nil

        fontSize = nil
        fontName = nil
        fontFamily = nil
        fontTypeface = nil

        hasTextContext = false
    }
}
