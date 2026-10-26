//
//  ZestTextInserter.swift
//  Zest
//
//  Inserts text into the previously active application.
//
//  Primary route:
//      Accessibility selected-text replacement
//
//  Fallback:
//      temporary clipboard + Command-V
//
//  This class is intentionally generic.
//  Emoji and Symbols will both use it.
//

import Foundation
import AppKit
import ApplicationServices
import Combine


@MainActor
final class ZestTextInserter: ObservableObject {

    // The runtime inspector may become the foreground application before a feature
    // panel lazily creates its inserter. Keep the editor that summoned Zest here so
    // Clipboard/Emoji/Symbol never lose their destination merely because search is
    // now a real key-window interaction.
    private static var rememberedExternalPID: pid_t?

    static func rememberExternalTarget(_ application: NSRunningApplication) {
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        rememberedExternalPID = application.processIdentifier
    }

    // MARK: Target

    private weak var targetApplication:
        NSRunningApplication?

    private var targetPID:
        pid_t?

    private var targetElement:
        AXUIElement?

    private var targetElementPID:
        pid_t?


    // MARK: Observation

    private var observers:
        [NSObjectProtocol] = []


    // MARK: Clipboard

    private weak var clipboardManager:
        ClipboardHistoryManager?


    // MARK: Init

    init(
        clipboardManager:
            ClipboardHistoryManager
    ) {

        self.clipboardManager =
            clipboardManager


        installWorkspaceObservers()


        captureCurrentExternalTarget()

        if targetPID == nil,
           let pid = Self.rememberedExternalPID,
           let application = NSRunningApplication(processIdentifier: pid),
           !application.isTerminated {
            capture(application)
        }
    }


    deinit {

        for observer in observers {

            NSWorkspace.shared
                .notificationCenter
                .removeObserver(
                    observer
                )
        }
    }


    // MARK: Public

    func insert(
        _ text: String
    ) {

        guard !text.isEmpty else {
            return
        }


        guard let application =
            resolvedTargetApplication()
        else {

            print(
                "🍊 INSERT → no target application"
            )

            return
        }


        let pid =
            application.processIdentifier


        // -----------------------------------------
        // Route 1:
        // Accessibility direct selected-text write.
        // -----------------------------------------

        if let element =
            resolvedTargetElement(
                pid: pid
            ),
           insertViaAccessibility(
                text,
                into: element
           )
        {

            print(
                "🍊 INSERT AX → \(text)"
            )

            application.activate(
                options: []
            )

            return
        }


        // -----------------------------------------
        // Route 2:
        // Clipboard + Command-V.
        // -----------------------------------------

        insertViaPaste(
            text,
            into:
                application
        )
    }


    // MARK: Paste-Only Public Route

    /// Uses the temporary-pasteboard + Command-V path directly.
    /// Emoji and Symbol tiles use this route because some AX text controls
    /// duplicate single Unicode graphemes when kAXSelectedTextAttribute is set.
    func insertUsingPasteboard(
        _ text: String
    ) {
        guard !text.isEmpty else {
            return
        }

        guard let application =
            resolvedTargetApplication()
        else {
            print(
                "🍊 INSERT PASTE-ONLY → no target application"
            )
            return
        }

        insertViaPaste(
            text,
            into: application
        )
    }


    // MARK: Target Capture

    private func installWorkspaceObservers() {

        let center =
            NSWorkspace.shared
                .notificationCenter


        let deactivated =
            center.addObserver(
                forName:
                    NSWorkspace
                        .didDeactivateApplicationNotification,
                object:
                    nil,
                queue:
                    .main
            ) {
                [weak self]
                notification in

                Task { @MainActor in

                    self?
                        .handleDeactivatedApplication(
                            notification
                        )
                }
            }


        observers.append(
            deactivated
        )


        let activated =
            center.addObserver(
                forName:
                    NSWorkspace
                        .didActivateApplicationNotification,
                object:
                    nil,
                queue:
                    .main
            ) {
                [weak self]
                notification in

                Task { @MainActor in

                    self?
                        .handleActivatedApplication(
                            notification
                        )
                }
            }


        observers.append(
            activated
        )
    }


