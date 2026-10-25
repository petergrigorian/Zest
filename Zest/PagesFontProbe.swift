//
//  PagesFontProbe.swift
//  Zest
//
//  Probe #21
//
//  Pages context-state classifier.
//
//  Purpose:
//  Determine which formatting-reading strategy Zest should use:
//
//  1. Normal Pages text formatting controls available
//     → use Accessibility.
//
//  2. Pages table/cell context with Copy available
//     → inspect copied RTF.
//
//  3. Neither route available
//     → no truthful formatting context.
//
//  DIAGNOSTIC ONLY.
//
//  The probe never modifies the Pages document.
//  It temporarily uses Copy only when available and restores
//  the user's clipboard afterward.
//

import Foundation
import AppKit
import ApplicationServices


enum PagesFontProbe {

    // MARK: - Entry Point

    @MainActor
    static func run(
        pid: pid_t,
        applicationName: String?
    ) {

        print("")
        print("==========================================")
        print("🍊 ZEST PAGES CONTEXT PROBE")
        print("==========================================")
        print("")

        print(
            "Target application: \(applicationName ?? "Unknown")"
        )

        print(
            "Target PID: \(pid)"
        )

        print("")

        guard AXIsProcessTrusted() else {

            print(
                "❌ Accessibility permission unavailable."
            )

            finish()

            return
        }

        let application =
            AXUIElementCreateApplication(
                pid
            )

        guard let window =
            focusedWindow(
                of: application
            )
        else {

            print(
                "❌ Could not resolve Pages focused window."
            )

            finish()

            return
        }

        // -----------------------------------------
        // Scan Pages UI once.
        // -----------------------------------------

        var scan =
            ContextScanResult()

        var scannedCount = 0

        scanContext(
            window,
            depth: 0,
            scannedCount:
                &scannedCount,
            result:
                &scan
        )

        // -----------------------------------------
        // Copy availability.
        // -----------------------------------------

        let copyMenuItem =
            findCopyMenuItem(
                pid: pid
            )

        let copyEnabled =
            copyMenuItem.flatMap {
                copyBool(
                    from: $0,
                    attribute:
                        kAXEnabledAttribute
                )
            } ?? false

        // -----------------------------------------
        // Print classification.
        // -----------------------------------------

        printContextReport(
            scan: scan,
            copyEnabled:
                copyEnabled
        )

        // -----------------------------------------
        // RTF fallback experiment.
        // -----------------------------------------

        if
            !scan.hasFontFamilyControl,
            scan.hasTableFormattingMarker,
            copyEnabled,
            let copyMenuItem
        {

            print("")
            print(
                "------------------------------------------"
            )

            print(
                "RTF FALLBACK TEST"
            )

            print(
                "------------------------------------------"
            )

            print("")

            probeCopiedFormatting(
                copyMenuItem:
                    copyMenuItem
            )

        } else {

            print("")
            print(
                "------------------------------------------"
            )

            print(
                "RTF FALLBACK TEST"
            )

            print(
                "------------------------------------------"
            )

            print("")

            if scan.hasFontFamilyControl {

                print(
                    "⏭️ Skipped."
                )

                print(
                    "Reason: normal Pages text formatting controls are available."
                )

                print(
                    "Production Zest should use the AX reader here."
                )

            } else if !scan.hasTableFormattingMarker {

                print(
                    "⏭️ Skipped."
                )

                print(
                    "Reason: this is not the known Pages table-formatting context."
                )

            } else if !copyEnabled {

                print(
                    "⏭️ Skipped."
                )

                print(
                    "Reason: Pages Copy is disabled in this context."
                )

            } else {

                print(
                    "⏭️ Skipped."
                )

                print(
                    "Reason: Copy menu item unavailable."
                )
            }
        }

        finish()
    }


    // MARK: - Scan Result

    private struct ContextScanResult {

        var hasFontFamilyControl =
            false

        var fontFamilyValue:
            String?

        var hasFontSizeControl =
            false

        var fontSizeValue:
            String?

        var hasTypefaceControl =
            false

        var typefaceValue:
            String?

        var hasTableFormattingMarker =
            false

        var tableFormattingMarker:
            String?
    }


    // MARK: - Context Scan

