//
//  EmojiLibraryManager.swift
//  Zest
//
//  Local Emoji 18 search library.
//
//  The complete Unicode emoji catalogue is loaded from the bundled
//  "Emoji Test.rtf" resource. Zest then builds a searchable,
//  category-aware index entirely in memory.
//

import Foundation
import AppKit
import Combine


// MARK: - Zest Emoji Category

enum ZestEmojiCategory: String, CaseIterable, Identifiable {

    case smileys = "Smileys"
    case people = "People"
    case animals = "Animals"
    case food = "Food"
    case activities = "Activities"
    case travel = "Travel"
    case objects = "Objects"
    case symbols = "Symbols"
    case flags = "Flags"

    var id: String {
        rawValue
    }
}


// MARK: - Emoji Item

struct ZestEmojiItem: Identifiable, Hashable {

    let character: String
    let name: String
    let keywords: [String]
    let category: ZestEmojiCategory

    var id: String {
        character
    }
}


// MARK: - Emoji Library

@MainActor
final class EmojiLibraryManager: ObservableObject {

    // MARK: Published

    @Published private(set)
    var emojis: [ZestEmojiItem] = []


    // MARK: Pins

    private let pinnedCharacters = [
        "😂",
        "❤️",
        "👍",
        "🔥",
        "✨"
    ]


    // MARK: Zest Contextual Vocabulary

    /// These aliases supplement the official Unicode names.
    ///
    /// This is intentionally small and human-oriented. The normal
    /// Unicode name already supplies most useful search terms.
    ///
    /// We can later replace/augment this with CLDR annotations
    /// without changing the panel API.

