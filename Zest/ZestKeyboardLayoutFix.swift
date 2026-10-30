//
//  ZestKeyboardLayoutFix.swift
//  Zest
//
//  0.1.2 — deterministic wrong-keyboard-layout correction + AX/clipboard fallback
//

import SwiftUI
import AppKit
import ApplicationServices
import Combine
import Carbon

struct ZestLayoutFixCandidate: Identifiable, Equatable {
    let id = UUID()
    let sourceName: String
    let targetName: String
    let correctedText: String
    let confidence: Double
}

@MainActor
final class ZestKeyboardLayoutFixService: ObservableObject {
    static let shared = ZestKeyboardLayoutFixService()

    @Published private(set) var selectedText = ""
    @Published private(set) var candidate: ZestLayoutFixCandidate?
    @Published private(set) var status = "Select text typed with the wrong keyboard layout."

    private var lastExternalPID: pid_t?
    private var cachedFocusedElement: AXUIElement?
    private var cachedSelectionElement: AXUIElement?
    private var cachedSelectedText: String?
    private var observer: NSObjectProtocol?

    private let english = Array("`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./")
    private let russian = Array("ё1234567890-=йцукенгшщзхъ\\фывапролджэячсмитьбю.")
    private let ukrainian = Array("'1234567890-=йцукенгшщзхї\\фівапролджєячсмитьбю.")

    private init() {
        rememberFrontmostExternalApplication()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            self?.lastExternalPID = app.processIdentifier
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    /// Captures the editor context while the external app still owns focus,
    /// immediately before Zest activates its inspector panel.
    func captureExternalContext(from application: NSRunningApplication) {
        guard application.bundleIdentifier != Bundle.main.bundleIdentifier else { return }

        lastExternalPID = application.processIdentifier
        cachedFocusedElement = focusedElement(for: application.processIdentifier)
        cachedSelectionElement = nil
        cachedSelectedText = nil

        if let context = findSelectionContext(for: application.processIdentifier) {
            cachedSelectionElement = context.element
            cachedSelectedText = context.text
            print(
                "⌨️ LAYOUT FIX PRECAPTURE AX TREE → chars:",
                context.text.count,
                "role:", elementRole(context.element) ?? "<unknown>"
            )
        } else {
            print("⌨️ LAYOUT FIX PRECAPTURE AX TREE → no selection")
        }
    }

    /// Browser/web views frequently stop exposing selected text through AX the
    /// instant Zest takes focus. When Layout Fix is available in the active UI,
    /// prime a non-destructive Command-C while the original application is still
    /// frontmost, cache the copied string, then restore the user's pasteboard.
    /// The keyboard assistant waits for this short capture before activating Zest.
    func primeExternalSelectionBeforeActivation(
        from application: NSRunningApplication
    ) async {
        captureExternalContext(from: application)

        if let cachedSelectedText, !cachedSelectedText.isEmpty {
            print("⌨️ LAYOUT FIX PRECAPTURE → AX selection already available")
            return
        }

        let pid = application.processIdentifier
        let snapshot = snapshotPasteboard()
        let pasteboard = NSPasteboard.general
        let baselineChangeCount = pasteboard.changeCount

        print(
            "⌨️ LAYOUT FIX PRECAPTURE COPY → target:",
            application.localizedName ?? "<unknown>",
            "pid:", pid,
            "baseline:", baselineChangeCount
        )

        if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            application.activate(options: [])
            try? await Task.sleep(for: .milliseconds(90))
        }

        let modifiersReleased = await waitForShortcutModifiersToRelease()
        print(
            "⌨️ LAYOUT FIX PRECAPTURE COPY → modifiers released:",
            modifiersReleased,
            "frontmost:",
            NSWorkspace.shared.frontmostApplication?.localizedName ?? "<none>"
        )

        var captured: String?

        // 1) Post an actual Command-key sequence at the session event tap.
        // Some apps ignore a plain C event whose flags merely contain Command.
        if await postPhysicalCommandShortcut(
            keyCode: CGKeyCode(kVK_ANSI_C),
            tap: .cgSessionEventTap
        ) {
            captured = await waitForCopiedString(
                pasteboard: pasteboard,
                baselineChangeCount: baselineChangeCount,
                timeoutMilliseconds: 520
            )
            if let captured {
                print("⌨️ LAYOUT FIX PRECAPTURE SESSION COPY → chars:", captured.count)
            }
        }

        // 2) Retry at the HID tap with the same real modifier sequence.
        if captured == nil {
            let secondBaseline = pasteboard.changeCount
            if await postPhysicalCommandShortcut(
                keyCode: CGKeyCode(kVK_ANSI_C),
                tap: .cghidEventTap
            ) {
                captured = await waitForCopiedString(
                    pasteboard: pasteboard,
                    baselineChangeCount: secondBaseline,
                    timeoutMilliseconds: 620
                )
                if let captured {
                    print("⌨️ LAYOUT FIX PRECAPTURE HID COPY → chars:", captured.count)
                }
            }
        }

        // 3) Last event-transport fallback: send the full Command down/C/down/up/
        // Command up sequence directly to the remembered source process.
        if captured == nil {
            let thirdBaseline = pasteboard.changeCount
            if await postPhysicalCommandShortcutToPID(
                keyCode: CGKeyCode(kVK_ANSI_C),
                pid: pid
            ) {
                captured = await waitForCopiedString(
                    pasteboard: pasteboard,
                    baselineChangeCount: thirdBaseline,
                    timeoutMilliseconds: 720
                )
                if let captured {
                    print("⌨️ LAYOUT FIX PRECAPTURE PID COPY → chars:", captured.count)
                }
            }
        }

        // 4) AX menu fallback, when the target exposes its menu hierarchy.
        if captured == nil {
            let menuBaseline = pasteboard.changeCount
            let pressedCopy = performMenuShortcut(
                commandCharacter: "C",
                in: application
            )
            print("⌨️ LAYOUT FIX PRECAPTURE MENU COPY →", pressedCopy)

            if pressedCopy {
                captured = await waitForCopiedString(
                    pasteboard: pasteboard,
                    baselineChangeCount: menuBaseline,
                    timeoutMilliseconds: 720
                )
                if let captured {
                    print("⌨️ LAYOUT FIX PRECAPTURE MENU COPY → chars:", captured.count)
                }
            }
        }

        if let captured, !captured.isEmpty {
            cachedSelectedText = captured
            print("⌨️ LAYOUT FIX PRECAPTURE COPY →", captured)
        } else {
            print(
                "⌨️ LAYOUT FIX PRECAPTURE COPY → no string received;",
                "final changeCount:", pasteboard.changeCount,
                "current string:", pasteboard.string(forType: .string) ?? "<nil>"
            )
        }

        restorePasteboard(snapshot)
    }