    private static func scanContext(
        _ element: AXUIElement,
        depth: Int,
        scannedCount: inout Int,
        result: inout ContextScanResult
    ) {

        let maximumDepth =
            20

        let maximumElements =
            2500

        guard
            depth <= maximumDepth,
            scannedCount < maximumElements
        else {
            return
        }

        scannedCount += 1

        let role =
            copyString(
                from: element,
                attribute:
                    kAXRoleAttribute
            )

        let help =
            copyString(
                from: element,
                attribute:
                    kAXHelpAttribute
            )?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        let value =
            copyString(
                from: element,
                attribute:
                    kAXValueAttribute
            )?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        // =========================================
        // FONT FAMILY
        // =========================================

        if
            role == kAXPopUpButtonRole as String,
            help?
                .lowercased()
                == "choose the font family."
        {

            result.hasFontFamilyControl =
                true

            if let value,
               !value.isEmpty
            {
                result.fontFamilyValue =
                    normalizePagesString(
                        value
                    )
            }
        }


        // =========================================
        // FONT SIZE
        // =========================================

        if
            role == kAXTextFieldRole as String,
            help?
                .lowercased()
                == "set the font size."
        {

            result.hasFontSizeControl =
                true

            if let value,
               !value.isEmpty
            {
                result.fontSizeValue =
                    normalizePagesString(
                        value
                    )
            }
        }


        // =========================================
        // TYPEFACE
        // =========================================

        if
            role == kAXPopUpButtonRole as String,
            help?
                .lowercased()
                == "choose the typeface."
        {

            result.hasTypefaceControl =
                true

            if let value,
               !value.isEmpty
            {
                result.typefaceValue =
                    normalizePagesString(
                        value
                    )
            }
        }


        // =========================================
        // TABLE FORMAT MARKER
        // =========================================

        if role == kAXStaticTextRole as String {

            if let value {

                let normalized =
                    value
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .lowercased()

                if normalized
                    == "table font size"
                {

                    result.hasTableFormattingMarker =
                        true

                    result.tableFormattingMarker =
                        value
                }
            }
        }


        // =========================================
        // CHILDREN
        // =========================================

        for child in copyChildren(
            from: element
        ) {

            scanContext(
                child,
                depth:
                    depth + 1,
                scannedCount:
                    &scannedCount,
                result:
                    &result
            )

            if scannedCount
                >= maximumElements
            {
                break
            }
        }
    }


    // MARK: - Report

    private static func printContextReport(
        scan: ContextScanResult,
        copyEnabled: Bool
    ) {

        print(
            "------------------------------------------"
        )

        print(
            "PAGES CONTEXT STATE"
        )

        print(
            "------------------------------------------"
        )

        print("")

        print(
            "Font-family control present: " +
            yesNo(
                scan.hasFontFamilyControl
            )
        )

        if let value =
            scan.fontFamilyValue
        {
            print(
                "  Family value: \(value)"
            )
        }


        print(
            "Font-size control present: " +
            yesNo(
                scan.hasFontSizeControl
            )
        )

        if let value =
            scan.fontSizeValue
        {
            print(
                "  Size value: \(value)"
            )
        }


        print(
            "Typeface control present: " +
            yesNo(
                scan.hasTypefaceControl
            )
        )

        if let value =
            scan.typefaceValue
        {
            print(
                "  Typeface value: \(value)"
            )
        }


        print(
            "\"Table Font Size\" marker present: " +
            yesNo(
                scan.hasTableFormattingMarker
            )
        )


        print(
            "Pages Copy enabled: " +
            yesNo(
                copyEnabled
            )
        )


        print("")
        print(
            "------------------------------------------"
        )

        print(
            "CLASSIFICATION"
        )

        print(
            "------------------------------------------"
        )

        print("")


        if
            scan.hasFontFamilyControl,
            scan.hasFontSizeControl
        {

            print(
                "🟢 TEXT FORMATTING CONTEXT"
            )

            print(
                "Reader: ACCESSIBILITY"
            )

            print("")
            print(
                "Pages exposes its normal semantic text-formatting controls."
            )

            print(
                "Zest should read font family / size directly from AX."
            )

            return
        }


        if
            scan.hasTableFormattingMarker,
            copyEnabled
        {

            print(
                "🟠 TABLE / CELL CONTEXT"
            )

            print(
                "Reader: RTF CLIPBOARD FALLBACK"
            )

            print("")
            print(
                "Pages text-formatting controls are unavailable,"
            )

            print(
                "but the table inspector is active and Copy is enabled."
            )

            return
        }


        if scan.hasTableFormattingMarker {

            print(
                "🟡 TABLE CONTEXT WITHOUT COPY"
            )

            print(
                "Reader: NONE"
            )

            print("")
            print(
                "Pages table inspector is active,"
            )

            print(
                "but Copy is currently disabled."
            )

            return
        }


        print(
            "⚪ NO KNOWN TEXT FORMATTING CONTEXT"
        )

        print(
            "Reader: NONE"
        )
    }