    private static let aliases: [String: [String]] = [

        // MARK: Reactions

        "😂": [
            "laugh",
            "laughing",
            "funny",
            "lol",
            "lmao",
            "rofl",
            "haha",
            "hahaha",
            "cry laughing",
            "tears"
        ],

        "🤣": [
            "laugh",
            "laughing",
            "funny",
            "lol",
            "lmao",
            "rofl",
            "haha",
            "hahaha"
        ],

        "😆": [
            "laugh",
            "laughing",
            "funny",
            "haha"
        ],

        "😹": [
            "laugh",
            "laughing",
            "funny",
            "cat",
            "lol"
        ],

        "❤️": [
            "love",
            "heart",
            "romance",
            "romantic",
            "valentine"
        ],

        "🥰": [
            "love",
            "loving",
            "romance",
            "romantic",
            "adorable",
            "cute"
        ],

        "😍": [
            "love",
            "loving",
            "crush",
            "beautiful",
            "cute",
            "heart eyes"
        ],

        "😘": [
            "love",
            "kiss",
            "kissing",
            "romance"
        ],

        "😭": [
            "sad",
            "cry",
            "crying",
            "tears",
            "sob"
        ],

        "😢": [
            "sad",
            "cry",
            "crying",
            "tear"
        ],

        "😔": [
            "sad",
            "unhappy",
            "depressed",
            "down"
        ],

        "😡": [
            "angry",
            "mad",
            "rage",
            "furious"
        ],

        "😠": [
            "angry",
            "mad",
            "annoyed"
        ],

        "🤬": [
            "angry",
            "mad",
            "rage",
            "swear",
            "cursing"
        ],

        "🥳": [
            "party",
            "birthday",
            "celebrate",
            "celebration",
            "congratulations"
        ],

        "🎉": [
            "party",
            "birthday",
            "celebrate",
            "celebration",
            "congratulations",
            "confetti"
        ],

        "🎂": [
            "birthday",
            "cake",
            "party",
            "celebrate"
        ],

        "🔥": [
            "fire",
            "hot",
            "lit",
            "awesome",
            "great"
        ],

        "✨": [
            "sparkle",
            "sparkles",
            "magic",
            "shiny",
            "new",
            "special"
        ],

        "👍": [
            "yes",
            "good",
            "great",
            "okay",
            "ok",
            "agree",
            "like",
            "approve"
        ],

        "👎": [
            "no",
            "bad",
            "dislike",
            "disagree"
        ],

        "👏": [
            "clap",
            "applause",
            "congratulations",
            "bravo",
            "good job"
        ],

        "🙏": [
            "please",
            "pray",
            "prayer",
            "thanks",
            "thank you"
        ],


        // MARK: Music

        "🎵": [
            "music",
            "song",
            "note"
        ],

        "🎶": [
            "music",
            "song",
            "songs",
            "notes"
        ],

        "🎼": [
            "music",
            "score",
            "sheet music",
            "notes"
        ],

        "🎹": [
            "music",
            "piano",
            "keyboard",
            "instrument"
        ],

        "🎷": [
            "music",
            "sax",
            "saxophone",
            "jazz",
            "instrument"
        ],

        "🎸": [
            "music",
            "guitar",
            "rock",
            "instrument"
        ],

        "🎺": [
            "music",
            "trumpet",
            "brass",
            "instrument"
        ],

        "🎻": [
            "music",
            "violin",
            "classical",
            "instrument"
        ],

        "🎤": [
            "music",
            "microphone",
            "sing",
            "singing",
            "vocal",
            "karaoke"
        ],

        "🎧": [
            "music",
            "headphones",
            "listen",
            "audio",
            "dj"
        ],

        "💿": [
            "music",
            "disc",
            "cd",
            "album",
            "dj"
        ],


        // MARK: Work / Tech

        "💼": [
            "work",
            "job",
            "office",
            "business"
        ],

        "💻": [
            "work",
            "computer",
            "laptop",
            "coding",
            "programming",
            "developer"
        ],

        "⌨️": [
            "computer",
            "keyboard",
            "typing",
            "work"
        ],

        "🖥️": [
            "computer",
            "desktop",
            "monitor",
            "work"
        ],

        "📱": [
            "phone",
            "iphone",
            "mobile",
            "smartphone"
        ],

        "📧": [
            "email",
            "mail",
            "message",
            "work"
        ],

        "📅": [
            "calendar",
            "date",
            "schedule",
            "appointment",
            "work"
        ],


        // MARK: Money

        "💰": [
            "money",
            "cash",
            "rich",
            "payment"
        ],

        "💵": [
            "money",
            "cash",
            "dollar",
            "payment"
        ],

        "💶": [
            "money",
            "cash",
            "euro",
            "payment"
        ],

        "💳": [
            "money",
            "card",
            "credit",
            "payment"
        ],

        "🤑": [
            "money",
            "rich",
            "cash"
        ],


        // MARK: Travel

        "✈️": [
            "plane",
            "airplane",
            "flight",
            "fly",
            "travel",
            "airport"
        ],

        "🛫": [
            "plane",
            "airplane",
            "flight",
            "departure",
            "travel",
            "airport"
        ],

        "🛬": [
            "plane",
            "airplane",
            "flight",
            "arrival",
            "travel",
            "airport"
        ],

        "🚗": [
            "car",
            "drive",
            "driving",
            "travel",
            "road"
        ],

        "🚆": [
            "train",
            "rail",
            "travel"
        ],

        "🧳": [
            "travel",
            "trip",
            "vacation",
            "holiday",
            "luggage"
        ],

        "🏨": [
            "hotel",
            "travel",
            "vacation",
            "holiday"
        ],

        "🌍": [
            "world",
            "earth",
            "travel",
            "international"
        ],


        // MARK: Food / Drink

        "☕": [
            "coffee",
            "cafe",
            "drink",
            "morning"
        ],

        "🍕": [
            "pizza",
            "food",
            "italian"
        ],

        "🍔": [
            "burger",
            "hamburger",
            "food"
        ],

        "🍰": [
            "cake",
            "dessert",
            "sweet",
            "birthday"
        ],

        "🍷": [
            "wine",
            "drink",
            "glass"
        ],

        "🍺": [
            "beer",
            "drink"
        ],


        // MARK: Animals

        "🐱": [
            "cat",
            "kitty",
            "kitten",
            "pet"
        ],

        "🐈": [
            "cat",
            "kitty",
            "kitten",
            "pet"
        ],

        "🐶": [
            "dog",
            "puppy",
            "pet"
        ],

        "🐕": [
            "dog",
            "puppy",
            "pet"
        ],


        // MARK: Countries

        "🇩🇪": [
            "germany",
            "german",
            "deutschland",
            "de"
        ],

        "🇺🇦": [
            "ukraine",
            "ukrainian",
            "ukraina",
            "ua"
        ],

        "🇬🇧": [
            "uk",
            "britain",
            "british",
            "england",
            "united kingdom"
        ],

        "🇺🇸": [
            "usa",
            "america",
            "american",
            "united states"
        ]
    ]


    // MARK: Suggestions