    private func handleDeactivatedApplication(
        _ notification: Notification
    ) {

        guard
            let application =
                notification.userInfo?[
                    NSWorkspace
                        .applicationUserInfoKey
                ]
                as?
                NSRunningApplication
        else {
            return
        }


        capture(
            application
        )
    }


    private func handleActivatedApplication(
        _ notification: Notification
    ) {

        guard
            let application =
                notification.userInfo?[
                    NSWorkspace
                        .applicationUserInfoKey
                ]
                as?
                NSRunningApplication
        else {
            return
        }


        guard !isZest(
            application
        )
        else {
            return
        }


        // Keep the external application current.
        //
        // Its focused element will be captured either
        // here or when it deactivates in favor of Zest.

        capture(
            application
        )
    }


    private func captureCurrentExternalTarget() {

        guard
            let application =
                NSWorkspace.shared
                    .frontmostApplication,
            !isZest(
                application
            )
        else {
            return
        }


        capture(
            application
        )
    }


    private func capture(
        _ application:
            NSRunningApplication
    ) {

        guard !isZest(
            application
        )
        else {
            return
        }


        let pid =
            application.processIdentifier


        if targetPID != pid {
            targetElement = nil
            targetElementPID = nil
        }

        targetApplication =
            application

        targetPID =
            pid
        Self.rememberedExternalPID = pid


        let appElement =
            AXUIElementCreateApplication(
                pid
            )


        var focused:
            CFTypeRef?


        let error =
            AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedUIElementAttribute
                    as CFString,
                &focused
            )


        if error == .success,
           let focused
        {

            targetElement =
                unsafeBitCast(
                    focused,
                    to:
                        AXUIElement.self
                )
            targetElementPID = pid

        } else {

            targetElement =
                nil
            targetElementPID = nil
        }