    func refreshSelection() {
        status = "Reading the selected text…"
        Task { await refreshSelectionAsync() }
    }

    /// Shortcut-first Layout Fix route. The source application remains frontmost
    /// while Zest captures, remaps and replaces the selected text.
    func performShortcutFix(
        target: ZestLayoutFixTarget,
        from application: NSRunningApplication,
        installedSources: [ZestInputSource],
        preferredSourceID: String?
    ) async -> ZestLayoutRemapResult? {
        // The leader stage owns selection capture. Do not blindly recapture here:
        // browser/WebKit selections can disappear from AX after the shortcut
        // sequence advances, and recapturing would wipe the valid cached copy.
        var captured = cachedSelectedText
        if captured?.isEmpty != false {
            captureExternalContext(from: application)
            captured = cachedSelectedText
        }
        if captured?.isEmpty != false {
            await primeExternalSelectionBeforeActivation(from: application)
            captured = cachedSelectedText
        }

        guard let captured, !captured.isEmpty else {
            print("⌨️ LAYOUT FIX SHORTCUT → no selected text captured")
            return nil
        }

        guard let remap = ZestPhysicalKeyboardLayoutMapper.shared.remap(
            captured,
            to: target.inputSourceID,
            installedSources: installedSources,
            preferredSourceID: preferredSourceID
        ) else {
            print("⌨️ LAYOUT FIX SHORTCUT → no physical-key mapping candidate")
            return nil
        }

        guard await replaceCapturedSelection(
            with: remap.correctedText,
            in: application
        ) else {
            print("⌨️ LAYOUT FIX SHORTCUT → replacement failed")
            return nil
        }

        selectedText = remap.correctedText
        candidate = nil
        status = "Selection corrected to \(remap.targetName)."
        cachedSelectedText = nil
        cachedSelectionElement = nil

        return remap
    }