    private static let defaultSuggestions: [ZestEmojiCategory?: [String]] = [

        nil:
            ["😂", "❤️", "👍", "🔥", "✨"],

        .smileys:
            ["😂", "🤣", "🥰", "😭", "🥳"],

        .people:
            ["👍", "👏", "🙏", "💪", "👋"],

        .animals:
            ["🐶", "🐱", "🐻", "🦊", "🐼"],

        .food:
            ["🍕", "🍔", "🍓", "☕", "🎂"],

        .activities:
            ["⚽", "🏀", "🎮", "🎨", "🎯"],

        .travel:
            ["✈️", "🚗", "🚆", "🧳", "🌍"],

        .objects:
            ["💻", "📱", "🎷", "🎹", "💡"],

        .symbols:
            ["❤️", "🔥", "✨", "💯", "✅"],

        .flags:
            ["🇩🇪", "🇺🇦", "🇬🇧", "🇺🇸", "🇪🇺"]
    ]


    // MARK: Init

    init() {

        loadUnicodeLibrary()
    }


    // MARK: Public API

    var pinnedEmojis: [ZestEmojiItem] {

        items(
            matchingCharacters:
                pinnedCharacters
        )
    }


    func suggestions(
        in category: ZestEmojiCategory?
    ) -> [ZestEmojiItem] {

        let characters =
            Self.defaultSuggestions[category]
            ?? Self.defaultSuggestions[nil]
            ?? []


        return items(
            matchingCharacters:
                characters
        )
    }


    func search(
        query rawQuery: String,
        category: ZestEmojiCategory?
    ) -> [ZestEmojiItem] {

        let query =
            Self.normalize(
                rawQuery
            )


        guard !query.isEmpty else {
            return []
        }


        let queryWords =
            query
                .split(separator: " ")
                .map(String.init)


        let candidates: [ZestEmojiItem]

        if let category {

            candidates =
                emojis.filter {
                    $0.category == category
                }

        } else {

            candidates =
                emojis
        }


        let scored =
            candidates.compactMap {
                item
                -> (
                    item: ZestEmojiItem,
                    score: Int
                )?
                in

                guard let score =
                    score(
                        item,
                        query: query,
                        words: queryWords
                    )
                else {
                    return nil
                }


                return (
                    item,
                    score
                )
            }


        return scored
            .sorted {

                if $0.score
                    != $1.score
                {
                    return
                        $0.score
                        > $1.score
                }


                return
                    $0.item.name
                    .localizedCaseInsensitiveCompare(
                        $1.item.name
                    )
                    == .orderedAscending
            }
            .map(\.item)
    }


    // MARK: Search Scoring

    private func score(
        _ item: ZestEmojiItem,
        query: String,
        words: [String]
    ) -> Int? {

        let name =
            Self.normalize(
                item.name
            )


        let keywords =
            item.keywords.map {
                Self.normalize($0)
            }


        var total = 0


        // -----------------------------------------
        // Whole-query bonuses
        // -----------------------------------------

        if name == query {
            total += 220
        }

        else if name.hasPrefix(query) {
            total += 170
        }

        else if name.contains(query) {
            total += 125
        }


        if keywords.contains(query) {
            total += 190
        }

        else if keywords.contains(
            where: {
                $0.hasPrefix(query)
            }
        ) {
            total += 145
        }

        else if keywords.contains(
            where: {
                $0.contains(query)
            }
        ) {
            total += 105
        }


        // -----------------------------------------
        // Every query word must find something.
        //
        // "red heart" therefore behaves like a
        // real multi-word search rather than an OR.
        // -----------------------------------------

        for word in words {

            var wordScore = 0


            let nameWords =
                name.split(separator: " ")
                    .map(String.init)


            if nameWords.contains(word) {
                wordScore =
                    max(
                        wordScore,
                        90
                    )
            }

            else if nameWords.contains(
                where: {
                    $0.hasPrefix(word)
                }
            ) {
                wordScore =
                    max(
                        wordScore,
                        72
                    )
            }

            else if name.contains(word) {
                wordScore =
                    max(
                        wordScore,
                        55
                    )
            }


            for keyword in keywords {

                if keyword == word {

                    wordScore =
                        max(
                            wordScore,
                            100
                        )

                } else if keyword.hasPrefix(word) {

                    wordScore =
                        max(
                            wordScore,
                            82
                        )

                } else if keyword.contains(word) {

                    wordScore =
                        max(
                            wordScore,
                            62
                        )
                }
            }


            guard wordScore > 0 else {
                return nil
            }


            total += wordScore
        }


        // Prefer the base emoji over a long skin-tone
        // variation when both satisfy the same search.

        if item.name.contains(
            "skin tone"
        ) {
            total -= 18
        }


        return total
    }