    // MARK: - RTF Probe

    @MainActor
    private static func probeCopiedFormatting(
        copyMenuItem: AXUIElement
    ) {

        let pasteboard =
            NSPasteboard.general

        let snapshot =
            capturePasteboard(
                pasteboard
            )

        print(
            "Original clipboard items: \(snapshot.count)"
        )

        defer {

            restorePasteboard(
                snapshot,
                to:
                    pasteboard
            )

            print("")
            print(
                "♻️ Original clipboard restored."
            )
        }


        let previousChangeCount =
            pasteboard.changeCount


        let result =
            AXUIElementPerformAction(
                copyMenuItem,
                kAXPressAction
                    as CFString
            )


        guard result == .success else {

            print(
                "❌ AXPress Copy failed: \(result.rawValue)"
            )

            return
        }


        print(
            "AXPress Copy: ✅ success"
        )


        let changed =
            waitForPasteboardChange(
                pasteboard,
                previousChangeCount:
                    previousChangeCount,
                timeout:
                    1.0
            )


        guard changed else {

            print(
                "❌ Pasteboard did not change."
            )

            return
        }


        print(
            "Pasteboard changed: ✅"
        )

        print("")


        printPasteboardTypes(
            pasteboard
        )

        print("")


        guard let rtf =
            pasteboard.data(
                forType: .rtf
            )
        else {

            print(
                "❌ No public.rtf representation."
            )

            return
        }


        do {

            let attributed =
                try NSAttributedString(
                    data: rtf,
                    options: [
                        .documentType:
                            NSAttributedString.DocumentType.rtf
                    ],
                    documentAttributes:
                        nil
                )


            print(
                "RTF text: \(debugText(attributed.string))"
            )

            print(
                "RTF length: \(attributed.length)"
            )

            print("")


            guard attributed.length > 0 else {

                print(
                    "❌ RTF contains no characters."
                )

                return
            }


            var runNumber =
                0

            var discoveredFonts:
                [FontRun] = []


            let range =
                NSRange(
                    location: 0,
                    length:
                        attributed.length
                )


            attributed.enumerateAttribute(
                .font,
                in: range,
                options: []
            ) {
                value,
                range,
                _ in

                runNumber += 1


                let text =
                    attributed
                        .attributedSubstring(
                            from: range
                        )
                        .string


                print(
                    "RUN \(runNumber)"
                )

                print(
                    "  Range: \(range.location)..<\(NSMaxRange(range))"
                )

                print(
                    "  Text: \(debugText(text))"
                )


                guard let font =
                    value as? NSFont
                else {

                    print(
                        "  Font: <none>"
                    )

                    print("")

                    return
                }


                let family =
                    font.familyName
                    ?? font.fontName


                print(
                    "  Family: \(family)"
                )

                print(
                    "  Font name: \(font.fontName)"
                )

                print(
                    "  Display name: \(font.displayName ?? "<nil>")"
                )

                print(
                    "  Size: \(font.pointSize)"
                )


                let traits =
                    NSFontManager.shared
                        .traits(
                            of: font
                        )


                print(
                    "  Bold: \(traits.contains(.boldFontMask))"
                )

                print(
                    "  Italic: \(traits.contains(.italicFontMask))"
                )


                let weight =
                    NSFontManager.shared
                        .weight(
                            of: font
                        )


                print(
                    "  AppKit weight: \(weight)"
                )


                discoveredFonts.append(
                    FontRun(
                        family:
                            family,
                        fontName:
                            font.fontName,
                        size:
                            font.pointSize,
                        bold:
                            traits.contains(
                                .boldFontMask
                            ),
                        italic:
                            traits.contains(
                                .italicFontMask
                            )
                    )
                )


                print("")
            }


            print(
                "------------------------------------------"
            )

            print(
                "RTF RESULT"
            )

            print(
                "------------------------------------------"
            )

            print("")


            if discoveredFonts.isEmpty {

                print(
                    "❌ No font information found."
                )

                return
            }


            let unique =
                uniqueFontRuns(
                    discoveredFonts
                )


            if unique.count == 1,
               let font =
                    unique.first
            {

                print(
                    "✅ SINGLE FORMATTING"
                )

                print(
                    "Family: \(font.family)"
                )

                print(
                    "Font name: \(font.fontName)"
                )

                print(
                    "Size: \(font.size)"
                )

                print(
                    "Bold: \(font.bold)"
                )

                print(
                    "Italic: \(font.italic)"
                )

            } else {

                print(
                    "🟣 MIXED FORMATTING"
                )

                print(
                    "Unique font configurations: \(unique.count)"
                )

                print("")


                for (
                    index,
                    font
                ) in unique.enumerated()
                {

                    print(
                        "\(index + 1). \(font.family)"
                    )

                    print(
                        "   Font name: \(font.fontName)"
                    )

                    print(
                        "   Size: \(font.size)"
                    )

                    print(
                        "   Bold: \(font.bold)"
                    )

                    print(
                        "   Italic: \(font.italic)"
                    )
                }
            }


        } catch {

            print(
                "❌ RTF decoding failed:"
            )

            print(
                error.localizedDescription
            )
        }
    }


