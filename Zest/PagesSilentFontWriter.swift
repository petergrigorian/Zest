//
//  PagesSilentFontWriter.swift
//  Zest
//
//  Silent selected-text font writer for Pages.
//
//  Production path:
//
//      selected text
//          ↓
//      invisible Copy
//          ↓
//      correlate against body text
//          ↓
//      duplicate?
//          ↓
//      temporarily expand selection left
//          ↓
//      unique body-text context
//          ↓
//      restore original selection
//          ↓
//      direct AppleScript body-range font write
//
//  If there is NO selection, Copy is disabled and this writer
//  returns .noSelection. TextContextManager can then use the
//  existing AX popup writer as the caret-only fallback.
//

import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox


@MainActor
enum PagesSilentFontWriter {

    // MARK: - Public Result

    enum Result {
        case applied(canonicalFamily: String)
        case noSelection
        case failed(reason: String)
    }


    // MARK: - Private Types

    private struct DocumentIdentity: Equatable {
        let id: String
        let name: String
    }

    private struct BodyRange: Equatable {
        let start: Int
        let end: Int

        var length: Int {
            end - start + 1
        }
    }

    private typealias PasteboardSnapshot =
        [[NSPasteboard.PasteboardType: Data]]


    // MARK: - Entry

    static func apply(
        family requestedFontName: String,
        pid: pid_t
    ) -> Result {
        applyFontName(requestedFontName, pid: pid)
    }

    /// Silent selected-text writer for an exact installed font face.
    /// `fontName` should normally be the PostScript font name returned by
    /// NSFontManager.availableMembers(ofFontFamily:).
    static func apply(
        typeface requestedTypeface: String,
        family: String,
        pid: pid_t
    ) -> Result {
        guard let fontName = installedFontName(
            family: family,
            face: requestedTypeface
        ) else {
            return .failed(
                reason: "Could not resolve the requested typeface to an installed font."
            )
        }

        print("🍊 Resolved typeface \(requestedTypeface) → \(fontName)")
        return applyFontName(fontName, pid: pid)
    }

