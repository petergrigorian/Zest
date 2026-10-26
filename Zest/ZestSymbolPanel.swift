//
//  ZestSymbolPanel.swift
//  Zest
//
//  Symbol browser for Control 6.
//

import SwiftUI


struct ZestSymbolPanel: View {

    @ObservedObject
    var symbolLibraryManager:
        SymbolLibraryManager

    @ObservedObject
    var clipboardManager:
        ClipboardHistoryManager

    let accentColor: Color


    @State
    private var query = ""

    @State
    private var selectedCategory:
        ZestSymbolCategory?

    @State
    private var hoveredSymbol:
        String?

    @State
    private var hoveredCategory:
        ZestSymbolCategory?

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
                    spacing:
                        tileSpacing
                ),
            count: 5
        )
    }


    // MARK: - Search

    private var searchResults:
        [ZestSymbolItem] {

        if !hasSearchText,
           let selectedCategory {

            return symbolLibraryManager
                .symbols
                .filter {
                    $0.category
                        == selectedCategory
                }
        }


        return symbolLibraryManager.search(
            query:
                query,
            category:
                selectedCategory
        )
    }


    private var suggestions:
        [ZestSymbolItem] {

        symbolLibraryManager.suggestions(
            in:
                selectedCategory
        )
    }


    private var hasSearchText:
        Bool {

        !query
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
            .isEmpty
    }
    
    private var shouldShowResults:
        Bool {

        hasSearchText
        || selectedCategory != nil
    }


    // MARK: - Body

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
                                        edge:
                                            .top
                                    )
                            )
                    )
            }


            suggestionSection

            pinnedSection
        }
        .padding(13)
        .frame(
            width:
                panelWidth
        )
        .background {
            glassBody
        }
        .shadow(
            color:
                Color.black.opacity(
                    0.20
                ),
            radius: 15,
            x: 0,
            y: 8
        )
        .shadow(
            color:
                accentColor.opacity(
                    0.07
                ),
            radius: 10,
            x: 0,
            y: 4
        )
        .animation(
            .spring(
                response: 0.18,
                dampingFraction: 0.88
            ),
            value:
                shouldShowResults
        )
        .animation(
            .spring(
                response: 0.18,
                dampingFraction: 0.88
            ),
            value:
                selectedCategory
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

    private var searchField:
        some View {

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
                Color.secondary.opacity(
                    0.72
                )
            )


            if let selectedCategory {

                categoryToken(
                    selectedCategory
                )
            }


            TextField(
                selectedCategory == nil
                    ? "Search symbols..."
                    : "Search...",
                text:
                    $query
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
                        Color.secondary.opacity(
                            0.68
                        )
                    )
                }
                .buttonStyle(
                    .plain
                )
                .focusable(false)
            }
        }
        .padding(
            .horizontal,
            10
        )
        .frame(
            height: 36
        )
        .background {

            RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
            .fill(
                Color.primary.opacity(
                    0.035
                )
            )
        }
        .overlay {

            RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
            .stroke(
                searchFocused
                    ? accentColor.opacity(
                        0.65
                    )
                    : Color.white.opacity(
                        0.20
                    ),
                lineWidth:
                    searchFocused
                    ? 1.2
                    : 0.7
            )
        }
    }


    // MARK: - Category Token

    private func categoryToken(
        _ category:
            ZestSymbolCategory
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

                withAnimation(
                    .spring(
                        response: 0.17,
                        dampingFraction: 0.88
                    )
                ) {

                    selectedCategory =
                        nil
                }

                searchFocused =
                    true

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
            Color.primary.opacity(
                0.72
            )
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
                    Color.primary.opacity(
                        0.060
                    )
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
                    ZestSymbolCategory.allCases
                ) { category in

                    categoryChip(
                        category
                    )
                }
            }
        }
    }


    private func categoryChip(
        _ category:
            ZestSymbolCategory
    ) -> some View {

        let selected =
            selectedCategory
            == category

        let hovered =
            hoveredCategory
            == category


        return Button {

            withAnimation(
                .spring(
                    response: 0.17,
                    dampingFraction: 0.88
                )
            ) {

                if selected {

                    selectedCategory =
                        nil

                } else {

                    selectedCategory =
                        category
                }
            }


            searchFocused =
                true

        } label: {

            Text(
                category.rawValue
            )
            .font(
                .system(
                    size: 9,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                Color.primary.opacity(
                    selected
                        ? 0.90
                        : 0.66
                )
            )
            .padding(
                .horizontal,
                9
            )
            .frame(
                height: 25
            )
            .background {

                Capsule()
                    .fill(
                        Color.primary.opacity(
                            selected
                                ? 0.085
                                : hovered
                                    ? 0.065
                                    : 0.040
                        )
                    )
            }
            .overlay {

                Capsule()
                    .stroke(
                        Color.white.opacity(
                            selected
                                ? 0.25
                                : 0.14
                        ),
                        lineWidth: 0.6
                    )
            }
        }
        .buttonStyle(
            .plain
        )
        .focusable(false)
        .onHover {
            hovering in

            hoveredCategory =
                hovering
                ? category
                : nil
        }
    }


    // MARK: - Results

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
                            "No symbols found"
                        )
                        .font(
                            .system(
                                size: 10,
                                weight: .medium
                            )
                        )
                    }
                    .foregroundStyle(
                        Color.secondary.opacity(
                            0.62
                        )
                    )


                    Spacer()
                }
                .frame(
                    height: 76
                )
                .background {
                    resultSurface
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
                        ) { symbol in

                            symbolTile(
                                symbol
                            )
                        }
                    }
                    .padding(7)
                }
                .frame(
                    height: 185
                )
                .background {
                    resultSurface
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


    private var resultSurface:
        some View {

        RoundedRectangle(
            cornerRadius: 12,
            style: .continuous
        )
        .fill(
            Color.primary.opacity(
                0.030
            )
        )
        .overlay {

            RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(
                    0.16
                ),
                lineWidth: 0.7
            )
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
                    suggestions
                ) { symbol in

                    symbolTile(
                        symbol
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
                "PINNED SYMBOLS"
            )


            LazyVGrid(
                columns:
                    columns,
                spacing:
                    tileSpacing
            ) {

                ForEach(
                    symbolLibraryManager
                        .pinnedSymbols
                ) { symbol in

                    symbolTile(
                        symbol
                    )
                }
            }
        }
    }


    // MARK: - Symbol Tile

    private func symbolTile(
        _ symbol:
            ZestSymbolItem
    ) -> some View {

        let hovered =
            hoveredSymbol
            == symbol.character


        return Button {

            choose(
                symbol
            )

        } label: {

            Text(
                symbol.character
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
        .onHover {
            hovering in

            withAnimation(
                .easeOut(
                    duration: 0.10
                )
            ) {

                hoveredSymbol =
                    hovering
                    ? symbol.character
                    : nil
            }
        }
        .help(
            symbol.name
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
                    size: 9,
                    weight: .bold
                )
            )
            .foregroundStyle(
                Color.secondary.opacity(
                    0.72
                )
            )
            .tracking(0.8)


            Spacer()
        }
    }


    // MARK: - Actions

    private func choose(
        _ symbol:
            ZestSymbolItem
    ) {

        print(
            "🍊 SYMBOL →",
            symbol.character,
            symbol.name
        )


        textInserter?
            .insertUsingPasteboard(
                symbol.character
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

            selectedCategory =
                nil
        }


        searchFocused =
            false
    }


    // MARK: - Glass

    private var glassBody:
        some View {

        ZStack {

            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .fill(
                Color.clear
            )
            .glassEffect(
                .regular,
                in:
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
            )


            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .fill(
                Color.white.opacity(
                    0.025
                )
            )


            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(
                    0.28
                ),
                lineWidth: 0.8
            )


            RoundedRectangle(
                cornerRadius: 19,
                style: .continuous
            )
            .inset(
                by: 1
            )
            .stroke(
                accentColor.opacity(
                    0.08
                ),
                lineWidth: 0.7
            )
        }
    }
}