    // MARK: - Font Run

    private struct FontRun {

        let family:
            String

        let fontName:
            String

        let size:
            CGFloat

        let bold:
            Bool

        let italic:
            Bool
    }


    private static func uniqueFontRuns(
        _ runs: [FontRun]
    ) -> [FontRun] {

        var result:
            [FontRun] = []


        for run in runs {

            let alreadyExists =
                result.contains {
                    existing in

                    existing.family
                        == run.family
                    &&
                    existing.fontName
                        == run.fontName
                    &&
                    abs(
                        existing.size
                        - run.size
                    ) < 0.01
                    &&
                    existing.bold
                        == run.bold
                    &&
                    existing.italic
                        == run.italic
                }


            if !alreadyExists {

                result.append(
                    run
                )
            }
        }


        return result
    }


    // MARK: - Copy Menu

    private static func findCopyMenuItem(
        pid: pid_t
    ) -> AXUIElement? {

        let application =
            AXUIElementCreateApplication(
                pid
            )


        guard let menuBar =
            copyElement(
                from: application,
                attribute:
                    kAXMenuBarAttribute
            )
        else {
            return nil
        }


        var scannedCount =
            0


        return findCopyMenuItem(
            in: menuBar,
            depth: 0,
            scannedCount:
                &scannedCount
        )
    }


    private static func findCopyMenuItem(
        in element: AXUIElement,
        depth: Int,
        scannedCount: inout Int
    ) -> AXUIElement? {

        let maximumDepth =
            14

        let maximumElements =
            1600


        guard
            depth <= maximumDepth,
            scannedCount < maximumElements
        else {
            return nil
        }


        scannedCount += 1


        let role =
            copyString(
                from: element,
                attribute:
                    kAXRoleAttribute
            )


        if role
            == kAXMenuItemRole as String
        {

            let title =
                copyString(
                    from: element,
                    attribute:
                        kAXTitleAttribute
                )?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )


            if title == "Copy" {
                return element
            }
        }


        for child in copyChildren(
            from: element
        ) {

            if let result =
                findCopyMenuItem(
                    in: child,
                    depth:
                        depth + 1,
                    scannedCount:
                        &scannedCount
                )
            {
                return result
            }


            if scannedCount
                >= maximumElements
            {
                break
            }
        }