    private static func applyFontName(
        _ requestedFontName: String,
        pid: pid_t
    ) -> Result {

        print("")
        print("------------------------------------------")
        print("🍊 SILENT PAGES FONT BACKEND")
        print("------------------------------------------")

        guard
            let runningApplication =
                NSRunningApplication(
                    processIdentifier: pid
                ),
            runningApplication.bundleIdentifier ==
                "com.apple.Pages"
        else {

            return .failed(
                reason: "Target process is not Pages."
            )
        }

        guard AXIsProcessTrusted() else {

            return .failed(
                reason: "Accessibility permission is unavailable."
            )
        }


        // =========================================
        // LOCK THE EXACT PAGES DOCUMENT
        // =========================================

        guard
            let document =
                readFrontDocumentIdentity()
        else {

            return .failed(
                reason: "Could not identify the front Pages document."
            )
        }

        print(
            "Document:",
            "\"\(document.name)\""
        )

        print(
            "Document ID:",
            document.id
        )


        // =========================================
        // SNAPSHOT BODY TEXT
        // =========================================

        guard
            let bodyBefore =
                readBodyText(
                    documentID: document.id
                )
        else {

            return .failed(
                reason: "Could not read Pages body text."
            )
        }


        // =========================================
        // FIND CLOSED-MENU COPY COMMAND
        // =========================================

        let applicationElement =
            AXUIElementCreateApplication(pid)

        let copyCandidates =
            findAllMenuItems(
                in: applicationElement,
                title: "Copy"
            )

        let usableCopyCandidates =
            copyCandidates.filter { element in

                let enabled =
                    boolAttribute(
                        element,
                        kAXEnabledAttribute
                    )
                    ?? false

                let actions =
                    actionNames(
                        of: element
                    )

                return
                    enabled &&
                    actions.contains(
                        kAXPressAction
                    )
            }


        // Probe #20 established that Copy is disabled
        // at a collapsed Pages caret.
        //
        // This is therefore our clean selection/caret fork.

        guard
            let copyItem =
                usableCopyCandidates.first
        else {

            print(
                "↪️ Copy is disabled — collapsed caret detected."
            )

            return .noSelection
        }

        print(
            "✅ Active text selection detected."
        )


        // =========================================
        // PRESERVE USER CLIPBOARD
        // =========================================

        let pasteboard =
            NSPasteboard.general

        let originalPasteboard =
            capturePasteboard(
                pasteboard
            )

        defer {

            restorePasteboard(
                pasteboard,
                snapshot:
                    originalPasteboard
            )

            print(
                "🍊 Clipboard restored."
            )
        }


        // =========================================
        // COPY ORIGINAL SELECTION
        // =========================================

        guard
            let originalSelection =
                copySelection(
                    using: copyItem,
                    pasteboard: pasteboard
                ),
            !originalSelection.isEmpty
        else {

            return .failed(
                reason:
                    "Pages reported an active selection, but Zest could not copy it."
            )
        }

        print(
            "Selection:",
            quoted(
                originalSelection
            )
        )


        // =========================================
        // FIND ORIGINAL BODY CANDIDATES
        // =========================================

        let originalCandidates =
            ranges(
                of: originalSelection,
                in: bodyBefore
            )

        guard
            !originalCandidates.isEmpty
        else {

            return .failed(
                reason:
                    "Selected Pages text was not found in body text."
            )
        }

        print(
            "Body matches:",
            originalCandidates.count
        )


        // =========================================
        // UNIQUE SELECTION — EASY PATH
        // =========================================

        if originalCandidates.count == 1,
           let onlyRange =
                originalCandidates.first {

            print(
                "🎯 Unique selection range:",
                "\(onlyRange.start)...\(onlyRange.end)"
            )

            return performWrite(
                document:
                    document,
                bodyBefore:
                    bodyBefore,
                originalSelection:
                    originalSelection,
                range:
                    onlyRange,
                requestedFontName:
                    requestedFontName
            )
        }


        // =========================================
        // DUPLICATE SELECTION
        // =========================================

        print(
            "Selection is ambiguous:",
            "\(originalCandidates.count) identical occurrences."
        )

        print(
            "Expanding selection LEFT for context..."
        )

        let maximumExpansionSteps = 64

        var expansionSteps = 0
        var resolvedExpandedRange:
            BodyRange?

        var expandedSelection =
            originalSelection


        while
            expansionSteps <
                maximumExpansionSteps
        {

            expansionSteps += 1

            sendShiftLeft()

            tinyRunLoopDelay(
                0.025
            )

            guard
                let copied =
                    copySelection(
                        using:
                            copyItem,
                        pasteboard:
                            pasteboard
                    )
            else {

                restoreSelectionAfterLeftExpansion(
                    steps:
                        expansionSteps
                )

                return .failed(
                    reason:
                        "Could not copy the temporarily expanded selection."
                )
            }

            expandedSelection =
                copied

            let expandedCandidates =
                ranges(
                    of:
                        expandedSelection,
                    in:
                        bodyBefore
                )

            print(
                "Context step \(expansionSteps):",
                "\(expandedCandidates.count) match(es)"
            )

            if expandedCandidates.count == 1 {

                resolvedExpandedRange =
                    expandedCandidates.first

                break
            }

            if expandedSelection.isEmpty {

                restoreSelectionAfterLeftExpansion(
                    steps:
                        expansionSteps
                )

                return .failed(
                    reason:
                        "Selection unexpectedly collapsed while resolving duplicate context."
                )
            }
        }


        // =========================================
        // RESTORE ORIGINAL SELECTION
        // =========================================

        restoreSelectionAfterLeftExpansion(
            steps:
                expansionSteps
        )

        tinyRunLoopDelay(
            0.035
        )

        guard
            let restoredSelection =
                copySelection(
                    using:
                        copyItem,
                    pasteboard:
                        pasteboard
                )
        else {

            return .failed(
                reason:
                    "Could not verify selection restoration."
            )
        }

        guard
            restoredSelection ==
                originalSelection
        else {

            return .failed(
                reason:
                    "Original Pages selection was not restored exactly."
            )
        }

        print(
            "✅ Original selection restored."
        )


        // =========================================
        // RESOLVE ORIGINAL RANGE
        // =========================================

        guard
            let expandedRange =
                resolvedExpandedRange
        else {

            return .failed(
                reason:
                    "Could not uniquely resolve duplicate selection within \(maximumExpansionSteps) context characters."
            )
        }


        // Probe #18 established that extending LEFT adds
        // characters before the original selection.
        //
        // Therefore the original selection ends at the
        // same character as the expanded selection.

        let originalLength =
            characterCount(
                originalSelection
            )

        let resolvedRange =
            BodyRange(
                start:
                    expandedRange.end
                    - originalLength
                    + 1,
                end:
                    expandedRange.end
            )

        print(
            "🎯 Resolved duplicate range:",
            "\(resolvedRange.start)...\(resolvedRange.end)"
        )


        // Safety gate:
        // the calculated range MUST be one of the
        // original exact-text candidates.

        guard
            originalCandidates.contains(
                resolvedRange
            )
        else {

            return .failed(
                reason:
                    "Resolved range failed the original-candidate safety check."
            )
        }


        // =========================================
        // WRITE
        // =========================================

        return performWrite(
            document:
                document,
            bodyBefore:
                bodyBefore,
            originalSelection:
                originalSelection,
            range:
                resolvedRange,
            requestedFontName:
                requestedFontName
        )
    }