    // MARK: Unicode Resource

    private func loadUnicodeLibrary() {

        guard let url =
            Bundle.main.url(
                forResource: "Emoji Test",
                withExtension: "rtf"
            )
        else {

            print(
                "🍊 EMOJI ERROR → Emoji Test.rtf not found in app bundle"
            )

            emojis =
                Self.fallbackLibrary()

            return
        }


        do {

            let attributed =
                try NSAttributedString(
                    url: url,
                    options: [
                        .documentType:
                            NSAttributedString.DocumentType.rtf
                    ],
                    documentAttributes: nil
                )


            let source =
                attributed.string


            let parsed =
                Self.parseUnicodeEmojiTest(
                    source
                )


            guard !parsed.isEmpty else {

                print(
                    "🍊 EMOJI ERROR → Unicode resource parsed zero entries"
                )

                emojis =
                    Self.fallbackLibrary()

                return
            }


            emojis =
                parsed


            print(
                "🍊 EMOJI LIBRARY → \(parsed.count) searchable emoji loaded"
            )

        } catch {

            print(
                "🍊 EMOJI ERROR → \(error.localizedDescription)"
            )


            emojis =
                Self.fallbackLibrary()
        }
    }


    private static func parseUnicodeEmojiTest(
        _ source: String
    ) -> [ZestEmojiItem] {

        var result: [ZestEmojiItem] = []

        var currentCategory:
            ZestEmojiCategory?


        let lines =
            source.components(
                separatedBy: .newlines
            )


        for rawLine in lines {

            let line =
                rawLine.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )


            if line.hasPrefix(
                "# group:"
            ) {

                let group =
                    line
                        .replacingOccurrences(
                            of: "# group:",
                            with: ""
                        )
                        .trimmingCharacters(
                            in: .whitespaces
                        )


                currentCategory =
                    zestCategory(
                        forUnicodeGroup:
                            group
                    )


                continue
            }


            guard
                let category =
                    currentCategory
            else {
                continue
            }


            guard line.contains(
                "; fully-qualified"
            )
            else {
                continue
            }


            guard
                let semicolon =
                    line.firstIndex(
                        of: ";"
                    ),
                let hash =
                    line.firstIndex(
                        of: "#"
                    ),
                hash > semicolon
            else {
                continue
            }


            let codePointText =
                String(
                    line[..<semicolon]
                )
                .trimmingCharacters(
                    in: .whitespaces
                )


            let comment =
                String(
                    line[
                        line.index(
                            after: hash
                        )...
                    ]
                )
                .trimmingCharacters(
                    in: .whitespaces
                )


            guard
                let emoji =
                    emojiString(
                        from:
                            codePointText
                    )
            else {
                continue
            }


            // Unicode comment format:
            //
            // 😀 E1.0 grinning face
            //
            // We don't depend on the rendered emoji
            // token because we already reconstructed it
            // from the code points.

            let name =
                nameFromUnicodeComment(
                    comment
                )


            guard !name.isEmpty else {
                continue
            }


            let keywords =
                searchKeywords(
                    character:
                        emoji,
                    name:
                        name
                )


            result.append(
                ZestEmojiItem(
                    character:
                        emoji,
                    name:
                        name,
                    keywords:
                        keywords,
                    category:
                        category
                )
            )
        }


        // Defensive deduplication.

        var seen:
            Set<String> = []