        return nil
    }


    // MARK: - Clipboard Snapshot

    private struct PasteboardItemSnapshot {

        let representations:
            [
                (
                    type:
                        NSPasteboard.PasteboardType,
                    data:
                        Data
                )
            ]
    }


    private static func capturePasteboard(
        _ pasteboard:
            NSPasteboard
    ) -> [PasteboardItemSnapshot] {

        guard let items =
            pasteboard.pasteboardItems
        else {
            return []
        }


        return items.map {
            item in

            var representations:
                [
                    (
                        type:
                            NSPasteboard.PasteboardType,
                        data:
                            Data
                    )
                ] = []


            for type in item.types {

                guard let data =
                    item.data(
                        forType: type
                    )
                else {
                    continue
                }


                representations.append(
                    (
                        type:
                            type,
                        data:
                            data
                    )
                )
            }


            return PasteboardItemSnapshot(
                representations:
                    representations
            )
        }
    }


    private static func restorePasteboard(
        _ snapshot:
            [PasteboardItemSnapshot],
        to pasteboard:
            NSPasteboard
    ) {

        pasteboard.clearContents()


        guard !snapshot.isEmpty else {
            return
        }


        let items:
            [NSPasteboardItem] =
            snapshot.map {
                snapshotItem in

                let item =
                    NSPasteboardItem()


                for representation
                    in snapshotItem
                        .representations
                {

                    item.setData(
                        representation.data,
                        forType:
                            representation.type
                    )
                }


                return item
            }


        pasteboard.writeObjects(
            items
        )
    }


    // MARK: - Pasteboard Wait

    private static func waitForPasteboardChange(
        _ pasteboard:
            NSPasteboard,
        previousChangeCount:
            Int,
        timeout:
            TimeInterval
    ) -> Bool {

        let deadline =
            Date()
                .addingTimeInterval(
                    timeout
                )


        while Date() < deadline {

            if pasteboard.changeCount
                != previousChangeCount
            {
                return true
            }


            RunLoop.current.run(
                until:
                    Date()
                        .addingTimeInterval(
                            0.02
                        )
            )
        }


        return pasteboard.changeCount
            != previousChangeCount
    }


    // MARK: - Pasteboard Types

    private static func printPasteboardTypes(
        _ pasteboard:
            NSPasteboard
    ) {

        print(
            "PASTEBOARD TYPES"
        )

        print(
            "------------------------------------------"
        )


        guard let items =
            pasteboard.pasteboardItems,
              !items.isEmpty
        else {

            print(
                "<none>"
            )

            return
        }


        for (
            index,
            item
        ) in items.enumerated()
        {

            print(
                "ITEM \(index + 1)"
            )


            for type in item.types {

                let size =
                    item.data(
                        forType: type
                    )?
                    .count
                    ?? 0


                print(
                    "  \(type.rawValue) — \(size) bytes"
                )
            }
        }
    }


    // MARK: - Focused Window

    private static func focusedWindow(
        of application:
            AXUIElement
    ) -> AXUIElement? {

        copyElement(
            from: application,
            attribute:
                kAXFocusedWindowAttribute
        )
    }


    // MARK: - AX Helpers

    private static func copyElement(
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
            let value
        else {
            return nil
        }


        guard CFGetTypeID(
            value
        ) == AXUIElementGetTypeID()
        else {
            return nil
        }


        return unsafeDowncast(
            value as AnyObject,
            to:
                AXUIElement.self
        )
    }


    private static func copyChildren(
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
            let value
        else {
            return []
        }


        guard let array =
            value as? [AXUIElement]
        else {
            return []
        }


        return array
    }


    private static func copyString(
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


    private static func copyBool(
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
            let value
        else {
            return nil
        }


        if let number =
            value as? NSNumber
        {
            return number.boolValue
        }


        return nil
    }


    // MARK: - Helpers

    private static func normalizePagesString(
        _ value:
            String
    ) -> String {

        value
            .replacingOccurrences(
                of: "\u{FEFF}",
                with: ""
            )
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
    }


    private static func yesNo(
        _ value:
            Bool
    ) -> String {

        value
            ? "YES"
            : "NO"
    }


    private static func debugText(
        _ text:
            String
    ) -> String {

        let escaped =
            text
                .replacingOccurrences(
                    of: "\\",
                    with: "\\\\"
                )
                .replacingOccurrences(
                    of: "\n",
                    with: "\\n"
                )
                .replacingOccurrences(
                    of: "\r",
                    with: "\\r"
                )
                .replacingOccurrences(
                    of: "\t",
                    with: "\\t"
                )


        if escaped.count <= 180 {

            return "\"\(escaped)\""
        }


        let end =
            escaped.index(
                escaped.startIndex,
                offsetBy:
                    180
            )


        return
            "\"\(escaped[..<end])…\""
    }


    // MARK: - Finish

    private static func finish() {

        print("")
        print(
            "=========================================="
        )

        print(
            "🍊 END PAGES CONTEXT PROBE"
        )

        print(
            "=========================================="
        )

        print("")
    }
}