    // MARK: - Perform Silent Write

    private static func performWrite(
        document: DocumentIdentity,
        bodyBefore: String,
        originalSelection: String,
        range: BodyRange,
        requestedFontName: String
    ) -> Result {

        guard
            verifyFrontDocument(
                document
            )
        else {

            return .failed(
                reason:
                    "Front Pages document changed before the font write."
            )
        }

        guard
            let bodyImmediatelyBeforeWrite =
                readBodyText(
                    documentID:
                        document.id
                ),
            bodyImmediatelyBeforeWrite ==
                bodyBefore
        else {

            return .failed(
                reason:
                    "Pages body text changed before the font write."
            )
        }


        // =========================================
        // RANGE CONTENT SAFETY CHECK
        // =========================================

        guard
            let bodySlice =
                text(
                    in:
                        range,
                    from:
                        bodyBefore
                ),
            bodySlice ==
                originalSelection
        else {

            return .failed(
                reason:
                    "Resolved range no longer matches the selected text."
            )
        }

        print(
            "✅ All silent-write safety gates passed."
        )


        // =========================================
        // APPLESCRIPT WRITE
        // =========================================

        let escapedDocumentID =
            appleScriptEscaped(
                document.id
            )

        let escapedFamily =
            appleScriptEscaped(
                requestedFontName
            )

        let script =
            """
            tell application id "com.apple.Pages"
                tell document id "\(escapedDocumentID)"
                    set font of characters \(range.start) thru \(range.end) of body text to "\(escapedFamily)"
                end tell
            end tell
            """

        print(
            "🍎 Writing",
            "\"\(requestedFontName)\"",
            "to",
            "\(range.start)...\(range.end)"
        )

        guard
            executeAppleScript(
                script
            )
        else {

            return .failed(
                reason:
                    "Pages rejected the direct body-range font write."
            )
        }


        // =========================================
        // VERIFY DOCUMENT TEXT DID NOT CHANGE
        // =========================================

        guard
            verifyFrontDocument(
                document
            )
        else {

            return .failed(
                reason:
                    "Front document changed immediately after the font write."
            )
        }

        guard
            let bodyAfter =
                readBodyText(
                    documentID:
                        document.id
                ),
            bodyAfter ==
                bodyBefore
        else {

            return .failed(
                reason:
                    "Document text changed during the font operation."
            )
        }


        // =========================================
        // VERIFY FONT CHARACTER-BY-CHARACTER
        // =========================================

        guard
            let fonts =
                readFonts(
                    documentID:
                        document.id,
                    range:
                        range
                )
        else {

            // The write itself succeeded and text remained
            // unchanged. Do not perform a second write merely
            // because read-back failed.

            print(
                "⚠️ Font write succeeded, but read-back was unavailable."
            )

            return .applied(
                canonicalFamily:
                    requestedFontName
            )
        }

        let normalizedRequested =
            normalizeFontName(
                requestedFontName
            )

        let everyCharacterMatches =
            !fonts.isEmpty &&
            fonts.allSatisfy { font in

                fontNamesMatch(
                    font,
                    normalizedRequested
                )
            }

        print(
            "Font read-back:",
            fonts
        )

        guard
            everyCharacterMatches
        else {

            return .failed(
                reason:
                    "Pages completed the write, but character-level font verification did not match."
            )
        }

        print(
            "🎉 SILENT FONT WRITE VERIFIED."
        )

        return .applied(
            canonicalFamily:
                normalizedRequested
        )
    }


