//
//  SymbolLibraryManager.swift
//  Zest
//
//  Local searchable symbol library for Zest.
//

import Foundation
import Combine


// MARK: - Category

enum ZestSymbolCategory:
    String,
    CaseIterable,
    Identifiable {

    case pointers = "Pointers"
    case arrows = "Arrows"
    case math = "Math"
    case currency = "Currency"
    case typography = "Typography"
    case shapes = "Shapes"
    case music = "Music"
    case technical = "Technical"


    var id: String {
        rawValue
    }
}


// MARK: - Item

struct ZestSymbolItem:
    Identifiable,
    Hashable {

    let character: String
    let name: String
    let keywords: [String]
    let category: ZestSymbolCategory


    var id: String {
        character
    }
}


// MARK: - Library

@MainActor
final class SymbolLibraryManager:
    ObservableObject {

    @Published
    private(set)
    var symbols: [ZestSymbolItem] = []


    // Temporary pins.
    //
    // Settings can own these later.

    private let pinnedCharacters = [
        "→",
        "©",
        "°",
        "€",
        "≈"
    ]


    init() {

        symbols =
            Self.makeLibrary()
    }


    // MARK: - Pins

    var pinnedSymbols:
        [ZestSymbolItem] {

        items(
            matching:
                pinnedCharacters
        )
    }


    // MARK: - Suggestions

    func suggestions(
        in category:
            ZestSymbolCategory?
    ) -> [ZestSymbolItem] {

        let preferred:
            [String]


        switch category {

        case .pointers:

            preferred = [
                "☞",
                "☜",
                "☝",
                "☟",
                "⌖"
            ]


        case .arrows:

            preferred = [
                "→",
                "←",
                "↑",
                "↓",
                "↔"
            ]


        case .math:

            preferred = [
                "±",
                "×",
                "÷",
                "≈",
                "∞"
            ]


        case .currency:

            preferred = [
                "€",
                "$",
                "£",
                "¥",
                "₴"
            ]


        case .typography:

            preferred = [
                "©",
                "®",
                "™",
                "§",
                "¶"
            ]


        case .shapes:

            preferred = [
                "●",
                "○",
                "■",
                "□",
                "◆"
            ]


        case .music:

            preferred = [
                "♪",
                "♫",
                "♬",
                "♭",
                "♯"
            ]


        case .technical:

            preferred = [
                "⌘",
                "⌥",
                "⇧",
                "⌃",
                "⌫"
            ]


        case nil:

            preferred = [
                "→",
                "©",
                "°",
                "€",
                "≈"
            ]
        }


        return items(
            matching:
                preferred
        )
    }


    // MARK: - Search

    func search(
        query rawQuery: String,
        category:
            ZestSymbolCategory?
    ) -> [ZestSymbolItem] {

        let query =
            Self.normalize(
                rawQuery
            )


        guard !query.isEmpty else {
            return []
        }


        let words =
            query
                .split(separator: " ")
                .map(String.init)


        let candidates =
            category == nil
            ? symbols
            : symbols.filter {
                $0.category
                    == category
            }


        return candidates
            .compactMap {
                item
                -> (
                    ZestSymbolItem,
                    Int
                )?
                in

                guard let score =
                    Self.score(
                        item,
                        query:
                            query,
                        words:
                            words
                    )
                else {
                    return nil
                }


                return (
                    item,
                    score
                )
            }
            .sorted {

                if $0.1 != $1.1 {
                    return $0.1 > $1.1
                }


                return
                    $0.0.name
                    .localizedCaseInsensitiveCompare(
                        $1.0.name
                    )
                    == .orderedAscending
            }
            .map(\.0)
    }


    // MARK: - Ranking

    private static func score(
        _ item:
            ZestSymbolItem,
        query: String,
        words: [String]
    ) -> Int? {

        let name =
            normalize(
                item.name
            )


        let keywords =
            item.keywords.map(
                normalize
            )


        // Searching for the literal symbol itself.

        if item.character == query {
            return 1000
        }


        var score = 0


        if name == query {
            score += 220

        } else if name.hasPrefix(
            query
        ) {
            score += 170

        } else if name.contains(
            query
        ) {
            score += 125
        }


        if keywords.contains(
            query
        ) {
            score += 200

        } else if keywords.contains(
            where: {
                $0.hasPrefix(query)
            }
        ) {
            score += 150

        } else if keywords.contains(
            where: {
                $0.contains(query)
            }
        ) {
            score += 105
        }


        for word in words {

            var wordScore = 0


            if name.contains(
                word
            ) {
                wordScore =
                    max(
                        wordScore,
                        60
                    )
            }


            for keyword in keywords {

                if keyword == word {

                    wordScore =
                        max(
                            wordScore,
                            100
                        )

                } else if keyword.hasPrefix(
                    word
                ) {

                    wordScore =
                        max(
                            wordScore,
                            80
                        )

                } else if keyword.contains(
                    word
                ) {

                    wordScore =
                        max(
                            wordScore,
                            60
                        )
                }
            }


            guard wordScore > 0 else {
                return nil
            }


            score += wordScore
        }


        return score
    }


    // MARK: - Helpers

    private func items(
        matching characters:
            [String]
    ) -> [ZestSymbolItem] {

        characters.compactMap {
            character in

            symbols.first {
                $0.character
                    == character
            }
        }
    }


    private static func normalize(
        _ value: String
    ) -> String {

        value
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


    // MARK: - Library

    private static func makeLibrary()
        -> [ZestSymbolItem]
    {

        func item(
            _ character: String,
            _ name: String,
            _ category:
                ZestSymbolCategory,
            _ keywords:
                [String]
        ) -> ZestSymbolItem {

            ZestSymbolItem(
                character:
                    character,
                name:
                    name,
                keywords:
                    keywords,
                category:
                    category
            )
        }


        return [

            // =====================================
            // POINTERS
            // =====================================

            item(
                "☞",
                "Right Pointing Hand",
                .pointers,
                [
                    "right",
                    "pointer",
                    "point",
                    "hand",
                    "direction"
                ]
            ),

            item(
                "☜",
                "Left Pointing Hand",
                .pointers,
                [
                    "left",
                    "pointer",
                    "point",
                    "hand",
                    "direction"
                ]
            ),

            item(
                "☝",
                "Up Pointing Hand",
                .pointers,
                [
                    "up",
                    "pointer",
                    "point",
                    "hand"
                ]
            ),

            item(
                "☟",
                "Down Pointing Hand",
                .pointers,
                [
                    "down",
                    "pointer",
                    "point",
                    "hand"
                ]
            ),

            item(
                "⌖",
                "Position Indicator",
                .pointers,
                [
                    "position",
                    "target",
                    "location",
                    "crosshair",
                    "pointer"
                ]
            ),

            item(
                "※",
                "Reference Mark",
                .pointers,
                [
                    "reference",
                    "note",
                    "marker",
                    "attention"
                ]
            ),

            item(
                "⁂",
                "Asterism",
                .pointers,
                [
                    "asterism",
                    "separator",
                    "section",
                    "mark"
                ]
            ),

            item(
                "⁕",
                "Flower Punctuation Mark",
                .pointers,
                [
                    "flower",
                    "bullet",
                    "mark",
                    "pointer"
                ]
            ),


            // =====================================
            // ARROWS
            // =====================================

            item(
                "→",
                "Right Arrow",
                .arrows,
                [
                    "right",
                    "arrow",
                    "next",
                    "forward"
                ]
            ),

            item(
                "←",
                "Left Arrow",
                .arrows,
                [
                    "left",
                    "arrow",
                    "back",
                    "previous"
                ]
            ),

            item(
                "↑",
                "Up Arrow",
                .arrows,
                [
                    "up",
                    "arrow",
                    "above"
                ]
            ),

            item(
                "↓",
                "Down Arrow",
                .arrows,
                [
                    "down",
                    "arrow",
                    "below"
                ]
            ),

            item(
                "↔",
                "Left Right Arrow",
                .arrows,
                [
                    "left",
                    "right",
                    "arrow",
                    "horizontal",
                    "both"
                ]
            ),

            item(
                "↕",
                "Up Down Arrow",
                .arrows,
                [
                    "up",
                    "down",
                    "arrow",
                    "vertical",
                    "both"
                ]
            ),

            item(
                "↗",
                "Up Right Arrow",
                .arrows,
                [
                    "up",
                    "right",
                    "arrow",
                    "northeast",
                    "diagonal"
                ]
            ),

            item(
                "↘",
                "Down Right Arrow",
                .arrows,
                [
                    "down",
                    "right",
                    "arrow",
                    "southeast",
                    "diagonal"
                ]
            ),

            item(
                "↙",
                "Down Left Arrow",
                .arrows,
                [
                    "down",
                    "left",
                    "arrow",
                    "southwest",
                    "diagonal"
                ]
            ),

            item(
                "↖",
                "Up Left Arrow",
                .arrows,
                [
                    "up",
                    "left",
                    "arrow",
                    "northwest",
                    "diagonal"
                ]
            ),

            item(
                "⇒",
                "Right Double Arrow",
                .arrows,
                [
                    "right",
                    "double",
                    "arrow",
                    "implies"
                ]
            ),

            item(
                "⇐",
                "Left Double Arrow",
                .arrows,
                [
                    "left",
                    "double",
                    "arrow"
                ]
            ),

            item(
                "⇔",
                "Left Right Double Arrow",
                .arrows,
                [
                    "left",
                    "right",
                    "double",
                    "arrow",
                    "equivalent"
                ]
            ),

            item(
                "➜",
                "Heavy Round Tipped Right Arrow",
                .arrows,
                [
                    "right",
                    "arrow",
                    "forward",
                    "heavy"
                ]
            ),

            item(
                "➤",
                "Arrowhead",
                .arrows,
                [
                    "right",
                    "arrow",
                    "arrowhead",
                    "pointer"
                ]
            ),

            item(
                "↩",
                "Return Arrow",
                .arrows,
                [
                    "return",
                    "enter",
                    "back",
                    "arrow"
                ]
            ),

            item(
                "↪",
                "Right Hook Arrow",
                .arrows,
                [
                    "right",
                    "hook",
                    "arrow",
                    "return"
                ]
            ),

            item(
                "↻",
                "Clockwise Arrow",
                .arrows,
                [
                    "clockwise",
                    "refresh",
                    "reload",
                    "rotate",
                    "arrow"
                ]
            ),

            item(
                "↺",
                "Counterclockwise Arrow",
                .arrows,
                [
                    "counterclockwise",
                    "undo",
                    "rotate",
                    "arrow"
                ]
            ),


            // =====================================
            // MATH
            // =====================================

            item(
                "+",
                "Plus",
                .math,
                [
                    "plus",
                    "add",
                    "addition"
                ]
            ),

            item(
                "−",
                "Minus",
                .math,
                [
                    "minus",
                    "subtract",
                    "subtraction"
                ]
            ),

            item(
                "±",
                "Plus Minus",
                .math,
                [
                    "plus",
                    "minus",
                    "plus minus"
                ]
            ),

            item(
                "×",
                "Multiplication",
                .math,
                [
                    "multiply",
                    "multiplication",
                    "times"
                ]
            ),

            item(
                "÷",
                "Division",
                .math,
                [
                    "divide",
                    "division"
                ]
            ),

            item(
                "∕",
                "Division Slash",
                .math,
                [
                    "divide",
                    "division",
                    "slash"
                ]
            ),

            item(
                "=",
                "Equals",
                .math,
                [
                    "equals",
                    "equal",
                    "same"
                ]
            ),

            item(
                "≠",
                "Not Equal",
                .math,
                [
                    "not equal",
                    "unequal",
                    "different"
                ]
            ),

            item(
                "≈",
                "Approximately Equal",
                .math,
                [
                    "approximately",
                    "approx",
                    "roughly",
                    "almost",
                    "equal"
                ]
            ),

            item(
                "≃",
                "Asymptotically Equal",
                .math,
                [
                    "approximately",
                    "roughly",
                    "equal"
                ]
            ),

            item(
                "≡",
                "Identical To",
                .math,
                [
                    "identical",
                    "equivalent",
                    "equal"
                ]
            ),

            item(
                "<",
                "Less Than",
                .math,
                [
                    "less",
                    "less than",
                    "smaller"
                ]
            ),

            item(
                ">",
                "Greater Than",
                .math,
                [
                    "greater",
                    "greater than",
                    "bigger"
                ]
            ),

            item(
                "≤",
                "Less Than or Equal",
                .math,
                [
                    "less",
                    "equal",
                    "less than equal"
                ]
            ),

            item(
                "≥",
                "Greater Than or Equal",
                .math,
                [
                    "greater",
                    "equal",
                    "greater than equal"
                ]
            ),

            item(
                "∞",
                "Infinity",
                .math,
                [
                    "infinity",
                    "infinite",
                    "forever"
                ]
            ),

            item(
                "√",
                "Square Root",
                .math,
                [
                    "root",
                    "square root",
                    "sqrt"
                ]
            ),

            item(
                "∑",
                "Summation",
                .math,
                [
                    "sum",
                    "summation",
                    "sigma"
                ]
            ),

            item(
                "∏",
                "Product",
                .math,
                [
                    "product",
                    "pi",
                    "multiply"
                ]
            ),

            item(
                "∫",
                "Integral",
                .math,
                [
                    "integral",
                    "calculus"
                ]
            ),

            item(
                "∂",
                "Partial Differential",
                .math,
                [
                    "partial",
                    "differential",
                    "derivative"
                ]
            ),

            item(
                "∆",
                "Increment",
                .math,
                [
                    "delta",
                    "difference",
                    "change",
                    "triangle"
                ]
            ),

            item(
                "π",
                "Pi",
                .math,
                [
                    "pi",
                    "circle",
                    "math"
                ]
            ),

            item(
                "∴",
                "Therefore",
                .math,
                [
                    "therefore",
                    "thus",
                    "logic"
                ]
            ),

            item(
                "∵",
                "Because",
                .math,
                [
                    "because",
                    "logic"
                ]
            ),

            item(
                "∝",
                "Proportional To",
                .math,
                [
                    "proportional",
                    "proportion"
                ]
            ),


            // =====================================
            // CURRENCY
            // =====================================

            item(
                "$",
                "Dollar",
                .currency,
                [
                    "dollar",
                    "usd",
                    "money",
                    "currency"
                ]
            ),

            item(
                "€",
                "Euro",
                .currency,
                [
                    "euro",
                    "eur",
                    "money",
                    "currency"
                ]
            ),

            item(
                "£",
                "Pound",
                .currency,
                [
                    "pound",
                    "sterling",
                    "gbp",
                    "money",
                    "currency"
                ]
            ),

            item(
                "¥",
                "Yen",
                .currency,
                [
                    "yen",
                    "yuan",
                    "jpy",
                    "cny",
                    "money",
                    "currency"
                ]
            ),

            item(
                "₴",
                "Hryvnia",
                .currency,
                [
                    "hryvnia",
                    "uah",
                    "ukraine",
                    "ukrainian",
                    "money",
                    "currency"
                ]
            ),

            item(
                "₽",
                "Ruble",
                .currency,
                [
                    "ruble",
                    "rouble",
                    "rub",
                    "money",
                    "currency"
                ]
            ),

            item(
                "₿",
                "Bitcoin",
                .currency,
                [
                    "bitcoin",
                    "btc",
                    "crypto",
                    "currency"
                ]
            ),

            item(
                "₩",
                "Won",
                .currency,
                [
                    "won",
                    "krw",
                    "korea",
                    "money"
                ]
            ),

            item(
                "₹",
                "Rupee",
                .currency,
                [
                    "rupee",
                    "inr",
                    "india",
                    "money"
                ]
            ),

            item(
                "¢",
                "Cent",
                .currency,
                [
                    "cent",
                    "cents",
                    "money"
                ]
            ),

            item(
                "¤",
                "Currency Sign",
                .currency,
                [
                    "currency",
                    "money",
                    "generic"
                ]
            ),


            // =====================================
            // TYPOGRAPHY
            // =====================================

            item(
                "©",
                "Copyright",
                .typography,
                [
                    "copyright",
                    "rights",
                    "legal"
                ]
            ),

            item(
                "®",
                "Registered",
                .typography,
                [
                    "registered",
                    "trademark",
                    "brand"
                ]
            ),

            item(
                "™",
                "Trademark",
                .typography,
                [
                    "trademark",
                    "tm",
                    "brand"
                ]
            ),

            item(
                "°",
                "Degree",
                .typography,
                [
                    "degree",
                    "degrees",
                    "temperature",
                    "angle"
                ]
            ),

            item(
                "§",
                "Section",
                .typography,
                [
                    "section",
                    "paragraph",
                    "legal",
                    "law"
                ]
            ),

            item(
                "¶",
                "Pilcrow",
                .typography,
                [
                    "paragraph",
                    "pilcrow",
                    "formatting"
                ]
            ),

            item(
                "†",
                "Dagger",
                .typography,
                [
                    "dagger",
                    "footnote",
                    "reference"
                ]
            ),

            item(
                "‡",
                "Double Dagger",
                .typography,
                [
                    "double dagger",
                    "footnote",
                    "reference"
                ]
            ),

            item(
                "•",
                "Bullet",
                .typography,
                [
                    "bullet",
                    "list",
                    "dot"
                ]
            ),

            item(
                "·",
                "Middle Dot",
                .typography,
                [
                    "middle dot",
                    "dot",
                    "separator"
                ]
            ),

            item(
                "…",
                "Ellipsis",
                .typography,
                [
                    "ellipsis",
                    "dots",
                    "three dots"
                ]
            ),

            item(
                "–",
                "En Dash",
                .typography,
                [
                    "dash",
                    "en dash",
                    "range"
                ]
            ),

            item(
                "—",
                "Em Dash",
                .typography,
                [
                    "dash",
                    "em dash",
                    "long dash"
                ]
            ),

            item(
                "«",
                "Left Guillemets",
                .typography,
                [
                    "quote",
                    "quotation",
                    "guillemets",
                    "left"
                ]
            ),

            item(
                "»",
                "Right Guillemets",
                .typography,
                [
                    "quote",
                    "quotation",
                    "guillemets",
                    "right"
                ]
            ),

            item(
                "„",
                "Low Double Quote",
                .typography,
                [
                    "quote",
                    "quotation",
                    "german"
                ]
            ),

            item(
                "“",
                "Left Double Quote",
                .typography,
                [
                    "quote",
                    "quotation",
                    "left"
                ]
            ),

            item(
                "”",
                "Right Double Quote",
                .typography,
                [
                    "quote",
                    "quotation",
                    "right"
                ]
            ),

            item(
                "′",
                "Prime",
                .typography,
                [
                    "prime",
                    "minutes",
                    "feet"
                ]
            ),

            item(
                "″",
                "Double Prime",
                .typography,
                [
                    "double prime",
                    "seconds",
                    "inches"
                ]
            ),


            // =====================================
            // SHAPES
            // =====================================

            item(
                "●",
                "Black Circle",
                .shapes,
                [
                    "circle",
                    "round",
                    "filled",
                    "dot"
                ]
            ),

            item(
                "○",
                "White Circle",
                .shapes,
                [
                    "circle",
                    "round",
                    "empty",
                    "outline"
                ]
            ),

            item(
                "◉",
                "Fisheye",
                .shapes,
                [
                    "circle",
                    "target",
                    "dot",
                    "bullseye"
                ]
            ),

            item(
                "◎",
                "Bullseye",
                .shapes,
                [
                    "circle",
                    "target",
                    "bullseye"
                ]
            ),

            item(
                "■",
                "Black Square",
                .shapes,
                [
                    "square",
                    "filled",
                    "box"
                ]
            ),

            item(
                "□",
                "White Square",
                .shapes,
                [
                    "square",
                    "empty",
                    "outline",
                    "box"
                ]
            ),

            item(
                "◆",
                "Black Diamond",
                .shapes,
                [
                    "diamond",
                    "filled",
                    "shape"
                ]
            ),

            item(
                "◇",
                "White Diamond",
                .shapes,
                [
                    "diamond",
                    "empty",
                    "outline"
                ]
            ),

            item(
                "▲",
                "Up Triangle",
                .shapes,
                [
                    "triangle",
                    "up",
                    "filled"
                ]
            ),

            item(
                "△",
                "White Up Triangle",
                .shapes,
                [
                    "triangle",
                    "up",
                    "outline"
                ]
            ),

            item(
                "▼",
                "Down Triangle",
                .shapes,
                [
                    "triangle",
                    "down",
                    "filled"
                ]
            ),

            item(
                "▽",
                "White Down Triangle",
                .shapes,
                [
                    "triangle",
                    "down",
                    "outline"
                ]
            ),

            item(
                "★",
                "Black Star",
                .shapes,
                [
                    "star",
                    "favorite",
                    "filled"
                ]
            ),

            item(
                "☆",
                "White Star",
                .shapes,
                [
                    "star",
                    "favorite",
                    "outline"
                ]
            ),

            item(
                "♥",
                "Heart",
                .shapes,
                [
                    "heart",
                    "love",
                    "shape"
                ]
            ),

            item(
                "♦",
                "Diamond Suit",
                .shapes,
                [
                    "diamond",
                    "cards",
                    "suit"
                ]
            ),

            item(
                "♣",
                "Club Suit",
                .shapes,
                [
                    "club",
                    "cards",
                    "suit"
                ]
            ),

            item(
                "♠",
                "Spade Suit",
                .shapes,
                [
                    "spade",
                    "cards",
                    "suit"
                ]
            ),


            // =====================================
            // MUSIC
            // =====================================

            item(
                "♪",
                "Eighth Note",
                .music,
                [
                    "music",
                    "note",
                    "eighth",
                    "song"
                ]
            ),

            item(
                "♫",
                "Beamed Eighth Notes",
                .music,
                [
                    "music",
                    "notes",
                    "song",
                    "melody"
                ]
            ),

            item(
                "♬",
                "Beamed Sixteenth Notes",
                .music,
                [
                    "music",
                    "notes",
                    "song",
                    "melody"
                ]
            ),

            item(
                "♩",
                "Quarter Note",
                .music,
                [
                    "music",
                    "note",
                    "quarter"
                ]
            ),

            item(
                "♭",
                "Flat",
                .music,
                [
                    "music",
                    "flat",
                    "accidental"
                ]
            ),

            item(
                "♯",
                "Sharp",
                .music,
                [
                    "music",
                    "sharp",
                    "accidental"
                ]
            ),

            item(
                "♮",
                "Natural",
                .music,
                [
                    "music",
                    "natural",
                    "accidental"
                ]
            ),

            item(
                "𝄞",
                "Treble Clef",
                .music,
                [
                    "music",
                    "treble",
                    "clef",
                    "g clef"
                ]
            ),

            item(
                "𝄢",
                "Bass Clef",
                .music,
                [
                    "music",
                    "bass",
                    "clef",
                    "f clef"
                ]
            ),


            // =====================================
            // TECHNICAL
            // =====================================

            item(
                "⌘",
                "Command",
                .technical,
                [
                    "command",
                    "cmd",
                    "mac",
                    "keyboard",
                    "shortcut"
                ]
            ),

            item(
                "⌥",
                "Option",
                .technical,
                [
                    "option",
                    "alt",
                    "mac",
                    "keyboard",
                    "shortcut"
                ]
            ),

            item(
                "⇧",
                "Shift",
                .technical,
                [
                    "shift",
                    "keyboard",
                    "shortcut"
                ]
            ),

            item(
                "⌃",
                "Control",
                .technical,
                [
                    "control",
                    "ctrl",
                    "keyboard",
                    "shortcut"
                ]
            ),

            item(
                "⌫",
                "Delete",
                .technical,
                [
                    "delete",
                    "backspace",
                    "keyboard"
                ]
            ),

            item(
                "⌦",
                "Forward Delete",
                .technical,
                [
                    "delete",
                    "forward delete",
                    "keyboard"
                ]
            ),

            item(
                "⎋",
                "Escape",
                .technical,
                [
                    "escape",
                    "esc",
                    "keyboard"
                ]
            ),

            item(
                "↵",
                "Return",
                .technical,
                [
                    "return",
                    "enter",
                    "keyboard"
                ]
            ),

            item(
                "⇥",
                "Tab",
                .technical,
                [
                    "tab",
                    "keyboard",
                    "next"
                ]
            ),

            item(
                "⇤",
                "Back Tab",
                .technical,
                [
                    "tab",
                    "back",
                    "keyboard"
                ]
            ),

            item(
                "⌧",
                "Clear",
                .technical,
                [
                    "clear",
                    "delete",
                    "keyboard"
                ]
            ),

            item(
                "⏎",
                "Return Symbol",
                .technical,
                [
                    "return",
                    "enter",
                    "keyboard"
                ]
            ),

            item(
                "⌂",
                "Home",
                .technical,
                [
                    "home",
                    "keyboard",
                    "navigation"
                ]
            ),

            item(
                "⌗",
                "Viewdata Square",
                .technical,
                [
                    "technical",
                    "hash",
                    "grid"
                ]
            )
        ]
    }
}