    private func replaceCapturedSelection(
        with text: String,
        in application: NSRunningApplication
    ) async -> Bool {
        // Prefer the exact AX element that owned the selected text during the
        // leader stage. The focused AX leaf is frequently only a proxy/group.
        if let element = cachedSelectionElement ?? cachedFocusedElement {
            let result = replaceSelectedTextViaAX(text, in: element)
            print(
                "⌨️ LAYOUT FIX AX REPLACE → role:",
                elementRole(element) ?? "<unknown>",
                "result:", result.rawValue
            )
            if result == .success {
                return true
            }
        }

        let snapshot = snapshotPasteboard()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        if NSWorkspace.shared.frontmostApplication?.processIdentifier != application.processIdentifier {
            application.activate(options: [])
            try? await Task.sleep(for: .milliseconds(90))
        }

        _ = await waitForShortcutModifiersToRelease()

        let menuPaste = performMenuShortcut(
            commandCharacter: "V",
            in: application
        )
        print("⌨️ LAYOUT FIX REPLACE MENU PASTE →", menuPaste)

        if !menuPaste {
            _ = await postPhysicalCommandShortcut(
                keyCode: CGKeyCode(kVK_ANSI_V),
                tap: .cgSessionEventTap
            )
        }

        // Give the editor enough time to consume the pasteboard before restoring
        // the user's previous clipboard contents.
        try? await Task.sleep(for: .milliseconds(220))
        restorePasteboard(snapshot)
        return true
    }

    @discardableResult
    func replaceSelection() -> Bool {
        guard let candidate else { return false }

        if let element = focusedExternalTextElement() {
            let result = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                candidate.correctedText as CFTypeRef
            )
            if result == .success {
                selectedText = candidate.correctedText
                status = "Selection replaced."
                return true
            }
        }