    // MARK: - Installed Typeface Resolution

    private static func installedFontName(
        family: String,
        face: String
    ) -> String? {
        guard let members = NSFontManager.shared.availableMembers(
            ofFontFamily: family
        ) else {
            return nil
        }

        let wanted = normalizeFontName(face)

        for member in members {
            guard member.count >= 2,
                  let postScriptName = member[0] as? String,
                  let faceName = member[1] as? String
            else { continue }

            if fontNamesMatch(normalizeFontName(faceName), wanted) {
                return postScriptName
            }
        }

        return nil
    }

    // MARK: - Read Character Fonts

    private static func readFonts(
        documentID: String,
        range: BodyRange
    ) -> [String]? {

        let escapedID =
            appleScriptEscaped(
                documentID
            )

        let script =
            """
            tell application id "com.apple.Pages"
                tell document id "\(escapedID)"
                    set fontList to {}
                    repeat with i from \(range.start) to \(range.end)
                        set end of fontList to (font of character i of body text as text)
                    end repeat
                    return fontList
                end tell
            end tell
            """

        guard
            let descriptor =
                executeAppleScriptReturningDescriptor(
                    script
                )
        else {

            return nil
        }

        var result:
            [String] = []

        if descriptor.numberOfItems > 0 {

            for index in
                1...descriptor.numberOfItems {

                guard
                    let item =
                        descriptor.atIndex(
                            index
                        )
                else {
                    continue
                }

                if let value =
                    item.stringValue {

                    result.append(
                        normalizeFontName(
                            value
                        )
                    )
                }
            }

        } else if
            let value =
                descriptor.stringValue {

            result.append(
                normalizeFontName(
                    value
                )
            )
        }

        return result
    }


    // MARK: - Copy Selection

    private static func copySelection(
        using copyItem: AXUIElement,
        pasteboard: NSPasteboard
    ) -> String? {

        let oldChangeCount =
            pasteboard.changeCount

        let result =
            AXUIElementPerformAction(
                copyItem,
                kAXPressAction
                    as CFString
            )

        guard result == .success else {
            return nil
        }

        let deadline =
            Date()
                .addingTimeInterval(
                    0.25
                )

        while Date() < deadline {

            if pasteboard.changeCount !=
                oldChangeCount {

                if let text =
                    pasteboard.string(
                        forType:
                            .string
                    ) {

                    return text
                }
            }

            RunLoop.current.run(
                until:
                    Date()
                        .addingTimeInterval(
                            0.005
                        )
            )
        }

        return pasteboard.string(
            forType:
                .string
        )
    }


