//
//  ZestEmojiPanel.swift
//  Zest
//
//  Emoji browser for Control 5.
//

import SwiftUI


struct ZestEmojiPanel: View {

    @ObservedObject
    var emojiLibraryManager:
        EmojiLibraryManager
    
    @ObservedObject var clipboardManager: ClipboardHistoryManager

    let accentColor: Color


    @State private var query = ""

    @State private var selectedCategory:
        ZestEmojiCategory?

    @State private var hoveredEmoji:
        String?

    @State private var hoveredCategory:
        ZestEmojiCategory?

    @FocusState
    private var searchFocused: Bool

    @State
    private var textInserter:
        ZestTextInserter?

    private let panelWidth:
        CGFloat = 360

    private let tileHeight:
        CGFloat = 57

    private let tileSpacing:
        CGFloat = 7


    private var columns:
        [GridItem] {

        Array(
            repeating:
                GridItem(
                    .flexible(),
                    spacing: tileSpacing
                ),
            count: 5
        )
    }


    // MARK: - Search Results

    private var searchResults:
        [ZestEmojiItem] {

        if !hasSearchText,
           let selectedCategory {

            return emojiLibraryManager
                .emojis
                .filter {
                    $0.category
                        == selectedCategory
                }
        }


        return emojiLibraryManager.search(
            query:
                query,
            category:
                selectedCategory
        )
    }


    private var suggestions:
        [ZestEmojiItem] {

        emojiLibraryManager.suggestions(
            in: selectedCategory
        )
    }


    private var hasSearchText:
        Bool {

        !query
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty
    }
    