        Task { await replaceViaPasteboard(candidate.correctedText) }
        return true
    }

    func bestCandidate(for text: String) -> ZestLayoutFixCandidate? {
        var values: [ZestLayoutFixCandidate] = []

        let cyrillicCount = text.unicodeScalars.filter { scalar in
            (0x0400...0x04FF).contains(Int(scalar.value))
        }.count
        let latinCount = text.unicodeScalars.filter { scalar in
            (0x0041...0x007A).contains(Int(scalar.value))
        }.count

        if cyrillicCount > 0 {
            let ru = remap(text, from: russian, to: english)
            values.append(.init(sourceName: "Russian", targetName: "English", correctedText: ru, confidence: languageScore(ru, target: "English") + 0.35))
            let ua = remap(text, from: ukrainian, to: english)
            values.append(.init(sourceName: "Ukrainian", targetName: "English", correctedText: ua, confidence: languageScore(ua, target: "English") + 0.35))
        }

        if latinCount > 0 {
            let ru = remap(text, from: english, to: russian)
            values.append(.init(sourceName: "English", targetName: "Russian", correctedText: ru, confidence: languageScore(ru, target: "Russian")))
            let ua = remap(text, from: english, to: ukrainian)
            values.append(.init(sourceName: "English", targetName: "Ukrainian", correctedText: ua, confidence: languageScore(ua, target: "Ukrainian")))
        }

        guard let best = values.max(by: { $0.confidence < $1.confidence }),
              best.correctedText != text,
              best.confidence > 0.20 else { return nil }
        return best
    }

    private func refreshSelectionAsync() async {
        rememberFrontmostExternalApplication()

        if let cachedSelectedText, !cachedSelectedText.isEmpty {
            applySelection(cachedSelectedText)
            return
        }

        if let text = selectedTextFromAX(), !text.isEmpty {
            cachedSelectedText = text
            applySelection(text)
            return
        }

        if let text = await copySelectionViaPasteboard(), !text.isEmpty {
            applySelection(text)
            return
        }

        selectedText = ""
        candidate = nil
        status = "Select the incorrectly typed text in the previous app, then refresh."
    }

    private func applySelection(_ text: String) {
        selectedText = text
        candidate = bestCandidate(for: text)
        status = candidate == nil
            ? "No confident layout correction was found."
            : "A physical-key layout match was detected."
    }

    private func selectedTextFromAX() -> String? {
        if let cachedSelectionElement,
           let text = directSelectedText(in: cachedSelectionElement),
           !text.isEmpty {
            return text
        }

        if let element = cachedFocusedElement,
           let context = selectionContext(in: element) {
            cachedSelectionElement = context.element
            return context.text
        }

        if let pid = lastExternalPID,
           let context = findSelectionContext(for: pid) {
            cachedSelectionElement = context.element
            return context.text
        }

        return nil
    }

    private struct AXSelectionContext {
        let text: String
        let element: AXUIElement
    }

    private func selectedText(in startingElement: AXUIElement) -> String? {
        selectionContext(in: startingElement)?.text
    }

    private func selectionContext(in startingElement: AXUIElement) -> AXSelectionContext? {
        var element: AXUIElement? = startingElement

        // First search the focused lineage. This is cheap and handles standard
        // native editors where the selected-text owner is an ancestor of the
        // focused leaf.
        for _ in 0..<12 {
            guard let current = element else { break }

            if let text = directSelectedText(in: current), !text.isEmpty {
                return AXSelectionContext(text: text, element: current)
            }

            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                current,
                kAXParentAttribute as CFString,
                &parentValue
            ) == .success,
            let parentValue else {
                break
            }

            element = unsafeBitCast(parentValue, to: AXUIElement.self)
        }

        return nil
    }

    /// Finds the actual AX element that owns the current selection. Apps such as
    /// Safari, Telegram and Pages can place focus on a proxy/group while the
    /// editable text object lives deeper elsewhere in the focused window.
    private func findSelectionContext(for pid: pid_t) -> AXSelectionContext? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.18)

        // The system-wide focused element can be more accurate than querying
        // kAXFocusedUIElement directly on an app (notably with WebKit).
        let systemWide = AXUIElementCreateSystemWide()
        var systemFocusedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &systemFocusedValue
        ) == .success,
        let systemFocusedValue {
            let systemFocused = unsafeBitCast(systemFocusedValue, to: AXUIElement.self)
            var elementPID: pid_t = 0
            if AXUIElementGetPid(systemFocused, &elementPID) == .success,
               elementPID == pid,
               let context = selectionContext(in: systemFocused) {
                print("⌨️ LAYOUT FIX AX SEARCH → system-wide focused lineage")
                return context
            }
        }

        if let focused = focusedElement(for: pid),
           let context = selectionContext(in: focused) {
            print("⌨️ LAYOUT FIX AX SEARCH → app focused lineage")
            return context
        }

        // Search the focused window, then any remaining app windows. This is
        // bounded to avoid pathological AX trees blocking the hotkey path.
        var roots: [AXUIElement] = []
        var focusedWindowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            app,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        ) == .success,
        let focusedWindowValue {
            roots.append(unsafeBitCast(focusedWindowValue, to: AXUIElement.self))
        }

        var windowsValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            app,
            kAXWindowsAttribute as CFString,
            &windowsValue
        ) == .success,
        let windowsValue,
        CFGetTypeID(windowsValue) == CFArrayGetTypeID() {
            let windows = unsafeBitCast(windowsValue, to: CFArray.self)
            for windowIndex in 0..<CFArrayGetCount(windows) {
                let raw = CFArrayGetValueAtIndex(windows, windowIndex)
                roots.append(unsafeBitCast(raw, to: AXUIElement.self))
            }
        }

        if roots.isEmpty { roots = [app] }

        for root in roots {
            if let context = breadthFirstSelectionSearch(from: root) {
                print(
                    "⌨️ LAYOUT FIX AX SEARCH → tree match role:",
                    elementRole(context.element) ?? "<unknown>"
                )
                return context
            }
        }

        return nil
    }

    private func breadthFirstSelectionSearch(
        from root: AXUIElement,
        nodeLimit: Int = 1400,
        depthLimit: Int = 16
    ) -> AXSelectionContext? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var index = 0
        var visited = Set<CFHashCode>()
        var inspected = 0

        while index < queue.count, inspected < nodeLimit {
            let (element, depth) = queue[index]
            index += 1
            inspected += 1

            let hash = CFHash(element)
            if !visited.insert(hash).inserted { continue }

            if let text = directSelectedText(in: element), !text.isEmpty {
                print("⌨️ LAYOUT FIX AX SEARCH → inspected:", inspected)
                return AXSelectionContext(text: text, element: element)
            }

            guard depth < depthLimit else { continue }

            var childCount: CFIndex = 0
            guard AXUIElementGetAttributeValueCount(
                element,
                kAXChildrenAttribute as CFString,
                &childCount
            ) == .success,
            childCount > 0 else { continue }

            let cappedCount = min(childCount, 220)
            var children: CFArray?
            guard AXUIElementCopyAttributeValues(
                element,
                kAXChildrenAttribute as CFString,
                0,
                cappedCount,
                &children
            ) == .success,
            let children else { continue }

            for childIndex in 0..<CFArrayGetCount(children) {
                let raw = CFArrayGetValueAtIndex(children, childIndex)
                let child = unsafeBitCast(raw, to: AXUIElement.self)
                queue.append((child, depth + 1))
            }
        }

        print("⌨️ LAYOUT FIX AX SEARCH → no selected-text owner; inspected:", inspected)
        return nil
    }

    private func elementRole(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &value
        ) == .success else { return nil }
        return value as? String
    }

    private func replaceSelectedTextViaAX(
        _ replacement: String,
        in element: AXUIElement
    ) -> AXError {
        // Preferred route: editable text elements are expected to expose
        // AXSelectedText directly.
        let directResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            replacement as CFTypeRef
        )
        if directResult == .success { return .success }

        // Some custom editors expose a selected range + full value but reject
        // setting AXSelectedText. Replace the range in the full value instead.
        var rangeValue: CFTypeRef?
        var textValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &textValue
        ) == .success,
        let rangeValue,
        CFGetTypeID(rangeValue) == AXValueGetTypeID(),
        let fullText = textValue as? String else {
            return directResult
        }

        var range = CFRange()
        guard AXValueGetValue(
            unsafeBitCast(rangeValue, to: AXValue.self),
            .cfRange,
            &range
        ),
        range.location >= 0,
        range.length > 0,
        range.location + range.length <= (fullText as NSString).length else {
            return directResult
        }

        let mutable = NSMutableString(string: fullText)
        mutable.replaceCharacters(
            in: NSRange(location: range.location, length: range.length),
            with: replacement
        )

        let valueResult = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            mutable.copy() as CFTypeRef
        )
        guard valueResult == .success else { return directResult }

        var insertionRange = CFRange(
            location: range.location + (replacement as NSString).length,
            length: 0
        )
        if let insertionValue = AXValueCreate(.cfRange, &insertionRange) {
            _ = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                insertionValue
            )
        }
        return .success
    }

    private func directSelectedText(in element: AXUIElement) -> String? {
        var value: CFTypeRef?

        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        ) == .success,
        let text = value as? String,
        !text.isEmpty {
            return text
        }

        // WebKit/Safari-style selection.
        var markerRange: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            "AXSelectedTextMarkerRange" as CFString,
            &markerRange
        ) == .success,
        let markerRange {
            var markerText: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element,
                "AXStringForTextMarkerRange" as CFString,
                markerRange,
                &markerText
            ) == .success,
            let text = markerText as? String,
            !text.isEmpty {
                return text
            }
        }

        // Standard text controls that expose only a selected range + full value.
        var rangeValue: CFTypeRef?
        var textValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &textValue
        ) == .success,
        let rangeValue,
        CFGetTypeID(rangeValue) == AXValueGetTypeID(),
        let fullText = textValue as? String {
            var range = CFRange()
            if AXValueGetValue(
                unsafeBitCast(rangeValue, to: AXValue.self),
                .cfRange,
                &range
            ),
            range.location >= 0,
            range.length > 0,
            range.location + range.length <= (fullText as NSString).length {
                return (fullText as NSString).substring(
                    with: NSRange(location: range.location, length: range.length)
                )
            }
        }

        return nil
    }

    private func rememberFrontmostExternalApplication() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalPID = front.processIdentifier
            if let element = focusedElement(for: front.processIdentifier) {
                cachedFocusedElement = element
                if let text = selectedText(in: element), !text.isEmpty {
                    cachedSelectedText = text
                }
            }
        }
    }

    private func focusedExternalTextElement() -> AXUIElement? {
        if let cachedFocusedElement {
            return cachedFocusedElement
        }

        guard let pid = lastExternalPID else { return nil }
        return focusedElement(for: pid)
    }

    private func focusedElement(for pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success,
        let value else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private struct PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    private func snapshotPasteboard() -> PasteboardSnapshot {
        let pasteboard = NSPasteboard.general
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { values[type] = data }
            }
            return values
        }
        return PasteboardSnapshot(items: items)
    }

    private func restorePasteboard(_ snapshot: PasteboardSnapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let restored: [NSPasteboardItem] = snapshot.items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }

    private func copySelectionViaPasteboard() async -> String? {
        guard let pid = lastExternalPID,
              let application = NSRunningApplication(processIdentifier: pid),
              !application.isTerminated else { return nil }

        let snapshot = snapshotPasteboard()
        let pasteboard = NSPasteboard.general
        let sentinel = "__ZEST_LAYOUT_REFRESH_\(UUID().uuidString)__"

        pasteboard.clearContents()
        pasteboard.setString(sentinel, forType: .string)
        let baselineChangeCount = pasteboard.changeCount

        if NSWorkspace.shared.frontmostApplication?.processIdentifier != application.processIdentifier {
            application.activate(options: [])
            try? await Task.sleep(for: .milliseconds(90))
        }
        _ = await waitForShortcutModifiersToRelease()
        await postCommandKeyToFrontmostAsync(keyCode: 8)

        var copied: String?
        for _ in 0..<32 {
            try? await Task.sleep(for: .milliseconds(22))
            if pasteboard.changeCount != baselineChangeCount,
               let value = pasteboard.string(forType: .string),
               !value.isEmpty,
               value != sentinel {
                copied = value
                break
            }
        }

        restorePasteboard(snapshot)
        return copied
    }

    private func replaceViaPasteboard(_ text: String) async {
        guard let pid = lastExternalPID,
              let application = NSRunningApplication(processIdentifier: pid),
              !application.isTerminated else {
            status = "The original app could not be found."
            return
        }
        let snapshot = snapshotPasteboard()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        if NSWorkspace.shared.frontmostApplication?.processIdentifier != application.processIdentifier {
            application.activate(options: [])
            try? await Task.sleep(for: .milliseconds(90))
        }
        _ = await waitForShortcutModifiersToRelease()
        let menuPaste = performMenuShortcut(
            commandCharacter: "V",
            in: application
        )
        if !menuPaste {
            await postCommandKeyToFrontmostAsync(keyCode: 9) // V
        }
        try? await Task.sleep(for: .milliseconds(220))

        restorePasteboard(snapshot)
        selectedText = text
        status = "Selection replaced."
    }

    /// Invoke a standard menu shortcut (for example Command-C or Command-V)
    /// through the source application's Accessibility menu hierarchy.
    ///
    /// This is intentionally independent from selected-text AX attributes: an
    /// app can expose its menu bar correctly even when its editor does not expose
    /// AXSelectedText. It gives Layout Fix a second transport path when synthetic
    /// keyboard events are filtered by macOS.
    private func performMenuShortcut(
        commandCharacter: String,
        in application: NSRunningApplication
    ) -> Bool {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)

        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXMenuBarAttribute as CFString,
            &menuBarValue
        ) == .success,
        let menuBarValue else {
            print("⌨️ LAYOUT FIX AX MENU → menu bar unavailable")
            return false
        }

        let menuBar = unsafeBitCast(menuBarValue, to: AXUIElement.self)
        guard let item = findMenuItem(
            commandCharacter: commandCharacter,
            in: menuBar,
            depth: 0
        ) else {
            print("⌨️ LAYOUT FIX AX MENU → command not found:", commandCharacter)
            return false
        }

        let result = AXUIElementPerformAction(
            item,
            kAXPressAction as CFString
        )
        print(
            "⌨️ LAYOUT FIX AX MENU →",
            commandCharacter,
            "result:",
            result.rawValue
        )
        return result == .success
    }

    private func findMenuItem(
        commandCharacter: String,
        in element: AXUIElement,
        depth: Int
    ) -> AXUIElement? {
        guard depth <= 10 else { return nil }

        var commandValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXMenuItemCmdCharAttribute as CFString,
            &commandValue
        ) == .success,
        let value = commandValue as? String,
        value.caseInsensitiveCompare(commandCharacter) == .orderedSame {
            var enabledValue: CFTypeRef?
            let enabledResult = AXUIElementCopyAttributeValue(
                element,
                kAXEnabledAttribute as CFString,
                &enabledValue
            )

            if enabledResult != .success ||
               (enabledValue as? Bool) != false {
                return element
            }
        }

        var childCount: CFIndex = 0
        guard AXUIElementGetAttributeValueCount(
            element,
            kAXChildrenAttribute as CFString,
            &childCount
        ) == .success,
        childCount > 0 else {
            return nil
        }

        var children: CFArray?
        guard AXUIElementCopyAttributeValues(
            element,
            kAXChildrenAttribute as CFString,
            0,
            childCount,
            &children
        ) == .success,
        let children else {
            return nil
        }

        for index in 0..<CFArrayGetCount(children) {
            let raw = CFArrayGetValueAtIndex(children, index)
            let child = unsafeBitCast(raw, to: AXUIElement.self)

            if let match = findMenuItem(
                commandCharacter: commandCharacter,
                in: child,
                depth: depth + 1
            ) {
                return match
            }
        }

        return nil
    }

    private func postCommandKeyAsync(
        keyCode: CGKeyCode,
        to pid: pid_t
    ) async {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: true
              ),
              let up = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: false
              ) else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand

        down.postToPid(pid)
        try? await Task.sleep(for: .milliseconds(14))
        up.postToPid(pid)
    }

    private func waitForCopiedString(
        pasteboard: NSPasteboard,
        baselineChangeCount: Int,
        timeoutMilliseconds: Int
    ) async -> String? {
        let iterations = max(1, timeoutMilliseconds / 18)
        for _ in 0..<iterations {
            try? await Task.sleep(for: .milliseconds(18))
            guard pasteboard.changeCount != baselineChangeCount else { continue }
            if let value = pasteboard.string(forType: .string), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// Emit a real modifier sequence rather than relying on `flags = .maskCommand`
    /// alone. This more closely mirrors a physical Command-C / Command-V chord.
    private func postPhysicalCommandShortcut(
        keyCode: CGKeyCode,
        tap: CGEventTapLocation
    ) async -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let commandDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Command),
                keyDown: true
              ),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: false
              ),
              let commandUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Command),
                keyDown: false
              ) else {
            print("⌨️ LAYOUT FIX PHYSICAL SHORTCUT → unable to create events")
            return false
        }

        commandDown.flags = .maskCommand
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        commandUp.flags = []

        commandDown.post(tap: tap)
        try? await Task.sleep(for: .milliseconds(12))
        keyDown.post(tap: tap)
        try? await Task.sleep(for: .milliseconds(18))
        keyUp.post(tap: tap)
        try? await Task.sleep(for: .milliseconds(12))
        commandUp.post(tap: tap)

        print(
            "⌨️ LAYOUT FIX PHYSICAL SHORTCUT → posted",
            keyCode == CGKeyCode(kVK_ANSI_C) ? "⌘C" :
            keyCode == CGKeyCode(kVK_ANSI_V) ? "⌘V" : "⌘+\(keyCode)",
            "tap:", tap.rawValue
        )
        return true
    }

    private func postPhysicalCommandShortcutToPID(
        keyCode: CGKeyCode,
        pid: pid_t
    ) async -> Bool {
        guard let source = CGEventSource(stateID: .privateState),
              let commandDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Command),
                keyDown: true
              ),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: false
              ),
              let commandUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Command),
                keyDown: false
              ) else {
            return false
        }

        commandDown.flags = .maskCommand
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        commandUp.flags = []

        commandDown.postToPid(pid)
        try? await Task.sleep(for: .milliseconds(12))
        keyDown.postToPid(pid)
        try? await Task.sleep(for: .milliseconds(18))
        keyUp.postToPid(pid)
        try? await Task.sleep(for: .milliseconds(12))
        commandUp.postToPid(pid)

        print("⌨️ LAYOUT FIX PHYSICAL PID SHORTCUT → posted to", pid)
        return true
    }

    /// Wait until the physical modifiers used by the Layout Fix leader are no
    /// longer depressed. This prevents a synthetic Command-C / Command-V from
    /// accidentally becoming Control-Shift-Command-C/V at the HID layer.
    private func waitForShortcutModifiersToRelease(
        timeoutMilliseconds: Int = 520
    ) async -> Bool {
        let forbidden: CGEventFlags = [
            .maskCommand,
            .maskControl,
            .maskAlternate,
            .maskShift
        ]

        let iterations = max(1, timeoutMilliseconds / 12)
        for _ in 0..<iterations {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection(forbidden).isEmpty {
                // One extra beat keeps the key-up events ahead of our synthetic
                // shortcut in the event stream.
                try? await Task.sleep(for: .milliseconds(18))
                return true
            }
            try? await Task.sleep(for: .milliseconds(12))
        }

        return false
    }

    /// Post a clean Command-key shortcut through the normal HID event path.
    /// `.privateState` is deliberate: unlike `.hidSystemState`, it does not
    /// inherit the user's current physical modifier state from the leader chord.
    private func postCommandKeyToFrontmostAsync(
        keyCode: CGKeyCode
    ) async {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: true
              ),
              let up = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: false
              ) else {
            print("⌨️ LAYOUT FIX HID → unable to create Command event")
            return
        }

        down.flags = .maskCommand
        up.flags = .maskCommand

        down.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(24))
        up.post(tap: .cghidEventTap)

        print(
            "⌨️ LAYOUT FIX HID → posted Command+",
            keyCode == 8 ? "C" : keyCode == 9 ? "V" : "\(keyCode)"
        )
    }

    private func postCommandKey(keyCode: CGKeyCode, to pid: pid_t) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(pid)
        up.postToPid(pid)
    }

    private func remap(_ input: String, from: [Character], to: [Character]) -> String {
        let map = Dictionary(uniqueKeysWithValues: zip(from, to))
        let upperMap = Dictionary(uniqueKeysWithValues: zip(from.map { Character(String($0).uppercased()) }, to.map { Character(String($0).uppercased()) }))
        return String(input.map { char in
            if let mapped = map[char] { return mapped }
            if let mapped = upperMap[char] { return mapped }
            return char
        })
    }

    private func languageScore(_ text: String, target: String) -> Double {
        let lower = text.lowercased()
        let common: [String]
        switch target {
        case "English": common = ["the", "and", "you", "good", "dear", "this", "with", "for", "to", "of"]
        case "Russian": common = ["что", "это", "как", "для", "доб", "при", "на", "не", "я", "и"]
        default: common = ["що", "це", "для", "доб", "при", "на", "не", "я", "і"]
        }
        let hits = common.reduce(0) { $0 + (lower.contains($1) ? 1 : 0) }
        let printable = max(text.count, 1)
        let letters = text.filter { $0.isLetter }.count
        return min(1, Double(hits) * 0.20 + Double(letters) / Double(printable) * 0.25)
    }
}