    // MARK: - Selection Keyboard Operations

    private static func sendShiftLeft() {

        sendKey(
            keyCode:
                CGKeyCode(
                    kVK_LeftArrow
                ),
            flags:
                .maskShift
        )
    }


    private static func sendShiftRight() {

        sendKey(
            keyCode:
                CGKeyCode(
                    kVK_RightArrow
                ),
            flags:
                .maskShift
        )
    }


    private static func sendKey(
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) {

        guard
            let source =
                CGEventSource(
                    stateID:
                        .hidSystemState
                )
        else {
            return
        }

        guard
            let keyDown =
                CGEvent(
                    keyboardEventSource:
                        source,
                    virtualKey:
                        keyCode,
                    keyDown:
                        true
                ),
            let keyUp =
                CGEvent(
                    keyboardEventSource:
                        source,
                    virtualKey:
                        keyCode,
                    keyDown:
                        false
                )
        else {
            return
        }

        keyDown.flags =
            flags

        keyUp.flags =
            flags

        keyDown.post(
            tap:
                .cghidEventTap
        )

        keyUp.post(
            tap:
                .cghidEventTap
        )
    }


    private static func restoreSelectionAfterLeftExpansion(
        steps: Int
    ) {

        guard steps > 0 else {
            return
        }

        for _ in 0..<steps {

            sendShiftRight()

            tinyRunLoopDelay(
                0.012
            )
        }
    }


    private static func tinyRunLoopDelay(
        _ seconds: TimeInterval
    ) {

        RunLoop.current.run(
            until:
                Date()
                    .addingTimeInterval(
                        seconds
                    )
        )
    }


    // MARK: - Body Matching

    private static func ranges(
        of needle: String,
        in haystack: String
    ) -> [BodyRange] {

        guard !needle.isEmpty else {
            return []
        }

        let source =
            haystack as NSString

        let target =
            needle as NSString

        var results:
            [BodyRange] = []

        var searchLocation = 0

        while
            searchLocation <=
                source.length
                - target.length
        {

            let searchRange =
                NSRange(
                    location:
                        searchLocation,
                    length:
                        source.length
                        - searchLocation
                )

            let found =
                source.range(
                    of:
                        needle,
                    options: [],
                    range:
                        searchRange
                )

            if found.location ==
                NSNotFound {

                break
            }

            // Pages AppleScript character ranges are 1-based.
            let start =
                found.location + 1

            let end =
                found.location
                + found.length

            results.append(
                BodyRange(
                    start:
                        start,
                    end:
                        end
                )
            )

            searchLocation =
                found.location
                + max(
                    found.length,
                    1
                )
        }

        return results
    }


    private static func text(
        in range: BodyRange,
        from body: String
    ) -> String? {

        let nsBody =
            body as NSString

        let location =
            range.start - 1

        let length =
            range.length

        guard
            location >= 0,
            length >= 0,
            location + length <=
                nsBody.length
        else {

            return nil
        }

        return nsBody.substring(
            with:
                NSRange(
                    location:
                        location,
                    length:
                        length
                )
        )
    }


    private static func characterCount(
        _ string: String
    ) -> Int {

        // This intentionally matches NSString indexing used
        // for body correlation in the currently proven Pages
        // pipeline.

        (string as NSString).length
    }


    // MARK: - Document

    private static func readFrontDocumentIdentity()
        -> DocumentIdentity? {

        guard
            let descriptor =
                executeAppleScriptReturningDescriptor(
                    """
                    tell application id "com.apple.Pages"
                        tell front document
                            return {id as text, name as text}
                        end tell
                    end tell
                    """
                ),
            descriptor.numberOfItems >= 2,
            let id =
                descriptor.atIndex(1)?
                    .stringValue,
            let name =
                descriptor.atIndex(2)?
                    .stringValue
        else {

            return nil
        }

        return DocumentIdentity(
            id:
                id,
            name:
                name
        )
    }


