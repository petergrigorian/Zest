//
//  FontLibraryManager.swift
//  Zest
//
//  Provides Zest with a system-wide catalogue of installed
//  macOS font families.
//
//  This manager is intentionally application-independent.
//  It knows about fonts installed on macOS, not about Pages.
//

import Foundation
import AppKit
import Combine


@MainActor
final class FontLibraryManager: ObservableObject {

    // MARK: - Published Font Catalogue

    @Published
    private(set)
    var families: [String] = []


    // MARK: - Quick Access Fonts

    //
    // These are temporary defaults for development.
    //
    // Later, Settings will allow the user to choose
    // which five font families appear in Zest's
    // quick-access Font control.

    @Published
    var quickAccessFonts: [String] = [
        "Helvetica",
        "Times New Roman",
        "Courier New",
        "Avenir Next",
        "Georgia"
    ]


    // MARK: - Init

    init() {

        reload()
    }


    // MARK: - Reload Installed Fonts

    func reload() {

        let availableFamilies =
            NSFontManager
                .shared
                .availableFontFamilies

        families =
            availableFamilies
                .map {
                    normalizeFontName(
                        $0
                    )
                }
                .filter {
                    !$0.isEmpty
                }
                .uniqued()
                .sorted {
                    $0.localizedCaseInsensitiveCompare(
                        $1
                    )
                    == .orderedAscending
                }

        validateQuickAccessFonts()

        print("")
        print("==========================================")
        print("🍊 ZEST FONT LIBRARY")
        print("==========================================")
        print("")

        print(
            "Installed font families:",
            families.count
        )

        print("")

        print(
            "Quick-access fonts:"
        )

        for (
            index,
            font
        ) in quickAccessFonts.enumerated() {

            let available =
                contains(
                    font
                )

            print(
                "\(index + 1).",
                font,
                available
                    ? "✓"
                    : "⚠️ unavailable"
            )
        }

        print("")
        print("==========================================")
        print("")
    }


    // MARK: - Availability

    func contains(
        _ family: String
    ) -> Bool {

        families.contains {
            fontNamesMatch(
                $0,
                family
            )
        }
    }


    // MARK: - Canonical Family Name

    //
    // Allows Zest to ask for something like:
    //
    //     "helvetica"
    //
    // and receive:
    //
    //     "Helvetica"
    //
    // if that family exists.

    func canonicalFamilyName(
        for requestedName: String
    ) -> String? {

        families.first {
            fontNamesMatch(
                $0,
                requestedName
            )
        }
    }


    // MARK: - Members of Family

    //
    // This will become useful when we build
    // Control 4: Font Weight / Typeface.
    //
    // NSFontManager returns entries describing
    // individual members of a font family.

    func members(
        of family: String
    ) -> [[Any]] {

        NSFontManager
            .shared
            .availableMembers(
                ofFontFamily: family
            )
        ?? []
    }


    // MARK: - Validate Quick Access Fonts

    private func validateQuickAccessFonts() {

        var validated:
            [String] = []

        for requestedFont in quickAccessFonts {

            if let canonical =
                canonicalFamilyName(
                    for: requestedFont
                )
            {
                validated.append(
                    canonical
                )
            }
        }


        // If one of our development defaults doesn't
        // exist on this Mac, fill the empty slot with
        // another installed family.
        //
        // This keeps the quick-access list usable
        // without assuming every Mac has identical
        // third-party fonts.

        if validated.count < 5 {

            for family in families {

                guard
                    validated.count < 5
                else {
                    break
                }

                let alreadyIncluded =
                    validated.contains {
                        fontNamesMatch(
                            $0,
                            family
                        )
                    }

                if !alreadyIncluded {

                    validated.append(
                        family
                    )
                }
            }
        }

        quickAccessFonts =
            Array(
                validated.prefix(
                    5
                )
            )
    }


    // MARK: - Font Name Comparison

    private func fontNamesMatch(
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


    // MARK: - Normalize Font Name

    private func normalizeFontName(
        _ raw: String
    ) -> String {

        var scalars =
            Array(
                raw.unicodeScalars
            )

        while
            let first =
                scalars.first,
            shouldStripEdgeScalar(
                first
            )
        {
            scalars.removeFirst()
        }

        while
            let last =
                scalars.last,
            shouldStripEdgeScalar(
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
            in: .whitespacesAndNewlines
        )
    }


    private func shouldStripEdgeScalar(
        _ scalar: UnicodeScalar
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

        if
            scalar.properties.generalCategory
                == .format
        {
            return true
        }

        return false
    }
}


// MARK: - Unique Strings

private extension Array
where Element == String {

    func uniqued() -> [String] {

        var seen:
            Set<String> = []

        return filter {

            let key =
                $0.folding(
                    options: [
                        .caseInsensitive,
                        .diacriticInsensitive
                    ],
                    locale: .current
                )

            return seen
                .insert(
                    key
                )
                .inserted
        }
    }
}