    private var shouldShowResults:
        Bool {

        hasSearchText
        || selectedCategory != nil
    }


    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 11
        ) {

            searchField

            categoryStrip


            if shouldShowResults {

                searchGrid
                    .transition(
                        .opacity
                            .combined(
                                with:
                                    .move(
                                        edge: .top
                                    )
                            )
                    )
            }


            suggestionSection

            pinnedSection
        }
        .padding(13)
        .frame(
            width: panelWidth
        )
        .background {
            glassBody
        }
        .shadow(
            color:
                Color.black.opacity(0.20),
            radius: 15,
            x: 0,
            y: 8
        )
        .shadow(
            color:
                accentColor.opacity(0.07),
            radius: 10,
            x: 0,
            y: 4
        )
        .animation(
            .spring(
                response: 0.18,
                dampingFraction: 0.88
            ),
            value: shouldShowResults
        )
        .animation(
            .spring(
                response: 0.18,
                dampingFraction: 0.88
            ),
            value: selectedCategory
        )
        .onAppear {

            if textInserter == nil {

                textInserter =
                    ZestTextInserter(
                        clipboardManager:
                            clipboardManager
                    )
            }
        }
    }


    // MARK: - Search Field

    private var searchField: some View {

        HStack(
            spacing: 7
        ) {

            Image(
                systemName:
                    "magnifyingglass"
            )
            .font(
                .system(
                    size: 11,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                Color.secondary.opacity(0.72)
            )


            if let selectedCategory {

                categoryToken(
                    selectedCategory
                )
            }


            TextField(
                selectedCategory == nil
                    ? "Search emojis..."
                    : "Search...",
                text: $query
            )
            .textFieldStyle(
                .plain
            )
            .font(
                .system(
                    size: 12,
                    weight: .medium
                )
            )
            .focused(
                $searchFocused
            )
            .simultaneousGesture(TapGesture().onEnded {
                // The runtime panel is normally non-activating so the editor keeps
                // its caret. Search is the explicit inspector-style exception:
                // make Zest key only when the user deliberately enters text.
                NotificationCenter.default.post(
                    name: .zestRuntimeKeyboardFocusRequested,
                    object: nil
                )
                DispatchQueue.main.async { searchFocused = true }
            })


            Spacer(
                minLength: 2
            )


            if hasSearchText
                || selectedCategory != nil {

                Button {

                    clearEverything()

                } label: {

                    Image(
                        systemName:
                            "xmark.circle.fill"
                    )
                    .font(
                        .system(
                            size: 12,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        Color.secondary.opacity(0.68)
                    )
                    .contentShape(
                        Rectangle()
                    )
                }
                .buttonStyle(
                    .plain
                )
                .focusable(false)
                .help(
                    "Clear search"
                )
            }
        }
        .padding(
            .leading,
            10
        )
        .padding(
            .trailing,
            8
        )
        .frame(
            height: 32
        )
        .background {

            RoundedRectangle(
                cornerRadius: 9,
                style: .continuous
            )
            .fill(
                Color.primary.opacity(0.035)
            )
        }
        .overlay {

            RoundedRectangle(
                cornerRadius: 9,
                style: .continuous
            )
            .stroke(
                searchFocused
                    ? accentColor.opacity(0.55)
                    : Color.white.opacity(0.22),
                lineWidth:
                    searchFocused
                        ? 1.0
                        : 0.75
            )
        }
        .contentShape(
            RoundedRectangle(
                cornerRadius: 9,
                style: .continuous
            )
        )
        .onTapGesture {
            NotificationCenter.default.post(
                name: .zestRuntimeKeyboardFocusRequested,
                object: nil
            )
            DispatchQueue.main.async { searchFocused = true }
        }
    }


    // MARK: - Category Token Inside Search

    private func categoryToken(
        _ category: ZestEmojiCategory
    ) -> some View {

        HStack(
            spacing: 4
        ) {

            Text(
                category.rawValue
            )
            .font(
                .system(
                    size: 9,
                    weight: .semibold
                )
            )


            Button {

                clearCategory()

            } label: {

                Image(
                    systemName:
                        "xmark"
                )
                .font(
                    .system(
                        size: 7,
                        weight: .bold
                    )
                )
            }
            .buttonStyle(
                .plain
            )
            .focusable(false)
        }
        .foregroundStyle(
            Color.primary.opacity(0.78)
        )
        .padding(
            .horizontal,
            7
        )
        .frame(
            height: 21
        )
        .background {

            Capsule()
                .fill(
                    Color.primary.opacity(0.065)
                )
        }
        .overlay {

            Capsule()
                .stroke(
                    Color.white.opacity(0.20),
                    lineWidth: 0.7
                )
        }
    }


    // MARK: - Categories

    private var categoryStrip:
        some View {

        ScrollView(
            .horizontal,
            showsIndicators: false
        ) {

            HStack(
                spacing: 6
            ) {

                ForEach(
                    ZestEmojiCategory.allCases
                ) { category in

                    categoryChip(
                        category
                    )
                }
            }
        }
    }


    private func categoryChip(
        _ category: ZestEmojiCategory
    ) -> some View {

        let selected =
            selectedCategory == category

        let hovered =
            hoveredCategory == category


        return Button {

            withAnimation(
                .spring(
                    response: 0.17,
                    dampingFraction: 0.88
                )
            ) {

                if selected {

                    selectedCategory = nil

                } else {

                    selectedCategory =
                        category
                }
            }


            searchFocused = true

        } label: {

            HStack(
                spacing: 5
            ) {

                Text(
                    category.rawValue
                )
                .font(
                    .system(
                        size: 9,
                        weight:
                            selected
                            ? .semibold
                            : .medium
                    )
                )


                if selected {

                    Image(
                        systemName:
                            "xmark"
                    )
                    .font(
                        .system(
                            size: 6.5,
                            weight: .bold
                        )
                    )
                }
            }
            .foregroundStyle(
                Color.primary.opacity(
                    selected
                        ? 0.88
                        : 0.72
                )
            )
            .padding(
                .horizontal,
                9
            )
            .frame(
                height: 24
            )
            .background {

                Capsule()
                    .fill(
                        Color.primary.opacity(
                            selected
                                ? 0.085
                                : hovered
                                    ? 0.060
                                    : 0.035
                        )
                    )
            }
            .overlay {

                Capsule()
                    .stroke(
                        Color.white.opacity(
                            selected
                                ? 0.26
                                : 0.17
                        ),
                        lineWidth: 0.7
                    )
            }
        }
        .buttonStyle(
            .plain
        )
        .focusable(false)
        .onHover { hovering in

            hoveredCategory =
                hovering
                ? category
                : nil
        }
    }


    // MARK: - Search Grid

    private var searchGrid:
        some View {

        VStack(
            alignment: .leading,
            spacing: 7
        ) {

            sectionHeader(
                selectedCategory == nil
                    ? "RESULTS"
                    : "\(selectedCategory!.rawValue.uppercased()) RESULTS"
            )


            if searchResults.isEmpty {

                HStack {

                    Spacer()

                    VStack(
                        spacing: 5
                    ) {

                        Image(
                            systemName:
                                "magnifyingglass"
                        )
                        .font(
                            .system(
                                size: 14,
                                weight: .medium
                            )
                        )


                        Text(
                            "No emojis found"
                        )
                        .font(
                            .system(
                                size: 10,
                                weight: .medium
                            )
                        )
                    }
                    .foregroundStyle(
                        Color.secondary.opacity(0.62)
                    )

                    Spacer()
                }
                .frame(
                    height: 76
                )
                .background {

                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                    .fill(
                        Color.primary.opacity(0.030)
                    )
                }
                .overlay {

                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                    .stroke(
                        Color.white.opacity(0.16),
                        lineWidth: 0.7
                    )
                }

            } else {

                ScrollView(
                    .vertical,
                    showsIndicators: true
                ) {

                    LazyVGrid(
                        columns:
                            columns,
                        spacing:
                            tileSpacing
                    ) {

                        ForEach(
                            searchResults
                        ) { emoji in

                            emojiTile(
                                emoji
                            )
                        }
                    }
                    .padding(7)
                }
                .frame(
                    height: 185
                )
                .background {

                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                    .fill(
                        Color.primary.opacity(0.030)
                    )
                }
                .overlay {

                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                    .stroke(
                        Color.white.opacity(0.16),
                        lineWidth: 0.7
                    )
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )
            }
        }
    }


    // MARK: - Suggestions

    private var suggestionSection:
        some View {

        VStack(
            alignment: .leading,
            spacing: 7
        ) {

            sectionHeader(
                selectedCategory == nil
                    ? "SUGGESTED"
                    : "SUGGESTED IN \(selectedCategory!.rawValue.uppercased())"
            )


            LazyVGrid(
                columns:
                    columns,
                spacing:
                    tileSpacing
            ) {

                ForEach(
                    suggestions.prefix(5)
                ) { emoji in

                    emojiTile(
                        emoji
                    )
                }
            }
        }
    }


    // MARK: - Pinned

    private var pinnedSection:
        some View {

        VStack(
            alignment: .leading,
            spacing: 7
        ) {

            sectionHeader(
                "PINNED EMOJIS"
            )


            LazyVGrid(
                columns:
                    columns,
                spacing:
                    tileSpacing
            ) {

                ForEach(
                    emojiLibraryManager
                        .pinnedEmojis
                        .prefix(5)
                ) { emoji in

                    emojiTile(
                        emoji
                    )
                }
            }
        }
    }


    // MARK: - Emoji Tile

    private func emojiTile(
        _ emoji: ZestEmojiItem
    ) -> some View {

        let hovered =
            hoveredEmoji
            == emoji.character


        return Button {

            choose(
                emoji
            )

        } label: {

            Text(
                emoji.character
            )
            .font(
                .system(
                    size: 27
                )
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .frame(
                height:
                    tileHeight
            )
            .background {

                RoundedRectangle(
                    cornerRadius: 11,
                    style: .continuous
                )
                .fill(
                    Color.primary.opacity(
                        hovered
                            ? 0.075
                            : 0.040
                    )
                )
            }
            .overlay {

                RoundedRectangle(
                    cornerRadius: 11,
                    style: .continuous
                )
                .stroke(
                    Color.white.opacity(
                        hovered
                            ? 0.27
                            : 0.18
                    ),
                    lineWidth: 0.7
                )
            }
            .scaleEffect(
                hovered
                    ? 1.018
                    : 1.0
            )
        }
        .buttonStyle(
            .plain
        )
        .focusable(false)
        .onHover { hovering in

            withAnimation(
                .easeOut(
                    duration: 0.10
                )
            ) {

                hoveredEmoji =
                    hovering
                    ? emoji.character
                    : nil
            }
        }
        .help(
            emoji.name
        )
    }


    // MARK: - Header

    private func sectionHeader(
        _ title: String
    ) -> some View {

        HStack {

            Text(
                title
            )
            .font(
                .system(
                    size: 8,
                    weight: .bold
                )
            )
            .foregroundStyle(
                Color.secondary.opacity(0.75)
            )
            .tracking(0.8)


            Spacer()
        }
    }


    // MARK: - Actions

private func choose(
    _ emoji: ZestEmojiItem
) {

    print(
        "🍊 EMOJI →",
        emoji.character,
        emoji.name
    )


    textInserter?
        .insertUsingPasteboard(
            emoji.character
        )
}


    private func clearEverything() {

        withAnimation(
            .spring(
                response: 0.17,
                dampingFraction: 0.88
            )
        ) {

            query = ""
            selectedCategory = nil
        }


        searchFocused = false
    }


    private func clearCategory() {

        withAnimation(
            .spring(
                response: 0.17,
                dampingFraction: 0.88
            )
        ) {

            selectedCategory = nil
        }


        searchFocused = true
    }


    // MARK: - Short Names

    private func shortName(
        _ name: String
    ) -> String {

        let replacements: [
            String: String
        ] = [
            "Face with Tears of Joy":
                "Tears of Joy",

            "Rolling on the Floor Laughing":
                "ROFL",

            "Smiling Face with Hearts":
                "Hearts",

            "Grinning Face with Smiling Eyes":
                "Smiling",

            "Grinning Face with Big Eyes":
                "Grinning",

            "Loudly Crying Face":
                "Crying",

            "Smiling Face with Sunglasses":
                "Cool",

            "Clapping Hands":
                "Applause",

            "Folded Hands":
                "Prayer",

            "Musical Keyboard":
                "Piano",

            "Check Mark Button":
                "Check"
        ]


        return replacements[name]
            ?? name
    }


    // MARK: - Glass

    private var glassBody:
        some View {

        ZStack {

            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .fill(
                Color.clear
            )
            .glassEffect(
                .regular.tint(
                    accentColor.opacity(
                        0.035
                    )
                ),
                in:
                    RoundedRectangle(
                        cornerRadius: 24,
                        style: .continuous
                    )
            )


            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(
                            0.13
                        ),
                        Color.clear,
                        Color.black.opacity(
                            0.035
                        )
                    ],
                    startPoint:
                        .topLeading,
                    endPoint:
                        .bottomTrailing
                )
            )


            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .fill(
                RadialGradient(
                    colors: [
                        accentColor.opacity(
                            0.085
                        ),
                        Color.clear
                    ],
                    center:
                        .bottomLeading,
                    startRadius:
                        0,
                    endRadius:
                        240
                )
            )


            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(
                            0.72
                        ),
                        Color.white.opacity(
                            0.18
                        ),
                        accentColor.opacity(
                            0.12
                        )
                    ],
                    startPoint:
                        .topLeading,
                    endPoint:
                        .bottomTrailing
                ),
                lineWidth:
                    0.8
            )
        }
    }
}