    private static func verifyFrontDocument(
        _ expected: DocumentIdentity
    ) -> Bool {

        guard
            let current =
                readFrontDocumentIdentity()
        else {

            return false
        }

        return
            current.id ==
            expected.id
    }


    private static func readBodyText(
        documentID: String
    ) -> String? {

        let escapedID =
            appleScriptEscaped(
                documentID
            )

        guard
            let descriptor =
                executeAppleScriptReturningDescriptor(
                    """
                    tell application id "com.apple.Pages"
                        tell document id "\(escapedID)"
                            return body text as text
                        end tell
                    end tell
                    """
                )
        else {

            return nil
        }

        return descriptor.stringValue
    }


    // MARK: - Pasteboard

    private static func capturePasteboard(
        _ pasteboard: NSPasteboard
    ) -> PasteboardSnapshot {

        guard
            let items =
                pasteboard.pasteboardItems
        else {

            return []
        }

        var snapshot:
            PasteboardSnapshot = []

        for item in items {

            var itemSnapshot:
                [NSPasteboard.PasteboardType: Data] = [:]

            for type in
                item.types {

                if let data =
                    item.data(
                        forType:
                            type
                    ) {

                    itemSnapshot[
                        type
                    ] = data
                }
            }

            snapshot.append(
                itemSnapshot
            )
        }

        return snapshot
    }


    private static func restorePasteboard(
        _ pasteboard: NSPasteboard,
        snapshot: PasteboardSnapshot
    ) {

        pasteboard.clearContents()

        guard
            !snapshot.isEmpty
        else {

            return
        }

        var restoredItems:
            [NSPasteboardItem] = []

        for itemSnapshot in
            snapshot {

            let item =
                NSPasteboardItem()

            for (type, data) in
                itemSnapshot {

                item.setData(
                    data,
                    forType:
                        type
                )
            }

            restoredItems.append(
                item
            )
        }

        pasteboard.writeObjects(
            restoredItems
        )
    }


    // MARK: - Closed Menu Search

    private static func findAllMenuItems(
        in root: AXUIElement,
        title: String
    ) -> [AXUIElement] {

        var results:
            [AXUIElement] = []

        var visited =
            Set<CFHashCode>()

        scanAXTree(
            root,
            depth:
                0,
            maximumDepth:
                12,
            visited:
                &visited
        ) { element in

            guard
                stringAttribute(
                    element,
                    kAXRoleAttribute
                )
                == kAXMenuItemRole
            else {
                return
            }

            guard
                stringAttribute(
                    element,
                    kAXTitleAttribute
                )
                == title
            else {
                return
            }

            results.append(
                element
            )
        }

        return results
    }


    private static func scanAXTree(
        _ element: AXUIElement,
        depth: Int,
        maximumDepth: Int,
        visited: inout Set<CFHashCode>,
        visit: (AXUIElement) -> Void
    ) {

        guard
            depth <=
                maximumDepth
        else {

            return
        }

        let hash =
            CFHash(
                element
            )

        guard
            !visited.contains(
                hash
            )
        else {

            return
        }

        visited.insert(
            hash
        )

        visit(
            element
        )

        let childAttributes = [
            kAXChildrenAttribute,
            kAXMenuBarAttribute,
            kAXWindowsAttribute
        ]

        for attribute in
            childAttributes {

            let children =
                elementArrayAttribute(
                    element,
                    attribute
                )

            for child in
                children {

                scanAXTree(
                    child,
                    depth:
                        depth + 1,
                    maximumDepth:
                        maximumDepth,
                    visited:
                        &visited,
                    visit:
                        visit
                )
            }
        }
    }


    // MARK: - AX Helpers

