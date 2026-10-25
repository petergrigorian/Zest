//
//  ZestFontPanel.swift
//  Zest
//
//  Font + style picker for Control 3.
//

import SwiftUI
import AppKit


struct ZestFontPanel: View {

    @ObservedObject
    var textContextManager:
        TextContextManager

    @ObservedObject
    var fontLibraryManager:
        FontLibraryManager

    let accentColor: Color

    @Binding
    var isPresented: Bool


    @State private var query = ""

    @State private var fieldFocused =
        false

    @State private var showSuggestions =
        false

    @State private var hoveredFamily:
        String?

    @State private var boldEnabled =
        false

    @State private var italicEnabled =
        false

    @State private var underlineEnabled =
        false

    @State private var selectedTypeface =
        "Regular"

    @State private var showTypefaces =
        false


    @FocusState
    private var searchFocused: Bool


    private let panelWidth:
        CGFloat = 360

    var body: some View {

        VStack(
            spacing: 11
        ) {

            searchField


            // Main font-family browser belongs directly
            // to the main font-family field.
            if showSuggestions {

                suggestions
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


            formattingBar


            // Typeface/substyle choices belong to
            // the BIU + Typeface row.
            if showTypefaces {

                typefaceSuggestions
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


            pinnedFonts
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
        .onAppear {

            synchronizeFromContext()
        }
        .onChange(
            of:
                textContextManager.fontFamily
        ) { _, _ in

            guard !searchFocused else {
                return
            }

            synchronizeFromContext()
        }
        .onChange(
            of: textContextManager.fontTypeface
        ) { _, _ in
            synchronizeStyleFromContext()
        }
        .onChange(
            of:
                searchFocused
        ) { _, focused in

            fieldFocused =
                focused


            if
                focused,
                query
                    == textContextManager
                        .fontFamily
            {
                query = ""
            }
        }
        .onExitCommand {

            closePanel()
        }
    }


    // MARK: - Search

    private var searchField: some View {

        HStack(
            spacing: 8
        ) {

            Image(
                systemName:
                    "textformat"
            )
            .font(
                .system(
                    size: 12,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                Color.secondary
            )


            TextField(
                "Search fonts…",
                text:
                    $query
            )
            .textFieldStyle(
                .plain
            )
            .font(
                .system(
                    size: 13,
                    weight: .semibold
                )
            )
            .focused(
                $searchFocused
            )
            .simultaneousGesture(TapGesture().onEnded {
                NotificationCenter.default.post(name: .zestRuntimeKeyboardFocusRequested, object: nil)
                DispatchQueue.main.async { searchFocused = true }
            })
            .onSubmit {

                if let first =
                    filteredFamilies.first
                {
                    choose(
                        first
                    )
                }
            }


            Button {

                let shouldOpen =
                    !showSuggestions


                searchFocused =
                    false

                fieldFocused =
                    false


                // Opening the browser is NOT a search.
                //
                // The field normally contains the currently
                // selected font family. Previously that value
                // was accidentally being interpreted as the
                // search query, which is why opening the list
                // while using an "A..." font showed only A fonts.
                if shouldOpen {

                    query = ""

                } else {

                    // When closing the browser without choosing
                    // anything, restore the current font name
                    // to the field.
                    query =
                        textContextManager.fontFamily
                        ?? ""
                }


                withAnimation(
                    .spring(
                        response: 0.16,
                        dampingFraction: 0.90
                    )
                ) {

                    showTypefaces =
                        false

                    showSuggestions =
                        shouldOpen
                }

            } label: {

                ZStack {

                    RoundedRectangle(
                        cornerRadius: 7,
                        style: .continuous
                    )
                    .fill(
                        accentColor.opacity(0.82)
                    )


                    RoundedRectangle(
                        cornerRadius: 7,
                        style: .continuous
                    )
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.16),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )


                    Image(
                        systemName:
                            showSuggestions
                            ? "chevron.up"
                            : "chevron.down"
                    )
                    .font(
                        .system(
                            size: 10,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        .white
                    )
                }
                .frame(
                    width: 34,
                    height: 24
                )
                .contentShape(
                    Rectangle()
                )
                .padding(
                    .trailing,
                    -5
                )
                .frame(
                    width: 34,
                    height: 28
                )
                .contentShape(
                    Rectangle()
                )
            }
            .buttonStyle(
                .plain
            )
            .focusable(false)
            .contentShape(
                Rectangle()
            )
        }
        .padding(
            .horizontal,
            10
        )
        .frame(
            height: 34
        )
        .background {

            RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
            .fill(
                Color.primary.opacity(0.045)
            )
        }
        .overlay {

            RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
            .stroke(
                fieldFocused
                ? accentColor.opacity(0.55)
                : Color.white.opacity(0.24),
                lineWidth:
                    fieldFocused
                    ? 1.15
                    : 0.75
            )
        }
    }


    // MARK: - BIU + Typeface

    private var formattingBar: some View {

        HStack(
            spacing: 6
        ) {

            styleButton(
                title: "B",
                enabled:
                    boldEnabled
            ) {

                textContextManager.toggleBold()
            }


            styleButton(
                title: "I",
                enabled:
                    italicEnabled,
                italic: true
            ) {

                textContextManager.toggleItalic()
            }


            styleButton(
                title: "U",
                enabled:
                    underlineEnabled,
                underline: true
            ) {

                underlineEnabled.toggle()
                textContextManager.toggleUnderline()
            }


            Rectangle()
                .fill(
                    Color.white.opacity(0.18)
                )
                .frame(
                    width: 1,
                    height: 22
                )
                .padding(
                    .horizontal,
                    2
                )


            Button {

                withAnimation(
                    .spring(
                        response: 0.16,
                        dampingFraction: 0.90
                    )
                ) {

                    showSuggestions =
                        false

                    showTypefaces.toggle()
                }

            } label: {

                HStack(
                    spacing: 6
                ) {

                    Text(
                        selectedTypeface
                    )
                    .font(
                        .system(
                            size: 11,
                            weight: .semibold
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)


                    Spacer(
                        minLength: 2
                    )


                    Image(
                        systemName:
                            showTypefaces
                            ? "chevron.up"
                            : "chevron.down"
                    )
                    .font(
                        .system(
                            size: 8,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        Color.secondary
                    )
                }
                .padding(
                    .horizontal,
                    9
                )
                .frame(
                    height: 30
                )
                .background {

                    RoundedRectangle(
                        cornerRadius: 9,
                        style: .continuous
                    )
                    .fill(
                        Color.primary.opacity(0.045)
                    )
                }
                .overlay {

                    RoundedRectangle(
                        cornerRadius: 9,
                        style: .continuous
                    )
                    .stroke(
                        showTypefaces
                        ? accentColor.opacity(0.45)
                        : Color.white.opacity(0.22),
                        lineWidth:
                            showTypefaces
                            ? 1.0
                            : 0.7
                    )
                }
            }
            .buttonStyle(
                .plain
            )
            .focusable(false)
            .frame(
                maxWidth: .infinity
            )
        }
        .frame(
            height: 32
        )
    }


    private func styleButton(
        title: String,
        enabled: Bool,
        italic: Bool = false,
        underline: Bool = false,
        action:
            @escaping () -> Void
    ) -> some View {

        Button(
            action:
                action
        ) {

            Text(
                title
            )
            .font(
                .system(
                    size: 13,
                    weight:
                        title == "B"
                        ? .bold
                        : .semibold
                )
                .italic(
                    italic
                )
            )
            .underline(
                underline
            )
            .foregroundStyle(
                Color.primary.opacity(0.82)
            )
            .frame(
                width: 34,
                height: 30
            )
            .background {

                RoundedRectangle(
                    cornerRadius: 9,
                    style: .continuous
                )
                .fill(
                    Color.primary.opacity(
                        enabled ? 0.085 : 0.04
                    )
                )
            }
            .overlay {

                RoundedRectangle(
                    cornerRadius: 9,
                    style: .continuous
                )
                .stroke(
                    Color.white.opacity(
                        enabled ? 0.28 : 0.20
                    ),
                    lineWidth: 0.7
                )
            }
        }
        .buttonStyle(
            ZestPressButtonStyle()
        )
        .focusable(false)
    }


    // MARK: - Typeface Suggestions

    private var typefaceSuggestions: some View {

        ScrollView(
            .vertical,
            showsIndicators: false
        ) {

            LazyVStack(
                spacing: 3
            ) {

                ForEach(
                    availableTypefaces,
                    id: \.self
                ) { typeface in

                    Button {

                        selectedTypeface =
                            typeface


                        withAnimation(
                            .spring(
                                response: 0.18,
                                dampingFraction: 0.88
                            )
                        ) {

                            showTypefaces =
                                false
                        }


                        textContextManager
                            .setTypeface(
                                typeface
                            )

                    } label: {

                        HStack {

                            Text(
                                typeface
                            )
                            .font(
                                .system(
                                    size: 11.5,
                                    weight: .medium
                                )
                            )


                            Spacer()


                            if
                                typeface
                                    == selectedTypeface
                            {

                                Image(
                                    systemName:
                                        "checkmark"
                                )
                                .font(
                                    .system(
                                        size: 9,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(
                                    accentColor
                                )
                            }
                        }
                        .foregroundStyle(
                            Color.primary.opacity(0.90)
                        )
                        .padding(
                            .horizontal,
                            10
                        )
                        .frame(
                            height: 29
                        )
                        .background {

                            RoundedRectangle(
                                cornerRadius: 8,
                                style: .continuous
                            )
                            .fill(
                                typeface
                                    == selectedTypeface
                                ? accentColor.opacity(0.09)
                                : Color.primary.opacity(0.02)
                            )
                        }
                    }
                    .buttonStyle(
                        .plain
                    )
                    .focusable(false)
                }
            }
            .padding(4)
        }
        .frame(
            height:
                min(
                    CGFloat(
                        max(
                            availableTypefaces.count,
                            1
                        )
                    )
                    * 32
                    + 8,
                    132
                )
        )
        .background {

            RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
            .fill(
                Color.primary.opacity(0.035)
            )
        }
        .overlay {

            RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.20),
                lineWidth: 0.7
            )
        }
    }


    // MARK: - Font Suggestions

    private var suggestions: some View {

        ScrollView {

            LazyVStack(
                spacing: 3
            ) {

                ForEach(
                    filteredFamilies,
                    id: \.self
                ) { family in

                    Button {

                        choose(
                            family
                        )

                    } label: {

                        HStack(
                            spacing: 10
                        ) {

                            Text(
                                "Aa"
                            )
                            .font(
                                previewFont(
                                    family,
                                    size: 17
                                )
                            )
                            .frame(
                                width: 34
                            )


                            Text(
                                family
                            )
                            .font(
                                .system(
                                    size: 12,
                                    weight: .medium
                                )
                            )
                            .lineLimit(1)


                            Spacer()


                            if matchesCurrent(
                                family
                            ) {

                                Image(
                                    systemName:
                                        "checkmark"
                                )
                                .font(
                                    .system(
                                        size: 10,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(
                                    accentColor
                                )
                            }
                        }
                        .foregroundStyle(
                            Color.primary.opacity(0.90)
                        )
                        .padding(
                            .horizontal,
                            9
                        )
                        .frame(
                            height: 30
                        )
                        .background {

                            RoundedRectangle(
                                cornerRadius: 8,
                                style: .continuous
                            )
                            .fill(
                                hoveredFamily
                                    == family
                                ? accentColor.opacity(0.10)
                                : Color.primary.opacity(0.025)
                            )
                        }
                        .contentShape(
                            Rectangle()
                        )
                    }
                    .buttonStyle(
                        .plain
                    )
                    .focusable(false)
                    .onHover { hovering in

                        hoveredFamily =
                            hovering
                            ? family
                            : nil
                    }
                }


                if filteredFamilies.isEmpty {

                    Text(
                        "No matching installed fonts"
                    )
                    .font(
                        .system(
                            size: 11,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(
                        Color.secondary
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                    .padding(
                        .vertical,
                        12
                    )
                }
            }
            .padding(4)
        }
        .frame(
            height:
                min(
                    CGFloat(
                        max(
                            filteredFamilies.count,
                            1
                        )
                    )
                    * 33
                    + 8,
                    150
                )
        )
        .background {

            RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
            .fill(
                Color.primary.opacity(0.035)
            )
        }
        .overlay {

            RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.20),
                lineWidth: 0.7
            )
        }
    }


    // MARK: - Pinned

    private var pinnedFonts: some View {

        VStack(
            alignment: .leading,
            spacing: 7
        ) {

            HStack {

                Text(
                    "PINNED"
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


            HStack(
                spacing: 7
            ) {

                ForEach(
                    Array(
                        fontLibraryManager
                            .quickAccessFonts
                            .prefix(5)
                    ),
                    id: \.self
                ) { family in

                    pinnedCard(
                        family
                    )
                }
            }
        }
    }


    private func pinnedCard(
        _ family: String
    ) -> some View {

        let selected =
            matchesCurrent(
                family
            )


        return Button {

            choose(
                family
            )

        } label: {

            VStack(
                spacing: 3
            ) {

                Text(
                    "A"
                )
                .font(
                    previewFont(
                        family,
                        size: 25
                    )
                )
                .frame(
                    height: 29
                )


                Text(
                    shortDisplayName(
                        family
                    )
                )
                .font(
                    .system(
                        size: 7.5,
                        weight: .medium
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(
                    maxWidth: .infinity
                )
            }
            .foregroundStyle(
                Color.primary.opacity(0.90)
            )
            .frame(
                maxWidth: .infinity
            )
            .frame(
                height: 57
            )
            .background {

                RoundedRectangle(
                    cornerRadius: 11,
                    style: .continuous
                )
                .fill(
                    selected
                    ? accentColor.opacity(0.15)
                    : Color.primary.opacity(0.04)
                )
            }
            .overlay {

                RoundedRectangle(
                    cornerRadius: 11,
                    style: .continuous
                )
                .stroke(
                    selected
                    ? accentColor.opacity(0.58)
                    : Color.white.opacity(0.22),
                    lineWidth:
                        selected
                        ? 1.15
                        : 0.7
                )
            }
            .contentShape(
                Rectangle()
            )
        }
        .buttonStyle(
            ZestPressButtonStyle()
        )
        .focusable(false)
    }


    // MARK: - Glass

    private var glassBody: some View {

        ZStack {

            Color.clear
                .glassEffect(
                    .regular
                        .tint(
                            accentColor.opacity(0.035)
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
                    stops: [
                        .init(
                            color:
                                Color.white.opacity(0.18),
                            location: 0
                        ),
                        .init(
                            color:
                                Color.white.opacity(0.065),
                            location: 0.28
                        ),
                        .init(
                            color:
                                Color.clear,
                            location: 0.62
                        ),
                        .init(
                            color:
                                Color.black.opacity(0.035),
                            location: 1
                        )
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )


            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .fill(
                RadialGradient(
                    colors: [
                        accentColor.opacity(0.075),
                        Color.clear
                    ],
                    center:
                        UnitPoint(
                            x: 0.86,
                            y: 0.18
                        ),
                    startRadius: 0,
                    endRadius: 190
                )
            )


            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.88),
                        Color.white.opacity(0.36),
                        Color.white.opacity(0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.9
            )
        }
        .allowsHitTesting(false)
    }


    // MARK: - Data

    private var availableTypefaces: [String] {

        guard
            let family =
                currentFamily
        else {
            return [
                "Regular"
            ]
        }


        guard
            let members =
                NSFontManager.shared
                    .availableMembers(
                        ofFontFamily:
                            family
                    )
        else {
            return [
                "Regular"
            ]
        }


        var result:
            [String] = []


        for member in members {

            guard
                member.count >= 2,
                let face =
                    member[1]
                    as? String,
                !face.isEmpty
            else {
                continue
            }


            if !result.contains(
                face
            ) {

                result.append(
                    face
                )
            }
        }


        return
            result.isEmpty
            ? ["Regular"]
            : result
    }


    private var currentFamily: String? {

        let candidate =
            textContextManager
                .fontFamily?
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )


        guard
            let candidate,
            !candidate.isEmpty
        else {
            return nil
        }


        return candidate
    }


    private var filteredFamilies: [String] {

        let needle =
            query.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )


        guard !needle.isEmpty else {

            return
                fontLibraryManager
                    .families
        }


        let starts =
            fontLibraryManager
                .families
                .filter { family in

                    family.range(
                        of: needle,
                        options: [
                            .caseInsensitive,
                            .diacriticInsensitive,
                            .anchored
                        ]
                    ) != nil
                }


        let contains =
            fontLibraryManager
                .families
                .filter { family in

                    let isPrefix =
                        family.range(
                            of: needle,
                            options: [
                                .caseInsensitive,
                                .diacriticInsensitive,
                                .anchored
                            ]
                        ) != nil


                    let isContained =
                        family.range(
                            of: needle,
                            options: [
                                .caseInsensitive,
                                .diacriticInsensitive
                            ]
                        ) != nil


                    return
                        !isPrefix
                        && isContained
                }


        return
            starts
            + contains
    }


    // MARK: - Actions

    private func choose(
        _ family: String
    ) {

        query =
            family

        searchFocused =
            false

        fieldFocused =
            false


        withAnimation(
            .spring(
                response: 0.20,
                dampingFraction: 0.84
            )
        ) {

            showSuggestions =
                false

            showTypefaces =
                false
        }


        textContextManager
            .setFontFamily(
                family
            )


        selectedTypeface =
            availableTypefaces
                .first
            ?? "Regular"
    }


    private func synchronizeFromContext() {

        query =
            textContextManager.fontFamily
            ?? ""

        synchronizeStyleFromContext()
    }


    private func synchronizeStyleFromContext() {

        let faces = availableTypefaces
        let reported = textContextManager.fontTypeface

        if let reported, faces.contains(reported) {
            selectedTypeface = reported
        } else if !faces.contains(selectedTypeface) {
            selectedTypeface = faces.first ?? "Regular"
        }

        let lower = selectedTypeface.lowercased()
        boldEnabled = lower.contains("bold")
        italicEnabled = lower.contains("italic") || lower.contains("oblique")
    }


    private func closePanel() {

        searchFocused =
            false

        fieldFocused =
            false


        withAnimation(
            .spring(
                response: 0.24,
                dampingFraction: 0.84
            )
        ) {

            isPresented =
                false
        }
    }


    // MARK: - Helpers

    private func matchesCurrent(
        _ family: String
    ) -> Bool {

        guard
            let current =
                textContextManager
                    .fontFamily
        else {
            return false
        }


        return
            current.compare(
                family,
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive
                ]
            )
            == .orderedSame
    }


    private func previewFont(
        _ family: String,
        size: CGFloat
    ) -> Font {

        if
            NSFontManager.shared
                .availableFontFamilies
                .contains(
                    where: {

                        $0.compare(
                            family,
                            options: [
                                .caseInsensitive,
                                .diacriticInsensitive
                            ]
                        )
                        == .orderedSame
                    }
                )
        {

            return
                .custom(
                    family,
                    size: size
                )
        }


        return
            .system(
                size: size
            )
    }


    private func shortDisplayName(
        _ family: String
    ) -> String {

        switch family {

        case "Times New Roman":
            return "Times"

        case "Courier New":
            return "Courier"

        case "Avenir Next":
            return "Avenir"

        default:
            return family
        }
    }
}


extension Notification.Name {
    static let zestRuntimeKeyboardFocusRequested = Notification.Name("zestRuntimeKeyboardFocusRequested")
}