        return result.filter {

            guard !seen.contains(
                $0.character
            )
            else {
                return false
            }


            seen.insert(
                $0.character
            )


            return true
        }
    }


    private static func emojiString(
        from codePointText: String
    ) -> String? {

        let pieces =
            codePointText
                .split(
                    whereSeparator:
                        \.isWhitespace
                )


        guard !pieces.isEmpty else {
            return nil
        }


        var scalars:
            [UnicodeScalar] = []


        for piece in pieces {

            guard
                let value =
                    UInt32(
                        piece,
                        radix: 16
                    ),
                let scalar =
                    UnicodeScalar(
                        value
                    )
            else {
                return nil
            }


            scalars.append(
                scalar
            )
        }


        return String(
            String.UnicodeScalarView(
                scalars
            )
        )
    }


    private static func nameFromUnicodeComment(
        _ comment: String
    ) -> String {

        // Find the version token such as E0.6,
        // E15.1 or E18.0 and take everything after it.

        let parts =
            comment.split(
                separator: " ",
                omittingEmptySubsequences:
                    true
            )


        guard
            let versionIndex =
                parts.firstIndex(
                    where: {
                        $0.hasPrefix("E")
                        && $0.dropFirst()
                            .contains(".")
                    }
                ),
            parts.indices.contains(
                versionIndex + 1
            )
        else {
            return comment
        }


        return parts[
            (versionIndex + 1)...
        ]
        .joined(
            separator: " "
        )
    }


    private static func zestCategory(
        forUnicodeGroup group: String
    ) -> ZestEmojiCategory? {

        switch group {

        case "Smileys & Emotion":
            return .smileys

        case "People & Body":
            return .people

        case "Animals & Nature":
            return .animals

        case "Food & Drink":
            return .food

        case "Activities":
            return .activities

        case "Travel & Places":
            return .travel

        case "Objects":
            return .objects

        case "Symbols":
            return .symbols

        case "Flags":
            return .flags

        default:
            return nil
        }
    }


    // MARK: Keyword Generation

    private static func searchKeywords(
        character: String,
        name: String
    ) -> [String] {

        var values:
            Set<String> = []


        let normalizedName =
            normalize(
                name
            )


        values.insert(
            normalizedName
        )


        for word in
            normalizedName.split(
                separator: " "
            )
        {

            let clean =
                String(word)
                    .trimmingCharacters(
                        in:
                            CharacterSet
                                .alphanumerics
                                .inverted
                    )


            if clean.count >= 2 {
                values.insert(clean)
            }
        }


        for alias in
            aliases[character]
            ?? []
        {

            values.insert(
                normalize(
                    alias
                )
            )
        }


        return Array(values)
    }


    // MARK: Matching Helpers

    private func items(
        matchingCharacters characters: [String]
    ) -> [ZestEmojiItem] {

        characters.compactMap {
            character in

            emojis.first {
                $0.character
                    == character
            }
        }
    }


    private static func normalize(
        _ text: String
    ) -> String {

        text
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive
                ],
                locale:
                    Locale(
                        identifier:
                            "en_US_POSIX"
                    )
            )
            .lowercased()
            .replacingOccurrences(
                of: "-",
                with: " "
            )
            .replacingOccurrences(
                of: "_",
                with: " "
            )
            .split(
                whereSeparator:
                    \.isWhitespace
            )
            .joined(
                separator: " "
            )
    }


    // MARK: Emergency Fallback

    /// Zest remains usable if the resource accidentally
    /// disappears from the target during development.

    private static func fallbackLibrary()
        -> [ZestEmojiItem]
    {

        let fallback:
            [
                (
                    String,
                    String,
                    ZestEmojiCategory
                )
            ] =
        [
            ("😂", "face with tears of joy", .smileys),
            ("🤣", "rolling on the floor laughing", .smileys),
            ("🥰", "smiling face with hearts", .smileys),
            ("😍", "smiling face with heart-eyes", .smileys),
            ("😭", "loudly crying face", .smileys),

            ("👍", "thumbs up", .people),
            ("👏", "clapping hands", .people),
            ("🙏", "folded hands", .people),
            ("👋", "waving hand", .people),
            ("💪", "flexed biceps", .people),

            ("🐶", "dog face", .animals),
            ("🐱", "cat face", .animals),

            ("🍕", "pizza", .food),
            ("☕", "hot beverage", .food),
            ("🎂", "birthday cake", .food),

            ("⚽", "soccer ball", .activities),

            ("✈️", "airplane", .travel),
            ("🚗", "automobile", .travel),

            ("🎷", "saxophone", .objects),
            ("🎹", "musical keyboard", .objects),
            ("💻", "laptop", .objects),

            ("❤️", "red heart", .symbols),
            ("🔥", "fire", .symbols),
            ("✨", "sparkles", .symbols),

            ("🇩🇪", "flag: Germany", .flags),
            ("🇺🇦", "flag: Ukraine", .flags)
        ]


        return fallback.map {
            character,
            name,
            category in

            ZestEmojiItem(
                character:
                    character,
                name:
                    name,
                keywords:
                    searchKeywords(
                        character:
                            character,
                        name:
                            name
                    ),
                category:
                    category
            )
        }
    }
}