    private static func stringAttribute(
        _ element: AXUIElement,
        _ attribute: String
    ) -> String? {

        var value:
            CFTypeRef?

        let error =
            AXUIElementCopyAttributeValue(
                element,
                attribute
                    as CFString,
                &value
            )

        guard
            error == .success
        else {

            return nil
        }

        return value as? String
    }


    private static func boolAttribute(
        _ element: AXUIElement,
        _ attribute: String
    ) -> Bool? {

        var value:
            CFTypeRef?

        let error =
            AXUIElementCopyAttributeValue(
                element,
                attribute
                    as CFString,
                &value
            )

        guard
            error == .success
        else {

            return nil
        }

        return (
            value as? NSNumber
        )?.boolValue
    }


    private static func elementArrayAttribute(
        _ element: AXUIElement,
        _ attribute: String
    ) -> [AXUIElement] {

        var value:
            CFTypeRef?

        let error =
            AXUIElementCopyAttributeValue(
                element,
                attribute
                    as CFString,
                &value
            )

        guard
            error == .success,
            let value
        else {

            return []
        }

        return value as? [AXUIElement]
            ?? []
    }


    private static func actionNames(
        of element: AXUIElement
    ) -> [String] {

        var names:
            CFArray?

        let error =
            AXUIElementCopyActionNames(
                element,
                &names
            )

        guard
            error == .success,
            let names =
                names as? [String]
        else {

            return []
        }

        return names
    }


    // MARK: - AppleScript

    private static func executeAppleScript(
        _ source: String
    ) -> Bool {

        executeAppleScriptReturningDescriptor(
            source
        ) != nil
    }


    private static func executeAppleScriptReturningDescriptor(
        _ source: String
    ) -> NSAppleEventDescriptor? {

        guard
            let script =
                NSAppleScript(
                    source:
                        source
                )
        else {

            print(
                "❌ Could not create NSAppleScript."
            )

            return nil
        }

        var errorInfo:
            NSDictionary?

        let descriptor =
            script.executeAndReturnError(
                &errorInfo
            )

        if let errorInfo {

            let number =
                (
                    errorInfo[
                        NSAppleScript.errorNumber
                    ]
                    as? NSNumber
                )?.intValue
                ?? -1

            let message =
                errorInfo[
                    NSAppleScript.errorMessage
                ]
                as? String
                ?? "Unknown AppleScript error"

            print(
                "❌ AppleScript error \(number):",
                message
            )

            return nil
        }

        return descriptor
    }


    // MARK: - Font Matching

    private static func fontNamesMatch(
        _ lhs: String,
        _ rhs: String
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


    private static func normalizeFontName(
        _ raw: String
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


    private static func shouldStripFontEdgeScalar(
        _ scalar: UnicodeScalar
    ) -> Bool {

        if CharacterSet
            .whitespacesAndNewlines
            .contains(
                scalar
            ) {

            return true
        }

        if CharacterSet
            .controlCharacters
            .contains(
                scalar
            ) {

            return true
        }

        if CharacterSet
            .illegalCharacters
            .contains(
                scalar
            ) {

            return true
        }

        if scalar.properties
            .generalCategory ==
            .format {

            return true
        }

        return false
    }


    // MARK: - Utility

    private static func appleScriptEscaped(
        _ string: String
    ) -> String {

        string
            .replacingOccurrences(
                of:
                    "\\",
                with:
                    "\\\\"
            )
            .replacingOccurrences(
                of:
                    "\"",
                with:
                    "\\\""
            )
    }


    private static func quoted(
        _ string: String
    ) -> String {

        let escaped =
            string
                .replacingOccurrences(
                    of:
                        "\n",
                    with:
                        "\\n"
                )
                .replacingOccurrences(
                    of:
                        "\r",
                    with:
                        "\\r"
                )
                .replacingOccurrences(
                    of:
                        "\"",
                    with:
                        "\\\""
                )

        return
            "\""
            + escaped
            + "\""
    }
}
