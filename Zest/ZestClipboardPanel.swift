//
//  ZestClipboardPanel.swift
//  Zest
//
//  Clipboard history popup for Zest.
//

import SwiftUI
import AppKit


struct ZestClipboardPanel: View {

    @ObservedObject
    var clipboardManager: ClipboardHistoryManager

    let accentColor: Color


    // MARK: - State

    @State private var showingClearConfirmation = false

    @State private var hoveredEntryID: UUID?

    @State private var selectedEntryIDs: Set<UUID> = []
    
    @State private var textInserter:ZestTextInserter?


    // MARK: - Geometry

    private let panelWidth: CGFloat = 300
    private let panelHeight: CGFloat = 360
    private let expandedContentHeight: CGFloat = 224
    private let selectedContentHeight: CGFloat = 182

    private var currentContentHeight: CGFloat {
        selectedEntryIDs.isEmpty
            ? expandedContentHeight
            : selectedContentHeight
    }


    // MARK: - Body

    var body: some View {

        ZStack {

            panelContent

            if showingClearConfirmation {

                confirmationLayer
                    .transition(
                        .opacity
                            .combined(
                                with:
                                    .scale(
                                        scale: 0.97
                                    )
                            )
                    )
                    .zIndex(20)
            }
        }
        .frame(
            width: panelWidth,
            height: panelHeight
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
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
            .spring(response: 0.22, dampingFraction: 0.86),
            value: selectedEntryIDs.isEmpty
        )
        .onExitCommand {

            if showingClearConfirmation {

                withAnimation(
                    .spring(
                        response: 0.20,
                        dampingFraction: 0.88
                    )
                ) {
                    showingClearConfirmation = false
                }

            } else if !selectedEntryIDs.isEmpty {

                withAnimation(
                    .spring(
                        response: 0.18,
                        dampingFraction: 0.88
                    )
                ) {
                    selectedEntryIDs.removeAll()
                }
            }
        }
        .onChange(
            of: clipboardManager.entries
        ) { _, entries in

            // If history changes while some rows are selected,
            // remove IDs that no longer exist.

            let existingIDs =
                Set(
                    entries.map(\.id)
                )

            selectedEntryIDs =
                selectedEntryIDs
                    .intersection(
                        existingIDs
                    )
        }
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


    // MARK: - Main Panel

    private var panelContent: some View {

        VStack(
            spacing: 10
        ) {

            header

            clipboardContent

            if !selectedEntryIDs.isEmpty {
                pasteSelectionButton
                    .transition(
                        .opacity
                            .combined(
                                with: .move(edge: .bottom)
                            )
                    )
            }

            cleanButton
        }
        .padding(
            .horizontal,
            13
        )
        .padding(
            .top,
            16
        )
        .padding(
            .bottom,
            15
        )
        .frame(
            width: panelWidth,
            height: panelHeight
        )
        .background {
            glassBody
        }
    }


    // MARK: - Header

    private var header: some View {

        HStack(
            spacing: 8
        ) {

            Image(
                systemName:
                    "doc.on.clipboard"
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


            Text(
                "Clipboard"
            )
            .font(
                .system(
                    size: 13,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                Color.primary.opacity(0.90)
            )


            Spacer()


            Text(
                "\(clipboardManager.entries.count)"
            )
            .font(
                .system(
                    size: 10,
                    weight: .semibold,
                    design: .rounded
                )
            )
            .foregroundStyle(
                Color.secondary
            )
            .padding(
                .horizontal,
                8
            )
            .frame(
                height: 24
            )
            .background {

                Capsule()
                    .fill(
                        Color.primary.opacity(0.045)
                    )
            }
            .overlay {

                Capsule()
                    .stroke(
                        Color.white.opacity(0.24),
                        lineWidth: 0.75
                    )
            }
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
                Color.white.opacity(0.24),
                lineWidth: 0.75
            )
        }
    }


    // MARK: - Clipboard Content

    @ViewBuilder
    private var clipboardContent: some View {

        if clipboardManager.entries.isEmpty {

            emptyState

        } else {

            ScrollView(
                .vertical,
                showsIndicators: false
            ) {

                LazyVStack(
                    spacing: 6
                ) {

                    ForEach(
                        clipboardManager.entries
                    ) { entry in

                        entryRow(
                            entry
                        )
                    }
                }
                .padding(4)
            }
            .frame(
                height: currentContentHeight
            )
            .background {

                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
                .fill(
                    Color.primary.opacity(0.025)
                )
            }
            .overlay {

                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
                .stroke(
                    Color.white.opacity(0.18),
                    lineWidth: 0.7
                )
            }
        }
    }


    // MARK: - Empty State

    private var emptyState: some View {

        VStack(
            spacing: 7
        ) {

            Spacer()


            Image(
                systemName:
                    "doc.on.clipboard"
            )
            .font(
                .system(
                    size: 22,
                    weight: .light
                )
            )
            .foregroundStyle(
                Color.secondary.opacity(0.72)
            )


            Text(
                "Clipboard is empty"
            )
            .font(
                .system(
                    size: 11.5,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                Color.primary.opacity(0.86)
            )


            Text(
                "Copied text will appear here."
            )
            .font(
                .system(
                    size: 9.5,
                    weight: .medium
                )
            )
            .foregroundStyle(
                Color.secondary.opacity(0.82)
            )


            Spacer()
        }
        .frame(
            maxWidth: .infinity
        )
        .frame(
            height: currentContentHeight
        )
        .background {

            RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
            .fill(
                Color.primary.opacity(0.025)
            )
        }
        .overlay {

            RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.18),
                lineWidth: 0.7
            )
        }
    }


    // MARK: - Entry Row

    private func entryRow(
        _ entry:
            ClipboardHistoryManager.Entry
    ) -> some View {

        let hovered =
            hoveredEntryID
            == entry.id

        let selected =
            selectedEntryIDs
                .contains(
                    entry.id
                )


        return Button {

            toggleSelection(
                entry
            )

        } label: {

            HStack(
                spacing: 9
            ) {

                ZStack {

                    RoundedRectangle(
                        cornerRadius: 8,
                        style: .continuous
                    )
                    .fill(
                        // Neutral only.
                        //
                        // Hover dims the transparent surface
                        // instead of introducing a new color.
                        Color.primary.opacity(
                            hovered
                            ? 0.070
                            : 0.035
                        )
                    )


                    Image(
                        systemName:
                            iconName(
                                for:
                                    entry.text
                            )
                    )
                    .font(
                        .system(
                            size: 10.5,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        Color.secondary.opacity(
                            hovered
                            ? 0.95
                            : 0.76
                        )
                    )
                }
                .frame(
                    width: 30,
                    height: 30
                )


                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {

                    Text(
                        displayText(
                            entry.text
                        )
                    )
                    .font(
                        .system(
                            size: 10.5,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(
                        Color.primary.opacity(0.90)
                    )
                    .lineLimit(2)
                    .multilineTextAlignment(
                        .leading
                    )


                    Text(
                        relativeTime(
                            for:
                                entry.createdAt
                        )
                    )
                    .font(
                        .system(
                            size: 8.5,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(
                        Color.secondary.opacity(0.78)
                    )
                }


                Spacer(
                    minLength: 4
                )


                selectionCircle(
                    selected:
                        selected
                )
            }
            .padding(
                .horizontal,
                9
            )
            .frame(
                minHeight: 46
            )
            .background {

                RoundedRectangle(
                    cornerRadius: 9,
                    style: .continuous
                )
                .fill(
                    Color.primary.opacity(
                        hovered
                        ? 0.070
                        : selected
                            ? 0.045
                            : 0.020
                    )
                )
            }
            .overlay {

                RoundedRectangle(
                    cornerRadius: 9,
                    style: .continuous
                )
                .stroke(
                    selected
                    ? Color.primary.opacity(0.15)
                    : hovered
                        ? Color.primary.opacity(0.12)
                        : Color.white.opacity(0.10),
                    lineWidth:
                        selected
                        ? 0.85
                        : 0.65
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
        .onHover { hovering in

            withAnimation(
                .easeOut(
                    duration: 0.12
                )
            ) {

                hoveredEntryID =
                    hovering
                    ? entry.id
                    : nil
            }
        }
    }


    // MARK: - Selection Circle

    private func selectionCircle(
        selected: Bool
    ) -> some View {

        ZStack {

            Circle()
                .fill(
                    selected
                    ? accentColor.opacity(0.86)
                    : Color.clear
                )


            Circle()
                .stroke(
                    selected
                    ? accentColor.opacity(0.92)
                    : Color.secondary.opacity(0.46),
                    lineWidth: 1.15
                )


            if selected {

                Image(
                    systemName:
                        "checkmark"
                )
                .font(
                    .system(
                        size: 7.5,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    .white
                )
            }
        }
        .frame(
            width: 17,
            height: 17
        )
        .animation(
            .spring(
                response: 0.18,
                dampingFraction: 0.82
            ),
            value:
                selected
        )
    }


    // MARK: - Paste Selection

    private func pasteSelection() {

        // ClipboardHistoryManager stores newest first.
        //
        // For a combined paste we reverse the selected
        // history subset so that the resulting text follows
        // chronological clipboard order: oldest → newest.

        let selectedEntries =
            clipboardManager
                .entries
                .filter {

                    selectedEntryIDs
                        .contains(
                            $0.id
                        )
                }
                .reversed()


        let combinedText =
            selectedEntries
                .map(\.text)
                .joined(
                    separator: "\n"
                )


        guard !combinedText.isEmpty else {
            return
        }


        // Use the same insertion backend as Emoji.
        //
        // It first attempts direct Accessibility insertion.
        // If that isn't supported by the target control,
        // it falls back to temporary clipboard + Command-V
        // and restores the user's original clipboard.

        textInserter?
            .insert(
                combinedText
            )


        withAnimation(
            .spring(
                response: 0.20,
                dampingFraction: 0.86
            )
        ) {

            selectedEntryIDs
                .removeAll()
        }


        print(
            "🍊 PASTE SELECTION → \(selectedEntries.count) item(s)"
        )
    }
    
    // MARK: - Paste Selection Button

    private var pasteSelectionButton:
        some View {

        Button {

            pasteSelection()

        } label: {

            HStack(
                spacing: 7
            ) {

                Image(
                    systemName:
                        "arrow.down.doc"
                )
                .font(
                    .system(
                        size: 10,
                        weight: .semibold
                    )
                )


                Text(
                    selectedEntryIDs.count == 1
                    ? "Paste Selection"
                    : "Paste \(selectedEntryIDs.count) Items"
                )
                .font(
                    .system(
                        size: 10.5,
                        weight: .semibold
                    )
                )
            }
            .foregroundStyle(
                Color.primary.opacity(0.88)
            )
            .frame(
                maxWidth: .infinity
            )
            .frame(
                height: 34
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
                    Color.white.opacity(0.18),
                    lineWidth: 0.7
                )
            }
        }
        .buttonStyle(
            ZestPressButtonStyle()
        )
        .focusable(false)
    }


    // MARK: - Clean Clipboard Button

    private var cleanButton:
        some View {

        Button {

            showingClearConfirmation =
                true

        } label: {

            HStack(
                spacing: 7
            ) {

                Image(
                    systemName:
                        "trash"
                )
                .font(
                    .system(
                        size: 10,
                        weight: .semibold
                    )
                )


                Text(
                    "Clean Clipboard"
                )
                .font(
                    .system(
                        size: 10.5,
                        weight: .semibold
                    )
                )
            }
            .foregroundStyle(
                Color.primary.opacity(0.72)
            )
            .frame(
                maxWidth: .infinity
            )
            .frame(
                height: 31
            )
            .contentShape(
                Rectangle()
            )
        }
        .buttonStyle(
            .plain
        )
        .focusable(false)
    }


    // MARK: - Selection

    private func toggleSelection(
        _ entry:
            ClipboardHistoryManager.Entry
    ) {

        let id =
            entry.id


        withAnimation(
            .spring(
                response: 0.18,
                dampingFraction: 0.84
            )
        ) {

            if selectedEntryIDs.contains(
                id
            ) {

                selectedEntryIDs.remove(
                    id
                )

            } else {

                selectedEntryIDs.insert(
                    id
                )
            }
        }
    }


    // MARK: - Confirmation

    // MARK: - Confirmation

    private var confirmationLayer: some View {

        ZStack {

            // The dim is strictly local to the Clipboard panel.

            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .fill(
                Color.black.opacity(0.12)
            )
            .background {

                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
                .fill(
                    .ultraThinMaterial
                )
            }


            confirmationCard
        }
        .frame(
            width: panelWidth,
            height: panelHeight
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
    }


    private var confirmationCard: some View {

        VStack(
            spacing: 11
        ) {

            ZStack {

                Circle()
                    .fill(
                        accentColor.opacity(0.12)
                    )


                Image(
                    systemName:
                        "trash"
                )
                .font(
                    .system(
                        size: 14,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    accentColor
                )
            }
            .frame(
                width: 36,
                height: 36
            )


            VStack(
                spacing: 4
            ) {

                Text(
                    "Clean Clipboard?"
                )
                .font(
                    .system(
                        size: 13,
                        weight: .semibold
                    )
                )


                Text(
                    "This will remove all items from your Zest clipboard history."
                )
                .font(
                    .system(
                        size: 9.5,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    Color.secondary
                )
                .multilineTextAlignment(
                    .center
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }


            HStack(
                spacing: 7
            ) {

                Button {

                    withAnimation(
                        .spring(
                            response: 0.20,
                            dampingFraction: 0.88
                        )
                    ) {

                        showingClearConfirmation =
                            false
                    }

                } label: {

                    Text(
                        "Cancel"
                    )
                    .font(
                        .system(
                            size: 10,
                            weight: .semibold
                        )
                    )
                    .frame(
                        maxWidth: .infinity
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
                            Color.white.opacity(0.22),
                            lineWidth: 0.7
                        )
                    }
                }
                .buttonStyle(
                    ZestPressButtonStyle()
                )
                .focusable(false)


                Button {

                    clipboardManager
                        .clearHistory()

                    selectedEntryIDs
                        .removeAll()


                    withAnimation(
                        .spring(
                            response: 0.20,
                            dampingFraction: 0.88
                        )
                    ) {

                        showingClearConfirmation =
                            false
                    }

                } label: {

                    Text(
                        "Clean"
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
                    .frame(
                        maxWidth: .infinity
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
                            accentColor.opacity(0.82)
                        )
                    }
                    .overlay {

                        RoundedRectangle(
                            cornerRadius: 9,
                            style: .continuous
                        )
                        .stroke(
                            Color.white.opacity(0.24),
                            lineWidth: 0.7
                        )
                    }
                }
                .buttonStyle(
                    ZestPressButtonStyle()
                )
                .focusable(false)
            }
        }
        .padding(15)
        .frame(
            width: 236
        )
        .background {
            confirmationGlassBody
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
    }


    // MARK: - Main Glass

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
                    endRadius: 170
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


    // MARK: - Confirmation Glass

    private var confirmationGlassBody: some View {

        ZStack {

            Color.clear
                .glassEffect(
                    .regular
                        .tint(
                            accentColor.opacity(0.045)
                        ),
                    in:
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                )


            RoundedRectangle(
                cornerRadius: 18,
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
                            location: 0.30
                        ),
                        .init(
                            color:
                                Color.clear,
                            location: 0.65
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
                cornerRadius: 18,
                style: .continuous
            )
            .fill(
                RadialGradient(
                    colors: [
                        accentColor.opacity(0.085),
                        Color.clear
                    ],
                    center:
                        UnitPoint(
                            x: 0.84,
                            y: 0.16
                        ),
                    startRadius: 0,
                    endRadius: 150
                )
            )


            RoundedRectangle(
                cornerRadius: 18,
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


    // MARK: - Helpers

    private func displayText(
        _ text: String
    ) -> String {

        text
            .replacingOccurrences(
                of: "\r\n",
                with: "\n"
            )
            .replacingOccurrences(
                of: "\t",
                with: " "
            )
    }


    private func iconName(
        for text: String
    ) -> String {

        let trimmed =
            text.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )


        if
            let url =
                URL(
                    string:
                        trimmed
                ),
            let scheme =
                url.scheme?
                    .lowercased(),
            scheme == "http"
                || scheme == "https"
        {
            return "link"
        }


        if text.contains("\n") {
            return "text.alignleft"
        }


        return "text.quote"
    }


    private func relativeTime(
        for date: Date
    ) -> String {

        let interval =
            Date()
                .timeIntervalSince(
                    date
                )


        if interval < 10 {
            return "now"
        }

        if interval < 60 {
            return "\(Int(interval))s"
        }

        if interval < 3_600 {
            return "\(Int(interval / 60))m"
        }

        if interval < 86_400 {
            return "\(Int(interval / 3_600))h"
        }


        return
            "\(Int(interval / 86_400))d"
    }
}


// MARK: - Preview

#Preview {

    ZStack {

        LinearGradient(
            colors: [
                Color.blue.opacity(0.10),
                Color.white,
                Color.orange.opacity(0.07),
                Color.purple.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )


        ZestClipboardPanel(
            clipboardManager:
                ClipboardHistoryManager(),
            accentColor:
                Color(
                    red: 1.00,
                    green: 0.35,
                    blue: 0.01
                )
        )
    }
    .frame(
        width: 520,
        height: 440
    )
}