        print(
            "🍊 INSERT TARGET → \(application.localizedName ?? "Unknown")"
        )
    }


    // MARK: Resolve Target

    private func resolvedTargetApplication()
        -> NSRunningApplication?
    {

        // Prefer the editor that is frontmost at the instant of insertion.
        // Zest's runtime is non-activating, so this preserves the user's real
        // destination and prevents a stale Pages target from stealing Safari
        // emoji/symbol/clipboard insertions.
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           !frontmost.isTerminated,
           !isZest(frontmost)
        {
            if targetPID != frontmost.processIdentifier {
                capture(frontmost)
            } else {
                refreshFocusedElement(for: frontmost.processIdentifier)
            }
            return frontmost
        }

        if let application =
            targetApplication,
           !application.isTerminated,
           !isZest(
                application
           )
        {
            return application
        }


        if let pid =
            targetPID,
           let application =
                NSRunningApplication(
                    processIdentifier:
                        pid
                ),
           !application.isTerminated
        {
            targetApplication =
                application

            return application
        }


        return nil
    }


    private func resolvedTargetElement(
        pid: pid_t
    ) -> AXUIElement? {

        if let targetElement, targetElementPID == pid {
            return targetElement
        }

        targetElement = nil
        targetElementPID = nil


        let application =
            AXUIElementCreateApplication(
                pid
            )


        var focused:
            CFTypeRef?


        let result =
            AXUIElementCopyAttributeValue(
                application,
                kAXFocusedUIElementAttribute
                    as CFString,
                &focused
            )


        guard
            result == .success,
            let focused
        else {
            return nil
        }


        let element =
            unsafeBitCast(
                focused,
                to:
                    AXUIElement.self
            )


        targetElement =
            element
        targetElementPID = pid


        return element
    }


    private func refreshFocusedElement(for pid: pid_t) {
        let application = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        if result == .success, let focused {
            targetElement = unsafeBitCast(focused, to: AXUIElement.self)
            targetElementPID = pid
        } else {
            targetElement = nil
            targetElementPID = nil
        }
    }


    // MARK: Accessibility Route

    private func insertViaAccessibility(
        _ text: String,
        into element:
            AXUIElement
    ) -> Bool {

        var settable:
            DarwinBoolean =
                false


        let check =
            AXUIElementIsAttributeSettable(
                element,
                kAXSelectedTextAttribute
                    as CFString,
                &settable
            )


        guard
            check == .success,
            settable.boolValue
        else {
            return false
        }


        let result =
            AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute
                    as CFString,
                text as CFTypeRef
            )


        return
            result == .success
    }


    // MARK: Paste Route

    private func insertViaPaste(
        _ text: String,
        into application:
            NSRunningApplication
    ) {

        let pasteboard =
            NSPasteboard.general


        let oldItems =
            snapshotPasteboard(
                pasteboard
            )


        clipboardManager?
            .performInternalPasteboardWrite {

                pasteboard
                    .clearContents()


                pasteboard
                    .setString(
                        text,
                        forType:
                            .string
                    )
            }


        let destinationPID = application.processIdentifier

        // Paste into a real key editor, not merely a process. WebKit controls in
        // Safari reject process-targeted Command-V when their application is not
        // active. Return foreground ownership to the remembered destination first;
        // this also gives the runtime controller the normal "click back / insert"
        // dismissal signal. Then post Command-V after AppKit has restored its key
        // window and responder chain.
        application.activate(options: [.activateIgnoringOtherApps])

        DispatchQueue.main
            .asyncAfter(
                deadline:
                    .now()
                    + 0.08
            ) {
                [weak self]
                in

                guard let self else {
                    return
                }


                self.sendPasteShortcut(to: destinationPID)


                DispatchQueue.main
                    .asyncAfter(
                        deadline:
                            .now()
                            + 0.10
                    ) {
                        [weak self]
                        in

                        guard let self else {
                            return
                        }


                        self.restorePasteboard(
                            oldItems
                        )


                        print(
                            "🍊 INSERT PASTE → \(text)"
                        )
                    }
            }
    }


    // MARK: Command-V

    private func sendPasteShortcut(to pid: pid_t) {

        let source =
            CGEventSource(
                stateID:
                    .combinedSessionState
            )


        guard
            let down =
                CGEvent(
                    keyboardEventSource:
                        source,
                    virtualKey:
                        9,
                    keyDown:
                        true
                ),
            let up =
                CGEvent(
                    keyboardEventSource:
                        source,
                    virtualKey:
                        9,
                    keyDown:
                        false
                )
        else {
            return
        }


        down.flags =
            .maskCommand

        up.flags =
            .maskCommand


        // Deliver Command-V to the remembered editor process, not to whichever
        // window happens to own keyboard focus at this instant. This is essential
        // once the Zest inspector itself is key for Emoji/Symbol search.
        down.postToPid(pid)
        up.postToPid(pid)
    }


    // MARK: Clipboard Snapshot

    private struct PasteboardSnapshot {

        let values:
            [[NSPasteboard.PasteboardType: Data]]
    }


    private func snapshotPasteboard(
        _ pasteboard:
            NSPasteboard
    ) -> PasteboardSnapshot {

        let values =
            (pasteboard
                .pasteboardItems
                ?? [])
            .map {
                item in

                var dictionary:
                    [
                        NSPasteboard.PasteboardType:
                            Data
                    ] = [:]


                for type in item.types {

                    if let data =
                        item.data(
                            forType:
                                type
                        )
                    {

                        dictionary[type] =
                            data
                    }
                }


                return dictionary
            }


        return PasteboardSnapshot(
            values:
                values
        )
    }


    private func restorePasteboard(
        _ snapshot:
            PasteboardSnapshot
    ) {

        let pasteboard =
            NSPasteboard.general


        clipboardManager?
            .performInternalPasteboardWrite {

                pasteboard
                    .clearContents()


                let items =
                    snapshot.values.map {
                        dictionary
                        -> NSPasteboardItem
                        in

                        let item =
                            NSPasteboardItem()


                        for (
                            type,
                            data
                        )
                        in dictionary
                        {

                            item.setData(
                                data,
                                forType:
                                    type
                            )
                        }


                        return item
                    }


                if !items.isEmpty {

                    pasteboard
                        .writeObjects(
                            items
                        )
                }
            }
    }


    // MARK: Helpers

    private func isZest(
        _ application:
            NSRunningApplication
    ) -> Bool {

        application
            .bundleIdentifier
            == Bundle.main
                .bundleIdentifier
    }
}