struct ZestLayoutFixPanel: View {
    let accentColor: Color

    private var leaderShortcut: ZestKeyboardShortcut {
        let key = "zest.settings.layoutFixLeaderShortcut"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(ZestKeyboardShortcut.self, from: data) {
            return decoded
        }
        return ZestKeyboardShortcut(
            keyCode: 37,
            command: false,
            option: false,
            control: true,
            shift: true
        )
    }

    private var targets: [ZestLayoutFixTarget] {
        guard let data = UserDefaults.standard.data(forKey: "zest.settings.layoutFixTargets"),
              let decoded = try? JSONDecoder().decode([ZestLayoutFixTarget].self, from: data)
        else { return [] }
        return decoded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("Layout Fix", systemImage: "keyboard.badge.ellipsis")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
            }

            Text("Select text typed with the wrong keyboard layout, then use one of your Layout Fix shortcuts. Zest corrects the physical keys directly in the original app and shows a confirmation HUD.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if targets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "keyboard.badge.ellipsis")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(accentColor)
                    Text("Set up Layout Fix in Settings")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text("Choose the installed input sources you want to correct to and assign their 1–9 target keys.")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 7) {
                    ForEach(targets) { target in
                        HStack {
                            Text(target.shortLabel)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(accentColor)
                                .frame(width: 34)

                            Text(target.name)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)

                            Spacer()

                            Text("\(leaderShortcut.displayString) → \(target.triggerLabel)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 360)
        .frame(minHeight: 210)
        .zestPopupSurface(accentColor: accentColor, cornerRadius: 22)
    }
}
