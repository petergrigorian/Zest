//
//  ZestSettingsView.swift
//  Zest
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers


private struct SliceAssemblyCenterPreferenceKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero

    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}


// MARK: - Settings Section

private enum ZestSettingsSection:
    String,
    CaseIterable,
    Identifiable {

    case general
    case menuBar
    case shortcuts
    case permissions
    case softwareUpdate
    case reset
    case about


    var id: String {
        rawValue
    }


    var title: String {

        switch self {

        case .general:
            return "General"

        case .menuBar:
            return "Menu Bar"

        case .shortcuts:
            return "Keyboard Shortcuts"

        case .permissions:
            return "Permissions & Startup"
            
        case .softwareUpdate:
            return "Software Update"

        case .reset:
            return "Reset"

        case .about:
            return "About"
        }
    }


    var symbol: String {

        switch self {

        case .general:
            return "slider.horizontal.3"

        case .menuBar:
            return "menubar.rectangle"

        case .shortcuts:
            return "command"

        case .permissions:
            return "checkmark.shield"
            
        case .softwareUpdate:
            return "arrow.triangle.2.circlepath"

        case .reset:
            return "arrow.counterclockwise"

        case .about:
            return "info.circle"
        }
    }
}


private struct CenterOnlySectorShape: Shape {
    let index: Int
    let count: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let startDeg: Double
        let endDeg: Double
        if count == 2 {
            startDeg = index == 0 ? 180 : 0
            endDeg = index == 0 ? 360 : 180
        } else {
            startDeg = -135 + Double(index) * 90
            endDeg = startDeg + 90
        }
        path.move(to: c)
        path.addArc(center: c, radius: r, startAngle: .degrees(startDeg), endAngle: .degrees(endDeg), clockwise: false)
        path.closeSubpath()
        return path
    }
}


private struct CenterOnlyRingDropDelegate: DropDelegate {
    let diameter: CGFloat
    let count: Int
    @Binding var targetIndex: Int?
    let perform: (Int) -> Void
    let cleanup: () -> Void

    private func index(at location: CGPoint) -> Int {
        let dx = location.x - diameter / 2
        let dy = location.y - diameter / 2
        if count == 2 { return dy < 0 ? 0 : 1 }
        let angle = atan2(dy, dx) * 180 / .pi
        if angle >= -135 && angle < -45 { return 0 }
        if angle >= -45 && angle < 45 { return 1 }
        if angle >= 45 && angle < 135 { return 2 }
        return 3
    }

    func dropEntered(info: DropInfo) {
        targetIndex = index(at: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let next = index(at: info.location)
        if targetIndex != next {
            withAnimation(.spring(response: 0.20, dampingFraction: 0.82)) {
                targetIndex = next
            }
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        withAnimation(.easeOut(duration: 0.12)) { targetIndex = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = index(at: info.location)
        perform(target)
        cleanup()
        return true
    }
}


// MARK: - Shortcut Recorder

struct ZestShortcutRecorderRow: View {
    let title: String
    @Binding var shortcut: ZestKeyboardShortcut

    @State private var draft: ZestKeyboardShortcut
    @State private var isRecording = false
    @State private var monitor: Any?

    init(_ title: String, shortcut: Binding<ZestKeyboardShortcut>) {
        self.title = title
        self._shortcut = shortcut
        self._draft = State(initialValue: shortcut.wrappedValue)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
            Spacer()

            Button {
                beginRecording()
            } label: {
                Text(isRecording ? "Press keys…" : draft.displayString)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
                    .frame(minWidth: 112)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(isRecording ? 0.09 : 0.05))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isRecording ? Color.accentColor.opacity(0.75) : Color.white.opacity(0.10), lineWidth: 0.8)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        }
        .onDisappear { stopRecording() }
        .onChange(of: shortcut) { _, newValue in
            if !isRecording { draft = newValue }
        }
    }

    private func beginRecording() {
        stopRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let recorded = ZestKeyboardShortcut(
                keyCode: event.keyCode,
                command: flags.contains(.command),
                option: flags.contains(.option),
                control: flags.contains(.control),
                shift: flags.contains(.shift)
            )
            draft = recorded
            shortcut = recorded
            isRecording = false
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        isRecording = false
    }
}


// MARK: - Settings View

struct ZestSettingsView: View {

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject
    var settingsManager:
        ZestSettingsManager

    // Reuse the production Feature Placement editor outside the Settings shell
    // (currently used by first-run onboarding). This deliberately renders the
    // exact same editor instead of maintaining a second approximation.
    var layoutOnly: Bool = false
    var onboardingLayoutMode: Bool = false

    // Performance-only signal from the parent Settings document.
    // While the document is physically scrolling, the embedded editor should
    // not publish geometry state or keep drag interaction active.
    var parentScrollActive: Bool = false


    @State
    private var selectedSection:
        ZestSettingsSection =
            .general

    // This changes only when scrolling starts/stops; scroll position itself is
    // deliberately not stored in SwiftUI state.
    @State
    private var settingsScrollActive =
        false


    @State
    private var showResetConfirmation =
        false


    // These two layouts do not have runtime renderers yet,
    // so their assignments remain editor drafts for now.

    @State
    private var centerFeature:
        ZestFeature =
            .emoji

    @State private var centerOnlySlideDirection: CGFloat = 1


    private var tripleFeatures: [ZestFeature] {
        get { settingsManager.tripleFeatures }
        nonmutating set { settingsManager.tripleFeatures = newValue }
    }


    // MARK: - Physical Slice Drag State

    @State
    private var draggedSliceFeature:
        ZestFeature?

    @State
    private var draggedSliceLocation:
        CGPoint = .zero

    @State
    private var magneticSliceSlot:
        ZestSliceSlot?

    @State
    private var isDraggingSlicePiece =
        false

    @State
    private var sliceAssemblyCenter:
        CGPoint = .zero

    @State
    private var sliceDropBounce =
        false


    // MARK: - Center Only Physical Drag State

    @State private var centerOnlyDraggedFeature: ZestFeature?
    @State private var centerOnlyDraggedSourceIndex: Int?
    @State private var centerOnlyMagneticTargetIndex: Int?

    @State private var actionSetupSlot: ZestSliceSlot?
    @State private var actionSetupCenterIndex: Int?
    @State private var actionSetupCenterCount: Int?
    @State private var actionSetupFeature: ZestFeature?
    @State private var availableApplications: [ZestApplicationTarget] = []
    @State private var availableShortcuts: [String] = []
    @State private var selectedApplicationPath: String = ""
    @State private var selectedShortcutName: String = ""
    @State private var actionSetupVisible = false
    @State private var actionSelectorExpanded = true

    @State private var showLayoutSavePrompt = false
    @State private var showIncompleteLayoutPrompt = false

    @State private var editSnapshotCenterFeature: ZestFeature?
    @State private var editSnapshotTripleFeatures: [ZestFeature]?

    // MARK: - Menu Bar Dashboard Editor Draft
    @State private var menuBarDraftBlocks: [ZestMenuBarBlock] = [.monitors, .pinnedActions]
    @State private var menuBarDraftPinnedFeatures: [ZestFeature] = [.size, .font, .clipboard, .emoji, .symbols]
    @State private var menuBarEditorLoaded = false
    @State private var menuBarDropPulse = false


    private var accentColor: Color {
        settingsManager.accentColor
    }


    // MARK: Body

    var body: some View {

        Group {
            if layoutOnly {
                // IMPORTANT: this is the production Settings editor itself.
                // Onboarding therefore inherits its exact tile geometry, drag
                // behaviour, sizing, swapping, Center Only modes and controls.
                layoutEditor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    sidebar

                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 1)

                    detail
                }
                .frame(minWidth: 1200, minHeight: 700)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { settingsBackground }
                .ignoresSafeArea()
                .background(
                    ZestSettingsWindowConfigurator()
                        .frame(width: 0, height: 0)
                )
            }
        }
        .overlay {
            if actionSetupFeature != nil {
                actionSetupOverlay
                    .opacity(actionSetupVisible ? 1 : 0)
                    .transition(.opacity)
                    .zIndex(5000)
            }

            if showLayoutSavePrompt {
                layoutSaveConfirmationOverlay
                    .transition(.opacity)
                    .zIndex(6000)
            }

            if showIncompleteLayoutPrompt {
                incompleteLayoutOverlay
                    .transition(.opacity)
                    .zIndex(6000)
            }
        }
        .alert(
            "Reset Zest?",
            isPresented:
                $showResetConfirmation
        ) {

            Button(
                "Cancel",
                role: .cancel
            ) {
            }

            Button(
                "Reset",
                role: .destructive
            ) {

                settingsManager
                    .resetAll()
            }

        } message: {

            Text(
                "This restores Zest's appearance, layout, shortcut and startup preference to their defaults."
            )
        }
        .onAppear {
            if !centerOnlyModes.contains(settingsManager.centerOnlyPage) {
                settingsManager.centerOnlyPage = "language"
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .zestSettingsCloseRequested
            )
        ) { _ in
            handleSettingsCloseRequest()
        }
        .onReceive(NotificationCenter.default.publisher(for: .zestOnboardingCommitLayout)) { _ in
            guard onboardingLayoutMode, settingsManager.isLayoutEditing else { return }
            saveLayoutChanges()
        }
        .onChange(of: actionSetupFeature) { _, feature in
            guard onboardingLayoutMode else { return }
            NotificationCenter.default.post(name: .zestOnboardingActionOverlayChanged, object: feature != nil)
        }
        .onDisappear {
            if onboardingLayoutMode {
                NotificationCenter.default.post(name: .zestOnboardingActionOverlayChanged, object: false)
            }
        }
    }


    // MARK: - Layout Save / Cancel

    private var layoutIsComplete: Bool {
        switch settingsManager.formFactor {
        case .orangeSlice:
            return settingsManager.isOrangeSliceComplete
        case .centerOnly:
            switch settingsManager.centerOnlyPage {
            case "twoFeature": return settingsManager.centerOnlyTwoFeatures.count == 2 && !settingsManager.centerOnlyTwoFeatures.contains(.empty)
            case "fourFeature": return settingsManager.centerOnlyFourFeatures.count == 4 && !settingsManager.centerOnlyFourFeatures.contains(.empty)
            default: return true
            }
        case .tripleSquare:
            return tripleFeatures.count == 3 && !tripleFeatures.contains(.empty)
        }
    }


    private func beginLayoutEditIfNeeded() {
        guard !settingsManager.isLayoutEditing else { return }

        editSnapshotCenterFeature = centerFeature
        editSnapshotTripleFeatures = tripleFeatures
        settingsManager.beginLayoutEditing()
    }


    private func saveLayoutChanges() {
        guard layoutIsComplete else {
            withAnimation(.easeInOut(duration: 0.18)) {
                showIncompleteLayoutPrompt = true
            }
            return
        }

        settingsManager.commitLayoutEditing()
        editSnapshotCenterFeature = nil
        editSnapshotTripleFeatures = nil

        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
    }


    private func cancelLayoutChanges() {
        if let value = editSnapshotCenterFeature {
            centerFeature = value
        }

        if let value = editSnapshotTripleFeatures {
            tripleFeatures = value
        }

        settingsManager.cancelLayoutEditing()
        editSnapshotCenterFeature = nil
        editSnapshotTripleFeatures = nil
    }


    private func handleSettingsCloseRequest() {
        guard settingsManager.isLayoutEditing else {
            NotificationCenter.default.post(
                name: .zestSettingsForceClose,
                object: nil
            )
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            if layoutIsComplete {
                showLayoutSavePrompt = true
            } else {
                showIncompleteLayoutPrompt = true
            }
        }
    }


    private var layoutSaveConfirmationOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.10))
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.10))
                        .frame(width: 48, height: 48)

                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                VStack(spacing: 5) {
                    Text("Save Layout Changes?")
                        .font(.system(size: 18, weight: .bold, design: .rounded))

                    Text("Your Zest layout has unsaved changes.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 9) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            showLayoutSavePrompt = false
                        }
                        cancelLayoutChanges()
                        NotificationCenter.default.post(
                            name: .zestSettingsForceClose,
                            object: nil
                        )
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Color.primary.opacity(0.045))
                            }
                    }
                    .buttonStyle(ZestPressButtonStyle())
                    .focusable(false)

                    Button {
                        saveLayoutChanges()
                        withAnimation(.easeInOut(duration: 0.16)) {
                            showLayoutSavePrompt = false
                        }
                        NotificationCenter.default.post(
                            name: .zestSettingsForceClose,
                            object: nil
                        )
                    } label: {
                        Text("Save")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(accentColor.opacity(0.84))
                            }
                    }
                    .buttonStyle(ZestPressButtonStyle())
                    .focusable(false)
                }
            }
            .padding(24)
            .frame(width: 360)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.clear)
                    .glassEffect(
                        .regular.tint(accentColor.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.30), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.18), radius: 26, y: 10)
        }
    }


    private var incompleteLayoutOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.10))
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.10))
                        .frame(width: 48, height: 48)

                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                VStack(spacing: 5) {
                    Text("Complete the Ring")
                        .font(.system(size: 18, weight: .bold, design: .rounded))

                    Text("Fill every tile before saving this form factor.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showIncompleteLayoutPrompt = false
                    }
                } label: {
                    Text("OK")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(accentColor.opacity(0.84))
                        }
                }
                .buttonStyle(ZestPressButtonStyle())
                .focusable(false)
            }
            .padding(24)
            .frame(width: 360)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.clear)
                    .glassEffect(
                        .regular.tint(accentColor.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.30), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.18), radius: 26, y: 10)
        }
    }


    // MARK: - Configurable Action Setup

    private var unconfiguredActionSlots: Set<ZestSliceSlot> {
        Set(
            settingsManager.sliceAssignments.compactMap { slot, feature in
                guard (feature == .openShortcut || feature == .runShortcut),
                      !settingsManager.isConfigured(feature, in: slot)
                else { return nil }
                return slot
            }
        )
    }


    private func presentActionSetup(feature: ZestFeature, slot: ZestSliceSlot) {
        actionSetupFeature = feature
        actionSetupSlot = slot
        actionSetupVisible = false
        actionSelectorExpanded = true

        if feature == .openShortcut {
            availableApplications = discoverApplications()
            selectedApplicationPath = settingsManager.applicationTargets[slot]?.path
                ?? availableApplications.first?.path
                ?? ""
        } else {
            availableShortcuts = discoverShortcuts()
            selectedShortcutName = settingsManager.shortcutTargets[slot]?.name
                ?? availableShortcuts.first
                ?? ""
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.22)) {
                actionSetupVisible = true
            }
        }
    }


    private func presentCenterActionSetup(feature: ZestFeature, index: Int, count: Int) {
        actionSetupFeature = feature
        actionSetupSlot = nil
        actionSetupCenterIndex = index
        actionSetupCenterCount = count
        actionSetupVisible = false
        actionSelectorExpanded = true
        let key = settingsManager.centerActionKey(count: count, index: index)
        if feature == .openShortcut {
            availableApplications = discoverApplications()
            selectedApplicationPath = settingsManager.centerApplicationTargets[key]?.path ?? availableApplications.first?.path ?? ""
        } else {
            availableShortcuts = discoverShortcuts()
            selectedShortcutName = settingsManager.centerShortcutTargets[key]?.name ?? availableShortcuts.first ?? ""
        }
        DispatchQueue.main.async { withAnimation(.easeInOut(duration: 0.22)) { actionSetupVisible = true } }
    }

    private func dismissActionSetup() {
        withAnimation(.easeInOut(duration: 0.20)) {
            actionSetupVisible = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            actionSetupSlot = nil
            actionSetupCenterIndex = nil
            actionSetupCenterCount = nil
            actionSetupFeature = nil
            actionSelectorExpanded = true
        }
    }


    private func saveActionSetup() {
        guard let feature = actionSetupFeature else { return }
        beginLayoutEditIfNeeded()

        if let index = actionSetupCenterIndex, let count = actionSetupCenterCount {
            if feature == .openShortcut, let app = availableApplications.first(where: { $0.path == selectedApplicationPath }) {
                settingsManager.configureCenterApplication(app, count: count, index: index)
            } else if feature == .runShortcut, !selectedShortcutName.isEmpty {
                settingsManager.configureCenterShortcut(ZestShortcutTarget(name: selectedShortcutName), count: count, index: index)
            } else { return }
        } else if let slot = actionSetupSlot {
            if feature == .openShortcut, let app = availableApplications.first(where: { $0.path == selectedApplicationPath }) {
                settingsManager.configureApplication(app, for: slot)
            } else if feature == .runShortcut, !selectedShortcutName.isEmpty {
                settingsManager.configureShortcut(ZestShortcutTarget(name: selectedShortcutName), for: slot)
            } else { return }
        } else { return }

        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        dismissActionSetup()
    }


    private func discoverApplications() -> [ZestApplicationTarget] {
        let roots = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        var found: [String: ZestApplicationTarget] = [:]
        let fm = FileManager.default

        for root in roots {
            guard let urls = try? fm.contentsOfDirectory(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in urls where url.pathExtension.lowercased() == "app" {
                let bundle = Bundle(url: url)
                let display = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
                found[url.path] = ZestApplicationTarget(
                    name: display,
                    bundleIdentifier: bundle?.bundleIdentifier,
                    path: url.path
                )
            }
        }

        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }


    private func applicationCategory(for app: ZestApplicationTarget) -> String {
        guard let bundle = Bundle(path: app.path) else {
            return "Other"
        }

        let raw = bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String ?? ""

        let mapping: [(String, String)] = [
            ("productivity", "Productivity"),
            ("utilities", "Utilities"),
            ("developer-tools", "Developer"),
            ("graphics-design", "Creativity"),
            ("photography", "Creativity"),
            ("video", "Creativity"),
            ("music", "Music"),
            ("social-networking", "Social"),
            ("entertainment", "Entertainment"),
            ("games", "Games"),
            ("education", "Education"),
            ("finance", "Finance"),
            ("business", "Business"),
            ("news", "News"),
            ("travel", "Travel"),
            ("lifestyle", "Lifestyle")
        ]

        for (token, title) in mapping where raw.localizedCaseInsensitiveContains(token) {
            return title
        }

        return "Other"
    }


    private var groupedApplications: [(String, [ZestApplicationTarget])] {
        let grouped = Dictionary(grouping: availableApplications) {
            applicationCategory(for: $0)
        }

        let preferred = [
            "Productivity", "Creativity", "Utilities", "Developer",
            "Music", "Social", "Entertainment", "Games",
            "Education", "Business", "Finance", "News",
            "Travel", "Lifestyle", "Other"
        ]

        return preferred.compactMap { category in
            guard let apps = grouped[category], !apps.isEmpty else { return nil }
            return (category, apps)
        }
    }


    private func applicationIcon(for app: ZestApplicationTarget) -> NSImage {
        NSWorkspace.shared.icon(forFile: app.path)
    }


    private func discoverShortcuts() -> [String] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return text
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        } catch {
            print("🍊 SHORTCUT LIST ERROR → \(error.localizedDescription)")
            return []
        }
    }


    private var actionSetupOverlay: some View {
        ZStack {
            Rectangle()
                .fill(AnyShapeStyle(.ultraThinMaterial))
                .overlay(Color.black.opacity(onboardingLayoutMode ? 0.055 : 0.10))
                .ignoresSafeArea()
                .onTapGesture { }

            VStack(spacing: 16) {
                Image(
                    systemName:
                        actionSetupFeature == .openShortcut
                        ? "arrow.up.forward.app"
                        : "play.fill"
                )
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundStyle(accentColor)

                VStack(spacing: 5) {
                    Text(
                        actionSetupFeature == .openShortcut
                        ? "Select an Application"
                        : "Select a Shortcut"
                    )
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                    Text(
                        actionSetupFeature == .openShortcut
                        ? "Choose the application this Zest tile should open."
                        : "Choose the Apple Shortcut this Zest tile should run."
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                actionTargetSelector

                HStack(spacing: 9) {
                    Button {
                        dismissActionSetup()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Color.primary.opacity(0.045))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(Color.white.opacity(0.22), lineWidth: 0.7)
                            }
                    }
                    .buttonStyle(ZestPressButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .focusable(false)

                    Button {
                        saveActionSetup()
                    } label: {
                        Text("Save")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(accentColor.opacity(0.82))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(Color.white.opacity(0.24), lineWidth: 0.7)
                            }
                    }
                    .buttonStyle(ZestPressButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .focusable(false)
                    .disabled(
                        actionSetupFeature == .openShortcut
                        ? selectedApplicationPath.isEmpty
                        : selectedShortcutName.isEmpty
                    )
                }
                .frame(width: 390)
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
            .frame(width: 560)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.clear)
                    .glassEffect(
                        .regular.tint(accentColor.opacity(0.10)),
                        in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.32), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.18), radius: 28, y: 12)
        }
        // In onboarding this editor is embedded inside the setup page. Expand
        // the material scrim beyond the editor's own bounds so application /
        // Shortcut selection blurs the complete onboarding window rather than
        // producing a cropped rectangular blur.
        .frame(
            width: onboardingLayoutMode ? 1040 : nil,
            height: onboardingLayoutMode ? 700 : nil
        )
        .offset(y: onboardingLayoutMode ? -52 : 0)
    }


    @ViewBuilder
    private var actionTargetSelector: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                    actionSelectorExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    if actionSetupFeature == .openShortcut,
                       let app = availableApplications.first(where: { $0.path == selectedApplicationPath }) {
                        Image(nsImage: applicationIcon(for: app))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "command")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .foregroundStyle(accentColor)
                    }

                    Text(
                        actionSetupFeature == .openShortcut
                        ? (availableApplications.first(where: { $0.path == selectedApplicationPath })?.name
                           ?? "Choose an application")
                        : (selectedShortcutName.isEmpty ? "Choose a shortcut" : selectedShortcutName)
                    )
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.88))
                    .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees(actionSelectorExpanded ? 180 : 0))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 0.7)
                }
            }
            .buttonStyle(ZestPressButtonStyle())
            .focusable(false)

            if actionSelectorExpanded {
                ScrollView {
                    if actionSetupFeature == .openShortcut {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(groupedApplications, id: \.0) { category, apps in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(category.uppercased())
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundStyle(Color.secondary)
                                        .tracking(1.1)

                                    LazyVGrid(
                                        columns: Array(
                                            repeating: GridItem(.flexible(), spacing: 7),
                                            count: 5
                                        ),
                                        spacing: 8
                                    ) {
                                        ForEach(apps, id: \.path) { app in
                                            actionApplicationCell(app)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(12)
                    } else if availableShortcuts.isEmpty {
                        Text("No Apple Shortcuts were found.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 100)
                    } else {
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: 7),
                                count: 5
                            ),
                            spacing: 8
                        ) {
                            ForEach(availableShortcuts, id: \.self) { shortcut in
                                actionShortcutCell(shortcut)
                            }
                        }
                        .padding(12)
                    }
                }
                .frame(height: 230)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: 460)
    }


    private func actionApplicationCell(_ app: ZestApplicationTarget) -> some View {
        let selected = selectedApplicationPath == app.path

        return Button {
            selectedApplicationPath = app.path
        } label: {
            VStack(spacing: 5) {
                Image(nsImage: applicationIcon(for: app))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)

                Text(app.name)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? accentColor.opacity(0.16) : Color.primary.opacity(0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        selected ? accentColor.opacity(0.72) : Color.white.opacity(0.14),
                        lineWidth: selected ? 1.2 : 0.7
                    )
            }
        }
        .buttonStyle(ZestPressButtonStyle())
        .focusable(false)
    }


    private func actionShortcutCell(_ shortcut: String) -> some View {
        let selected = selectedShortcutName == shortcut

        return Button {
            selectedShortcutName = shortcut
        } label: {
            VStack(spacing: 5) {
                // Apple's public `shortcuts` command exposes names/identifiers,
                // but not the user-selected glyph metadata. Keep this cell ready
                // for a real glyph when Apple exposes it instead of inventing one.
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentColor.opacity(selected ? 0.22 : 0.10))
                        .frame(width: 34, height: 34)

                    Image(systemName: "command")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(accentColor)
                }

                Text(shortcut)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? accentColor.opacity(0.16) : Color.primary.opacity(0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        selected ? accentColor.opacity(0.72) : Color.white.opacity(0.14),
                        lineWidth: selected ? 1.2 : 0.7
                    )
            }
        }
        .buttonStyle(ZestPressButtonStyle())
        .focusable(false)
    }


    // MARK: - Sidebar

    private var sidebar:
        some View {

        VStack(
            alignment: .leading,
            spacing: 8
        ) {

            // Space for floating macOS traffic lights.

            Color.clear
                .frame(
                    height: 38
                )


            VStack(
                alignment: .leading,
                spacing: 3
            ) {

                Text(
                    "Zest"
                )
                .font(
                    .system(
                        size: 24,
                        weight: .bold,
                        design: .rounded
                    )
                )

                Text(
                    "Settings"
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
            }
            .padding(
                .horizontal,
                10
            )
            .padding(
                .bottom,
                14
            )


            ForEach(
                ZestSettingsSection.allCases
            ) { section in

                sidebarButton(
                    section
                )
            }


            Spacer()


            HStack(
                spacing: 7
            ) {

                Circle()
                    .fill(
                        accentColor
                    )
                    .frame(
                        width: 8,
                        height: 8
                    )

                Text(
                    "Zest"
                )
                .font(
                    .system(
                        size: 10,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    Color.secondary
                )
            }
            .padding(
                .horizontal,
                10
            )
            .padding(
                .bottom,
                8
            )
        }
        .padding(
            .horizontal,
            14
        )
        .padding(
            .bottom,
            14
        )
        .frame(
            width: 220
        )
        .background {

            ZStack {

                Color.primary.opacity(
                    0.022
                )

                LinearGradient(
                    colors: [
                        accentColor.opacity(
                            0.08
                        ),
                        Color.clear
                    ],
                    startPoint:
                        .topLeading,
                    endPoint:
                        .bottomTrailing
                )
            }
        }
    }


    private func sidebarButton(
        _ section:
            ZestSettingsSection
    ) -> some View {

        let selected =
            selectedSection
            == section


        return Button {

            withAnimation(
                .spring(
                    response: 0.20,
                    dampingFraction: 0.88
                )
            ) {

                selectedSection =
                    section
            }

        } label: {

            HStack(
                spacing: 10
            ) {

                Image(
                    systemName:
                        section.symbol
                )
                .font(
                    .system(
                        size: 13,
                        weight: .semibold
                    )
                )
                .frame(
                    width: 18
                )

                Text(
                    section.title
                )
                .font(
                    .system(
                        size: 12,
                        weight:
                            selected
                            ? .semibold
                            : .medium
                    )
                )

                Spacer()
            }
            .foregroundStyle(
                selected
                ? Color.primary
                : Color.secondary
            )
            .padding(
                .horizontal,
                10
            )
            .frame(
                height: 40
            )
            .background {

                RoundedRectangle(
                    cornerRadius: 11,
                    style: .continuous
                )
                .fill(
                    selected
                    ? accentColor.opacity(
                        0.16
                    )
                    : Color.clear
                )
            }
            .overlay {

                if selected {

                    RoundedRectangle(
                        cornerRadius: 11,
                        style: .continuous
                    )
                    .stroke(
                        accentColor.opacity(
                            0.38
                        ),
                        lineWidth: 0.8
                    )
                }
            }
        }
        .buttonStyle(
            .plain
        )
        .focusable(false)
    }


    // MARK: - Detail

    @ViewBuilder
    private var detail:
        some View {

        ScrollView(
            .vertical,
            showsIndicators: false
        ) {

            VStack(
                alignment: .leading,
                spacing: 18
            ) {

                Color.clear
                    .frame(
                        height: 22
                    )


                switch selectedSection {

                case .general:
                    generalSection

                case .menuBar:
                    menuBarSection

                case .shortcuts:
                    shortcutsSection

                case .permissions:
                    permissionsSection
                    
                case .softwareUpdate:
                    ZestUpdateSettingsView(
                        accentColor: accentColor
                    )

                case .reset:
                    resetSection

                case .about:
                    aboutSection
                }
            }
            .padding(
                .horizontal,
                28
            )
            .padding(
                .bottom,
                28
            )
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        // The production tile editor lives inside this ScrollView, unlike the
        // onboarding copy. Once a tile drag/edit begins, allowing the parent
        // scroll view to compete for pointer deltas causes extra layout passes
        // and visible drag jitter. Freeze scrolling only for the active General
        // layout edit; Save/Cancel restores normal scrolling immediately.
        .scrollDisabled(selectedSection == .general && settingsManager.isLayoutEditing)
        .onScrollPhaseChange { _, phase in
            let active =
                phase != .idle

            guard
                settingsScrollActive != active
            else {
                return
            }

            var transaction =
                Transaction()

            transaction.animation = nil
            transaction.disablesAnimations = true

            withTransaction(
                transaction
            ) {
                settingsScrollActive =
                    active
            }
        }
        .transaction { transaction in
            if settingsScrollActive {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }


    // MARK: - Menu Bar

    private var menuBarSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageHeader("Menu Bar", subtitle: "Build the dashboard directly in the live widget preview.")

            settingsCard(title: "Menu Bar Dashboard", subtitle: "Drag dashboard blocks and actions from the toolkit into the exact menu-bar widget on the right. Save when the layout is ready.") {
                VStack(alignment: .leading, spacing: 12) {
                    // Match the Orange Slice editor: persistence controls live in the
                    // upper-right corner and never steal vertical space from the toolkit.
                    HStack(spacing: 8) {
                        Spacer()

                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { resetMenuBarEditorDraftToDefaults() }
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        } label: {
                            Label("Revert", systemImage: "arrow.uturn.backward")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background {
                                    Capsule()
                                        .fill(accentColor.opacity(0.075))
                                        .glassEffect(.regular.tint(accentColor.opacity(0.07)), in: Capsule())
                                        .overlay { Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.7) }
                                        .shadow(color: .black.opacity(0.06), radius: 3, y: 1.5)
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)

                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                menuBarDraftBlocks.removeAll()
                            }
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        } label: {
                            Label("Remove All", systemImage: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background {
                                    Capsule()
                                        .fill(accentColor.opacity(0.075))
                                        .glassEffect(.regular.tint(accentColor.opacity(0.07)), in: Capsule())
                                        .overlay { Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.7) }
                                        .shadow(color: .black.opacity(0.06), radius: 3, y: 1.5)
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .disabled(menuBarDraftBlocks.isEmpty)

                        Button { saveMenuBarEditorDraft() } label: {
                            Label("Save", systemImage: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 14)
                                .frame(height: 30)
                                .background { Capsule().fill(accentColor.opacity(0.82)) }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .disabled(menuBarDraftBlocks.isEmpty)
                    }

                    HStack(alignment: .top, spacing: 26) {
                    // Left: toolkit and persistence controls.
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 14) {
                            ZestMenuBarGlyph(color: settingsManager.accent.palette.primary)
                                .frame(width: 28, height: 28)
                                .padding(7)
                                .background { Circle().fill(settingsManager.accent.palette.primary.opacity(0.08)) }

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Show Zest in Menu Bar").font(.system(size: 12, weight: .semibold))
                                Text("Click the slice in the menu bar to open the Zest dashboard.")
                                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $settingsManager.showInMenuBar)
                                .labelsHidden().toggleStyle(.switch)
                        }

                        Divider().opacity(0.55)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("DASHBOARD BLOCKS")
                                .font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundStyle(.secondary)
                            Text("Drag either complete block into the widget preview. The toolkit uses the same geometry as the active dashboard.")
                                .font(.system(size: 10.5)).foregroundStyle(.secondary)

                            menuBarMonitorToolkitPiece
                                .allowsHitTesting(
                                    !settingsScrollActive
                                )

                            menuBarPinnedToolkitPiece
                                .allowsHitTesting(
                                    !settingsScrollActive
                                )
                        }

                        if menuBarDraftBlocks.contains(.pinnedActions) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("PINNED ACTIONS")
                                    .font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundStyle(.secondary)
                                Text("Drag any available action onto one of the five tiles in the live preview.")
                                    .font(.system(size: 10.5)).foregroundStyle(.secondary)

                                LazyVGrid(
                                    columns: Array(repeating: GridItem(.fixed(46), spacing: 9), count: 5),
                                    alignment: .leading,
                                    spacing: 10
                                ) {
                                    ForEach(ZestFeature.allCases.filter { $0 != .empty }) { feature in
                                        menuBarFeaturePalettePiece(feature)
                                    }
                                }
                                .frame(width: 278, alignment: .leading)
                                .allowsHitTesting(
                                    !settingsScrollActive
                                )
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    // Right: the editor IS the exact dashboard rendering.
                    VStack(alignment: .leading, spacing: 10) {
                        Text("LIVE WIDGET")
                            .font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundStyle(.secondary)
                        Text("Drag blocks and actions directly into the dashboard.")
                            .font(.system(size: 10.5)).foregroundStyle(.secondary)

                        ZestMenuBarSettingsPreview(
                            settingsManager: settingsManager,
                            blocks: $menuBarDraftBlocks,
                            pinnedFeatures: $menuBarDraftPinnedFeatures
                        )
                        .frame(width: 345, alignment: .topLeading)
                        .allowsHitTesting(
                            !settingsScrollActive
                        )
                    }
                    .frame(width: 405, alignment: .topLeading)
                    }
                }
            }
        }
        .onAppear {
            if !menuBarEditorLoaded { loadMenuBarEditorDraft(); menuBarEditorLoaded = true }
        }
    }

    private var menuBarMonitorToolkitPiece: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Monitors", systemImage: "waveform.path.ecg")
                    .font(.system(size: 10.5, weight: .bold))
                Spacer()
                Text(menuBarDraftBlocks.contains(.monitors) ? "IN WIDGET" : "DRAG TO WIDGET")
                    .font(.system(size: 7.5, weight: .bold)).tracking(0.5).foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
                ZestMonitorCard(title: "Storage", value: 0.81, history: menuBarToolkitHistoryA, symbol: "internaldrive", palette: settingsManager.accent.palette, colors: settingsManager.accent.displayColors)
                ZestMonitorCard(title: "Memory", value: 0.67, history: menuBarToolkitHistoryB, symbol: "memorychip", palette: settingsManager.accent.palette, colors: settingsManager.accent.displayColors)
                ZestMonitorCard(title: "CPU", value: 0.09, history: menuBarToolkitHistoryC, symbol: "cpu", palette: settingsManager.accent.palette, colors: settingsManager.accent.displayColors)
            }
            .scaleEffect(0.76, anchor: .topLeading)
            .frame(width: 252, height: 51, alignment: .topLeading)
        }
        .padding(10)
        .frame(width: 278, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accentColor.opacity(0.055))
                .glassEffect(.regular.tint(accentColor.opacity(0.07)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.24), lineWidth: 0.7) }
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
        .opacity(menuBarDraftBlocks.contains(.monitors) ? 0.55 : 1)
        .draggable("menublock:\(ZestMenuBarBlock.monitors.rawValue)") { menuBarBlockDragPreview(.monitors) }
    }

    private var menuBarPinnedToolkitPiece: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Pinned Actions", systemImage: "square.grid.3x1.folder.badge.plus")
                    .font(.system(size: 10.5, weight: .bold))
                Spacer()
                Text(menuBarDraftBlocks.contains(.pinnedActions) ? "IN WIDGET" : "DRAG TO WIDGET")
                    .font(.system(size: 7.5, weight: .bold)).tracking(0.5).foregroundStyle(.secondary)
            }
            HStack(spacing: 5) {
                ForEach(Array(menuBarDraftPinnedFeatures.enumerated()), id: \.offset) { index, feature in
                    VStack(spacing: 3) {
                        ZestMenuFeatureTile(feature: feature, palette: settingsManager.accent.palette, accent: settingsManager.accentColor(at: index))
                            .scaleEffect(0.66)
                            .frame(width: 38, height: 38)
                        Text(feature == .settings ? "Show Zest" : feature.title).font(.system(size: 7, weight: .medium)).lineLimit(1)
                    }
                    .frame(width: 45)
                }
            }
        }
        .padding(10)
        .frame(width: 278, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accentColor.opacity(0.055))
                .glassEffect(.regular.tint(accentColor.opacity(0.07)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.24), lineWidth: 0.7) }
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
        .opacity(menuBarDraftBlocks.contains(.pinnedActions) ? 0.55 : 1)
        .draggable("menublock:\(ZestMenuBarBlock.pinnedActions.rawValue)") { menuBarBlockDragPreview(.pinnedActions) }
    }

    private var menuBarToolkitHistoryA: [Double] { [0.58,0.58,0.60,0.61,0.64,0.68,0.70,0.70,0.70,0.70,0.70,0.70] }
    private var menuBarToolkitHistoryB: [Double] { [0.55,0.56,0.56,0.58,0.60,0.63,0.65,0.67,0.67,0.67,0.67,0.67] }
    private var menuBarToolkitHistoryC: [Double] { [0.08,0.07,0.09,0.12,0.36,0.16,0.10,0.08,0.10,0.08,0.09,0.08] }

    private func menuBarBlockDragPreview(_ block: ZestMenuBarBlock) -> some View {
        HStack(spacing: 8) {
            Image(systemName: block.systemImage)
            Text(block.title).font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, 14).frame(height: 46)
        .background { RoundedRectangle(cornerRadius: 13).fill(accentColor.opacity(0.72)).shadow(radius: 8, y: 4) }
    }

    private func menuBarFeaturePalettePiece(_ feature: ZestFeature) -> some View {
        VStack(spacing: 4) {
            ZestMenuFeatureTile(feature: feature, palette: settingsManager.accent.palette, accent: accentColor)
                .scaleEffect(0.66)
                .frame(width: 38, height: 38)
            Text(feature == .settings ? "Show Zest" : feature.title)
                .font(.system(size: 7, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(width: 45, height: 55)
        .draggable("menufeature:\(feature.rawValue)") {
            VStack(spacing: 4) {
                ZestMenuFeatureTile(feature: feature, palette: settingsManager.accent.palette, accent: accentColor)
                Text(feature.title).font(.system(size: 8, weight: .bold))
            }
            .padding(6)
        }
    }

    private func loadMenuBarEditorDraft() {
        menuBarDraftBlocks = settingsManager.menuBarBlocks
        menuBarDraftPinnedFeatures = settingsManager.menuBarPinnedFeatures
    }

    /// Factory dashboard used by Revert: monitors + the original five Zest actions.
    /// This intentionally does not read the last saved draft. Save remains explicit.
    private func resetMenuBarEditorDraftToDefaults() {
        menuBarDraftBlocks = [.monitors, .pinnedActions]
        menuBarDraftPinnedFeatures = [.size, .font, .clipboard, .emoji, .symbols]
    }

    private func saveMenuBarEditorDraft() {
        guard !menuBarDraftBlocks.isEmpty else { return }
        settingsManager.menuBarBlocks = menuBarDraftBlocks
        settingsManager.menuBarPinnedFeatures = menuBarDraftPinnedFeatures
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    // MARK: - General

    private var generalSection:
        some View {

        VStack(
            alignment: .leading,
            spacing: 18
        ) {

            pageHeader(
                "General",
                subtitle:
                    "Customize how Zest looks and behaves."
            )


            settingsCard(
                title:
                    "Accent Color",
                subtitle:
                    "Choose the flavor used throughout Zest."
            ) {

                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(
                                minimum: 104
                            ),
                            spacing: 10
                        )
                    ],
                    spacing: 10
                ) {

                    ForEach(
                        ZestAccent.allCases
                    ) { accent in

                        accentButton(
                            accent
                        )
                    }
                }
                // The accent palette is visually static while the General page scrolls.
                // Flatten it into one compositor surface so its individual shadows and
                // translucent layers are not re-composited for every scroll tick.
                .drawingGroup(opaque: false, colorMode: .nonLinear)
            }


            settingsCard(
                title:
                    "Form Factor",
                subtitle:
                    "Choose the shape Zest will use when opened."
            ) {

                HStack(
                    spacing: 12
                ) {

                    formFactorCard(
                        .orangeSlice
                    )
                    
                    formFactorCard(
                        .centerOnly
                    )

                    formFactorCard(
                        .tripleSquare
                    )
                }
                // Keep Zest previews live. Liquid Glass needs access to the real
                // backdrop; rasterizing this subtree makes rear/translucent faces
                // resolve as opaque gray. The cheaper accent palette above remains
                // cached, but Zest itself is never flattened.
            }


            settingsCard(
                title:
                    "Feature Placement",
                subtitle:
                    "Drag features onto the positions in the preview."
            ) {

                // PERFORMANCE PASS 7:
                // Host Feature Placement in its own ZestSettingsView instance, using
                // the exact same layout-only path that makes onboarding so smooth.
                //
                // The important part is state ownership: all transient drag state
                // (pointer location, magnetic slot, drag visibility, drop bounce and
                // assembly geometry) now belongs to this child view instance instead
                // of the full Settings shell. Pointer updates therefore invalidate the
                // editor subtree rather than the sidebar + General document + cards.
                //
                // This is still the production editor -- no visual recreation and no
                // simulated glass. The shared settingsManager keeps committed layout
                // state synchronized with the surrounding Settings window.
                ZestSettingsView(
                    settingsManager: settingsManager,
                    layoutOnly: true,
                    onboardingLayoutMode: false,
                    parentScrollActive:
                        settingsScrollActive
                )
                .frame(
                    maxWidth: .infinity,
                    minHeight: 340
                )
                .allowsHitTesting(
                    !settingsScrollActive
                )
            }
        }
    }


    // MARK: - Accent

    private func accentButton(
        _ accent:
            ZestAccent
    ) -> some View {

        let selected =
            settingsManager.accent
            == accent

        let palette =
            accent.palette


        return Button {

            withAnimation(
                .spring(
                    response: 0.18,
                    dampingFraction: 0.86
                )
            ) {

                settingsManager.accent =
                    accent
            }

        } label: {

            VStack(
                spacing: 7
            ) {

                Circle()
                    .fill(
                        LinearGradient(
                            colors: accent.displayColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(
                        width: 32,
                        height: 32
                    )
                    .overlay {

                        Circle()
                            .stroke(
                                Color.white.opacity(
                                    selected
                                    ? 0.72
                                    : 0.25
                                ),
                                lineWidth:
                                    selected
                                    ? 2
                                    : 0.8
                            )
                    }
                    .shadow(
                        color:
                            palette.primary.opacity(
                                selected
                                ? 0.34
                                : 0.12
                            ),
                        radius:
                            selected
                            ? 7
                            : 3
                    )


                Text(
                    accent.title
                )
                .font(
                    .system(
                        size: 10,
                        weight:
                            selected
                            ? .semibold
                            : .medium
                    )
                )
            }
            .frame(
                maxWidth: .infinity
            )
            .padding(
                .vertical,
                10
            )
            .background {

                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
                .fill(
                    selected
                    ? palette.primary.opacity(
                        0.13
                    )
                    : Color.primary.opacity(
                        0.025
                    )
                )
            }
            .overlay {

                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
                .stroke(
                    selected
                    ? palette.primary.opacity(
                        0.42
                    )
                    : Color.white.opacity(
                        0.12
                    ),
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(
            .plain
        )
        .focusable(false)
    }


    // MARK: - Form Factor Cards

    private func formFactorCard(
        _ factor:
            ZestFormFactor
    ) -> some View {

        let selected =
            settingsManager.formFactor
            == factor


        return Button {

            beginLayoutEditIfNeeded()

            withAnimation(
                .spring(
                    response: 0.22,
                    dampingFraction: 0.86
                )
            ) {

                settingsManager.formFactor =
                    factor
            }

        } label: {

            VStack(
                spacing: 10
            ) {

                Group {

                    switch factor {

                    case .centerOnly:
                        miniCenterPreview

                    case .orangeSlice:
                        miniSlicePreview

                    case .tripleSquare:
                        miniTriplePreview
                    }
                }
                .frame(
                    height: 82
                )


                VStack(
                    spacing: 3
                ) {

                    Text(
                        factor.title
                    )
                    .font(
                        .system(
                            size: 11,
                            weight: .semibold
                        )
                    )

                    Text(
                        factor.subtitle
                    )
                    .font(
                        .system(
                            size: 9,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(
                        Color.secondary
                    )
                }
            }
            .frame(
                maxWidth: .infinity
            )
            .padding(12)
            .background {

                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
                .fill(
                    selected
                    ? accentColor.opacity(
                        0.13
                    )
                    : Color.primary.opacity(
                        0.025
                    )
                )
            }
            .overlay {

                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
                .stroke(
                    selected
                    ? accentColor.opacity(
                        0.48
                    )
                    : Color.white.opacity(
                        0.12
                    ),
                    lineWidth:
                        selected
                        ? 1.1
                        : 0.8
                )
            }
            .shadow(
                color:
                    selected
                    ? accentColor.opacity(
                        0.12
                    )
                    : Color.clear,
                radius: 10
            )
        }
        .buttonStyle(
            .plain
        )
        .focusable(false)
    }


    private var miniCenterPreview: some View {
        ZStack {
            Capsule()
                .fill(settingsManager.accentDeepColor.opacity(0.055))
                .frame(width: 104, height: 31)
                .glassEffect(.regular.tint(accentColor.opacity(0.12)), in: Capsule())
                .overlay {
                    Capsule().stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.58),
                                accentColor.opacity(0.18),
                                settingsManager.accentDeepColor.opacity(0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
                }

            HStack(spacing: 70) {
                Image(systemName: "chevron.left")
                Image(systemName: "chevron.right")
            }
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(Color.primary.opacity(0.66))

            Circle()
                .fill(settingsManager.accentDeepColor.opacity(0.045))
                .frame(width: 77, height: 77)

            Color.clear
                .frame(width: 74, height: 74)
                .glassEffect(.regular.tint(accentColor.opacity(0.26)), in: Circle())

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            settingsManager.accentHighlightColor.opacity(0.12),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.30, y: 0.18),
                        startRadius: 0,
                        endRadius: 42
                    )
                )
                .frame(width: 74, height: 74)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.90),
                            Color.white.opacity(0.28),
                            accentColor.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
                .frame(width: 74, height: 74)

            Text("EN")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .offset(y: -21)

            ZStack {
                Circle()
                    .fill(settingsManager.accentDeepColor.opacity(0.08))
                    .frame(width: 29, height: 29)

                Color.clear
                    .frame(width: 25, height: 25)
                    .glassEffect(.regular.tint(accentColor.opacity(0.25)), in: Circle())

                Image(systemName: "gearshape.fill")
                    .font(.system(size: 8.5, weight: .semibold))
            }

            Text("A   B   C")
                .font(.system(size: 4.2, weight: .semibold, design: .rounded))
                .offset(y: 23)
                .opacity(0.72)
        }
        .foregroundStyle(Color.primary.opacity(0.82))
        .shadow(color: .black.opacity(0.11), radius: 4, y: 2)
    }

    private var miniSlicePreview:
        some View {

        ZestMiniSlicePreview(
            accentColor:
                accentColor,
            accentHighlightColor:
                settingsManager
                    .accentHighlightColor,
            accentDeepColor:
                settingsManager
                    .accentDeepColor
        )
    }


    private var miniTriplePreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accentColor.opacity(0.08))
                .frame(width: 154, height: 58)
                .glassEffect(
                    .regular.tint(accentColor.opacity(0.10)),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.54),
                                    accentColor.opacity(0.14),
                                    settingsManager.accentDeepColor.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.7
                        )
                }

            HStack(spacing: 5) {
                ForEach(settingsManager.tripleFeatures.indices, id: \.self) { index in
                    let feature = settingsManager.tripleFeatures[index]

                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(accentColor.opacity(feature == .empty ? 0.06 : 0.22))
                        .frame(width: 43, height: 48)
                        .glassEffect(
                            .regular.tint(accentColor.opacity(feature == .empty ? 0.08 : 0.16)),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.white.opacity(0.24), lineWidth: 0.55)
                        }
                        .overlay {
                            if feature == .empty {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                    .opacity(0.35)
                            } else {
                                Image(systemName: feature.systemImage)
                                    .font(.system(size: 15, weight: .semibold))
                            }
                        }
                }
            }

            ZStack {
                Circle()
                    .fill(settingsManager.accentDeepColor.opacity(0.07))
                    .frame(width: 25, height: 25)
                    .glassEffect(.regular.tint(accentColor.opacity(0.10)), in: Circle())
                    .overlay {
                        Circle().stroke(Color.white.opacity(0.34), lineWidth: 0.55)
                    }

                Color.clear
                    .frame(width: 19, height: 19)
                    .glassEffect(.regular.tint(accentColor.opacity(0.23)), in: Circle())

                Image(systemName: "gearshape.fill")
                    .font(.system(size: 6.5, weight: .semibold))
            }
            .offset(y: 30)
        }
        .foregroundStyle(Color.primary.opacity(0.82))
        .shadow(color: .black.opacity(0.09), radius: 3.5, y: 2)
    }

    // MARK: - Layout Editor

    private var layoutEditor:

        some View {

        layoutPreview

            .frame(

                maxWidth: .infinity,

                minHeight: 340

            )

    }


    // MARK: - Physical Feature Pieces

    // The loose pieces intentionally use the same 280 pt reference canvas
    // as the assembly shell. That means there is no "miniature" library
    // version anymore: this is literally one Zest tile pulled out of the
    // slice and parked at a neutral, upright rotation.
    private let loosePieceCanvas:
        CGFloat = 280

    // The tile is rendered at the exact 280 pt assembly scale, but its
    // layout footprint stays compact so the Settings window does not grow
    // or squeeze the other columns.
    private let loosePieceCell:
        CGFloat = 118


    private var featureLibrary:
        some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            HStack {
                Text("Available Pieces")
                    .font(
                        .system(
                            size: 12,
                            weight: .semibold
                        )
                    )

                Spacer()
            }


            LazyVGrid(
                columns: Array(
                    repeating: GridItem(
                        .fixed(loosePieceCell),
                        spacing: 4
                    ),
                    count: 4
                ),
                alignment: .leading,
                spacing: 8
            ) {

                ForEach(
                    Array(
                        ZestFeature
                            .allCases
                            .filter { $0 != .empty }
                            .enumerated()
                    ),
                    id: \.element.id
                ) { index, feature in

                    physicalFeaturePiece(
                        feature,
                        libraryIndex: index
                    )
                }
            }
        }
    }


    private func physicalFeaturePiece(
        _ feature: ZestFeature,
        libraryIndex: Int
    ) -> some View {

        let isBeingDragged =
            draggedSliceFeature == feature


        return VStack(spacing: 2) {

            Color.clear
                .frame(
                    width: loosePieceCell,
                    height: loosePieceCell
                )
                .overlay {

                    ZestLiquidGlassWedgePiece(
                        accentColor: accentColor,
                        accentHighlightColor:
                            settingsManager.accentHighlightColor,
                        accentDeepColor:
                            settingsManager.accentDeepColor,
                        symbol: feature.systemImage,
                        title: feature.title,
                        installed: false,
                        labelCounterRotationDegrees:
                            -loosePieceNeutralRotation,
                        usesLiveGlass: false,
                        labelScale: 0.82
                    )
                    .frame(
                        width: loosePieceCanvas,
                        height: loosePieceCanvas
                    )
                    .rotationEffect(
                        .degrees(loosePieceNeutralRotation)
                    )
                    .offset(
                        y: loosePiecePaletteCenterCompensation
                    )
                    .opacity(
                        isBeingDragged ? 0.14 : 1
                    )
                    .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(
                        minimumDistance: 1,
                        coordinateSpace:
                            .named("slicePhysicalEditor")
                    )
                    .onChanged { value in

                        // Dragging is a hot path.  Keep it completely outside any
                        // inherited SwiftUI animation transaction and avoid waking
                        // the full Settings tree for sub-pixel pointer noise.
                        var transaction = Transaction()
                        transaction.animation = nil
                        transaction.disablesAnimations = true

                        withTransaction(transaction) {
                            if draggedSliceFeature != feature {
                                draggedSliceFeature = feature
                                isDraggingSlicePiece = true
                            }

                            let dx = value.location.x - draggedSliceLocation.x
                            let dy = value.location.y - draggedSliceLocation.y
                            if draggedSliceLocation == .zero || hypot(dx, dy) >= 1.5 {
                                draggedSliceLocation = value.location
                            }

                            let target =
                                nearestSliceSlot(to: value.location)

                            // Magnetic state changes only when we actually cross a
                            // slot boundary; don't republish the same target.
                            if target != magneticSliceSlot {
                                magneticSliceSlot = target
                            }
                        }
                    }
                    .onEnded { value in

                        let target =
                            nearestSliceSlot(to: value.location)

                        if let target {

                            withAnimation(
                                .spring(
                                    response: 0.30,
                                    dampingFraction: 0.76
                                )
                            ) {
                                beginLayoutEditIfNeeded()
                                settingsManager.assign(
                                    feature,
                                    to: target
                                )
                                sliceDropBounce = true
                            }

                            NSHapticFeedbackManager
                                .defaultPerformer
                                .perform(
                                    .alignment,
                                    performanceTime: .now
                                )

                            Task { @MainActor in
                                try? await Task.sleep(
                                    for: .milliseconds(115)
                                )

                                withAnimation(
                                    .spring(
                                        response: 0.26,
                                        dampingFraction: 0.72
                                    )
                                ) {
                                    sliceDropBounce = false
                                }
                            }

                            print(
                                "🍊 DROP → \(feature.title) → \(target.rawValue)"
                            )
                        }

                        draggedSliceFeature = nil
                        magneticSliceSlot = nil
                        isDraggingSlicePiece = false
                    }
                )


            Text(feature.paletteSubtitle)
                .font(
                    .system(
                        size: 8,
                        weight: .medium
                    )
                )
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
                .frame(
                    width: loosePieceCell,
                    alignment: .center
                )
        }
        .frame(
            width: loosePieceCell,
            height: loosePieceCell + 14,
            alignment: .top
        )
    }


    private var loosePiecePaletteCenterCompensation:
        CGFloat {

        let scale =
            loosePieceCanvas / 210

        return
            ((43 + 98) / 2)
            * scale
    }


    private var loosePieceNeutralRotation:
        Double {

        let nativeAngle =
            ZestSliceVisualSlot
                .all[0]
                .centerAngle

        return
            270
            - nativeAngle
    }


    private func nearestSliceSlot(
        to point:
            CGPoint
    ) -> ZestSliceSlot? {

        let shellCenter =
            sliceAssemblyCenter == .zero
            ? CGPoint(x: 720, y: 160)
            : sliceAssemblyCenter

        let socketRadius:
            CGFloat = 94

        let captureRadius:
            CGFloat = 72


        var bestSlot:
            ZestSliceSlot?

        var bestDistance:
            CGFloat = .greatestFiniteMagnitude


        for visualSlot in
            ZestSliceVisualSlot.all {

            let radians =
                visualSlot.centerAngle
                * Double.pi
                / 180


            let socketCenter =
                CGPoint(
                    x:
                        shellCenter.x
                        + CGFloat(
                            cos(
                                radians
                            )
                        )
                        * socketRadius,
                    y:
                        shellCenter.y
                        + CGFloat(
                            sin(
                                radians
                            )
                        )
                        * socketRadius
                )


            let distance =
                hypot(
                    point.x
                    - socketCenter.x,
                    point.y
                    - socketCenter.y
                )


            if distance
                <= captureRadius,
               distance
                < bestDistance {

                bestDistance =
                    distance

                bestSlot =
                    visualSlot
                        .settingsSlot
            }
        }


        return bestSlot
    }


    private func continuousDragRotation(
        at point: CGPoint
    ) -> Double {

        let shellCenter =
            sliceAssemblyCenter == .zero
            ? CGPoint(x: 720, y: 160)
            : sliceAssemblyCenter

        let dx = point.x - shellCenter.x
        let dy = point.y - shellCenter.y
        let distance = hypot(dx, dy)

        // Away from the slice the piece remains in its neutral upright
        // palette orientation. As it approaches the ring it follows the
        // cursor angle continuously instead of jumping between six slots.
        guard distance < 165 else {
            return loosePieceNeutralRotation
        }

        let pointerAngle =
            atan2(Double(dy), Double(dx))
            * 180
            / Double.pi

        let nativeAngle =
            ZestSliceVisualSlot
                .all[0]
                .centerAngle

        return pointerAngle - nativeAngle
    }


    private func rotationDegreesForSliceSlot(
        _ slot:
            ZestSliceSlot?
    ) -> Double {

        guard
            let slot,
            let visualSlot =
                ZestSliceVisualSlot.all
                    .first(
                        where: {
                            $0.settingsSlot
                            == slot
                        }
                    )
        else {

            return
                loosePieceNeutralRotation
        }


        let nativeAngle =
            ZestSliceVisualSlot
                .all[0]
                .centerAngle


        return
            visualSlot.centerAngle
            - nativeAngle
    }


    private func dragCanvasPosition(
        rotation: Double
    ) -> CGPoint {

        // ZestLiquidGlassWedgePiece is drawn inside a square reference
        // canvas, but the visible wedge is not centered in that square.
        // Putting the square's center on the pointer therefore leaves the
        // actual tile roughly 90 pt away from the cursor.
        //
        // Compensate for the wedge's radial visual center so the *piece*
        // itself stays directly under the mouse at every rotation.
        let scale =
            loosePieceCanvas / 210

        let visualRadius =
            ((43 + 98) / 2)
            * scale

        let nativeCenterAngle =
            ZestSliceVisualSlot
                .all[0]
                .centerAngle

        let visibleAngle =
            (nativeCenterAngle + rotation)
            * Double.pi
            / 180

        return CGPoint(
            x:
                draggedSliceLocation.x
                - CGFloat(cos(visibleAngle))
                * visualRadius,
            y:
                draggedSliceLocation.y
                - CGFloat(sin(visibleAngle))
                * visualRadius
        )
    }


    @ViewBuilder
    private var physicalDraggedSlicePiece:
        some View {

        if
            let feature =
                draggedSliceFeature,
            isDraggingSlicePiece {

            let rotation =
                continuousDragRotation(
                    at: draggedSliceLocation
                )


            ZestLiquidGlassWedgePiece(
                accentColor:
                    accentColor,
                accentHighlightColor:
                    settingsManager
                        .accentHighlightColor,
                accentDeepColor:
                    settingsManager
                        .accentDeepColor,
                symbol:
                    feature.systemImage,
                title:
                    feature.title,
                installed:
                    false,
                labelCounterRotationDegrees:
                    -rotation,
                usesLiveGlass:
                    false
            )
            .frame(
                width:
                    loosePieceCanvas,
                height:
                    loosePieceCanvas
            )
            .rotationEffect(
                .degrees(
                    rotation
                )
            )
            .scaleEffect(1.02)
            .shadow(
                color:
                    Color.black.opacity(
                        0.16
                    ),
                radius:
                    magneticSliceSlot == nil
                    ? 7
                    : 10,
                x: 0,
                y: 6
            )
            .position(
                dragCanvasPosition(
                    rotation: rotation
                )
            )
            .allowsHitTesting(
                false
            )
            .zIndex(1000)
        }
    }


    @ViewBuilder
    private var layoutPreview:
        some View {

        switch settingsManager.formFactor {

        case .centerOnly:
            centerLayoutEditor

        case .orangeSlice:
            sliceLayoutEditor

        case .tripleSquare:
            tripleLayoutEditor
        }
    }


    // MARK: Center-Only Editor

    private let centerOnlyModes = ["language", "twoFeature", "fourFeature"]

    private var centerOnlySelectionIndex: Int {
        get { centerOnlyModes.firstIndex(of: settingsManager.centerOnlyPage) ?? 0 }
    }

    private var centerOnlyHeading: String {
        switch settingsManager.centerOnlyPage {
        case "twoFeature": return "2 Features"
        case "fourFeature": return "4 Features"
        default: return "Language Switcher"
        }
    }

    private var centerOnlySubtitle: String {
        switch settingsManager.centerOnlyPage {
        case "twoFeature": return "Split the ring horizontally between two actions."
        case "fourFeature": return "Four actions arranged around the center settings control."
        default: return "Switch between your enabled keyboard input sources."
        }
    }

    private var centerOnlyAssignableFeatures: [ZestFeature] {
        [.size, .font, .clipboard, .emoji, .symbols, .openShortcut, .runShortcut]
    }

    private func centerOnlyFeatureIcon(_ feature: ZestFeature) -> String {
        switch feature {
        case .size: return "textformat.size"
        case .font: return "bold.italic.underline"
        default: return feature.systemImage
        }
    }

    private var centerLayoutEditor: some View {
        VStack(spacing: 12) {
            VStack(spacing: 3) {
                Text(centerOnlyHeading)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(centerOnlySubtitle)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.16), value: settingsManager.centerOnlyPage)

            HStack(spacing: 112) {
                centerOnlyModeNavigationButton(systemImage: "chevron.left", direction: -1)
                centerOnlySetupRing
                centerOnlyModeNavigationButton(systemImage: "chevron.right", direction: 1)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 5) {
                ForEach(centerOnlyModes.indices, id: \.self) { index in
                    Circle()
                        .fill(index == centerOnlySelectionIndex ? accentColor : Color.secondary.opacity(0.22))
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.top, 18)

            if settingsManager.centerOnlyPage != "language" {
                HStack(spacing: 7) {
                    ForEach(centerOnlyAssignableFeatures) { feature in
                        VStack(spacing: 3) {
                            Image(systemName: centerOnlyFeatureIcon(feature))
                                .font(.system(size: 14, weight: .semibold))
                            Text(feature.title)
                                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color.primary.opacity(0.80))
                        .frame(width: 48, height: 42)
                        .background {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.primary.opacity(0.035))
                                .glassEffect(.regular.tint(accentColor.opacity(0.10)), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                        .onDrag {
                            centerOnlyDraggedFeature = feature
                            centerOnlyDraggedSourceIndex = nil
                            return NSItemProvider(object: feature.rawValue as NSString)
                        } preview: {
                            centerOnlyBankDragPreview(feature)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 382, alignment: .top)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                if settingsManager.centerOnlyPage != "language" {
                    Button {
                        beginLayoutEditIfNeeded()
                        if settingsManager.centerOnlyPage == "twoFeature" { settingsManager.centerOnlyTwoFeatures = [.empty, .empty] }
                        else { settingsManager.centerOnlyFourFeatures = [.empty, .empty, .empty, .empty] }
                    } label: {
                        Label("Remove All", systemImage: "square.stack.3d.up.slash")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 11).frame(height: 28).contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .background { Capsule().fill(Color.primary.opacity(0.045)) }
                    .overlay { Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 0.8) }
                    .focusable(false)
                }
                Button { resetCurrentLayout() } label: {
                    Label("Restore Defaults", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 11).frame(height: 28).contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(accentColor)
                .background { Capsule().fill(accentColor.opacity(0.10)) }
                .overlay { Capsule().stroke(accentColor.opacity(0.24), lineWidth: 0.8) }
                .focusable(false)

                if settingsManager.isLayoutEditing && !onboardingLayoutMode {
                Button { saveLayoutChanges() } label: {
                    Label("Save", systemImage: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .frame(height: 28)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .background { Capsule().fill(accentColor.opacity(0.86)) }
                .contentShape(Capsule())
                .focusable(false)
                }
            }
            .padding(.trailing, 14)
        }
    }

    private var centerOnlySetupRing: some View {
        // Language keeps the compact dial. The 2/4 feature editors get
        // 20% more surface area so the sectors read as real controls.
        let diameter: CGFloat = settingsManager.centerOnlyPage == "language" ? 204 : 245

        return ZStack {
            if settingsManager.centerOnlyPage == "language" {
                centerOnlyLanguageBacking(diameter: diameter)
                centerOnlyLanguageWing(systemImage: "chevron.left", side: -1)
                    .offset(x: -(diameter / 2 + 23))
                centerOnlyLanguageWing(systemImage: "chevron.right", side: 1)
                    .offset(x: diameter / 2 + 23)
            }

            centerOnlyPhysicalRing(diameter: diameter)

            Group {
                switch settingsManager.centerOnlyPage {
                case "twoFeature":
                    centerOnlyFeatureDisk(features: settingsManager.centerOnlyTwoFeatures, count: 2, diameter: diameter)
                case "fourFeature":
                    centerOnlyFeatureDisk(features: settingsManager.centerOnlyFourFeatures, count: 4, diameter: diameter)
                default:
                    centerOnlyLanguagePreview(diameter: diameter)
                }
            }
            .id(settingsManager.centerOnlyPage)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
        .frame(width: diameter, height: diameter)
        .animation(.spring(response: 0.34, dampingFraction: 0.80), value: settingsManager.centerOnlyPage)
        .shadow(color: .black.opacity(0.14), radius: 8, y: 5)
        .shadow(color: accentColor.opacity(0.10), radius: 10)
    }

    private func centerOnlyLanguageBacking(diameter: CGFloat) -> some View {
        Capsule()
            .fill(settingsManager.accentDeepColor.opacity(0.055))
            .frame(width: diameter + 126, height: 58)
            .glassEffect(.regular.tint(accentColor.opacity(0.11)), in: Capsule())
            .overlay { Capsule().stroke(Color.white.opacity(0.30), lineWidth: 0.9) }
            .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
            .zIndex(-4)
    }

    private func centerOnlyPhysicalRing(diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(settingsManager.accentDeepColor.opacity(0.030))
                .frame(width: diameter + 12, height: diameter + 12)
                .offset(y: 1.1)
            Color.clear
                .frame(width: diameter + 12, height: diameter + 12)
                .glassEffect(.regular.tint(accentColor.opacity(0.095)), in: Circle())
            Circle()
                .stroke(LinearGradient(colors: [Color.white.opacity(0.86), Color.white.opacity(0.28), settingsManager.accentHighlightColor.opacity(0.13), settingsManager.accentDeepColor.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.05)
                .frame(width: diameter + 12, height: diameter + 12)
            Circle()
                .fill(settingsManager.accentDeepColor.opacity(0.055))
                .frame(width: diameter, height: diameter)
                .offset(y: 1.4)
            Color.clear
                .frame(width: diameter, height: diameter)
                .glassEffect(.regular.tint(accentColor.opacity(0.24)), in: Circle())
            Circle()
                .fill(RadialGradient(stops: [.init(color: Color.white.opacity(0.18), location: 0), .init(color: settingsManager.accentHighlightColor.opacity(0.12), location: 0.30), .init(color: Color.clear, location: 0.74)], center: UnitPoint(x: 0.28, y: 0.16), startRadius: 0, endRadius: 100))
                .frame(width: diameter, height: diameter)
            VStack(spacing: 5) {
                ForEach(0..<24, id: \.self) { _ in
                    Rectangle().fill(Color.black.opacity(0.020)).frame(height: 1)
                }
            }
            .frame(width: diameter - 24, height: diameter - 24)
            .clipShape(Circle())
            .allowsHitTesting(false)
            Circle()
                .stroke(LinearGradient(colors: [Color.white.opacity(0.88), Color.white.opacity(0.30), settingsManager.accentHighlightColor.opacity(0.18), accentColor.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.1)
                .frame(width: diameter, height: diameter)
        }
    }

    private func centerOnlyLanguagePreview(diameter: CGFloat) -> some View {
        ZStack {
            Text("EN")
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.84))
                .offset(y: -45)
            centerOnlyArcText("ABC", radius: 72)
            centerOnlySetupGear
        }
        .frame(width: diameter, height: diameter)
    }

    private func centerOnlyArcText(_ text: String, radius: CGFloat) -> some View {
        let characters = Array(text)
        let count = max(characters.count, 1)
        let start = 150.0
        let end = 30.0
        return ZStack {
            ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                let t = count == 1 ? 0.5 : Double(index) / Double(count - 1)
                let angle = start + (end - start) * t
                let radians = angle * Double.pi / 180
                Text(String(character))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.78))
                    .rotationEffect(.degrees(angle - 90))
                    .offset(x: cos(radians) * radius, y: sin(radians) * radius)
            }
        }
    }

    private var centerOnlySetupGear: some View {
        ZStack {
            Circle().fill(settingsManager.accentDeepColor.opacity(0.18)).frame(width: 58, height: 58).offset(y: 1.8)
            Color.clear.frame(width: 54, height: 54).glassEffect(.regular.tint(accentColor.opacity(0.25)), in: Circle())
            Circle().stroke(LinearGradient(colors: [Color.white.opacity(0.84), Color.white.opacity(0.28), settingsManager.accentDeepColor.opacity(0.20)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                .frame(width: 54, height: 54)
            Image(systemName: "gearshape.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.84))
        }
    }

    private func centerOnlyFeatureDisk(features: [ZestFeature], count: Int, diameter: CGFloat) -> some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let feature = features[index]
                centerOnlyFeatureSector(feature: feature, index: index, count: count, diameter: diameter)
                    .opacity(centerOnlyDraggedSourceIndex == index ? 0.22 : 1)
                    .onDrag {
                        guard feature != .empty else { return NSItemProvider() }
                        centerOnlyDraggedFeature = feature
                        centerOnlyDraggedSourceIndex = index
                        return NSItemProvider(object: feature.rawValue as NSString)
                    } preview: {
                        centerOnlySectorDragPreview(feature, index: index, count: count, diameter: diameter)
                    }
            }

            // Magnetic destination preview: once the pointer enters the ring,
            // the loose block visually becomes the exact destination sector.
            if let target = centerOnlyMagneticTargetIndex,
               let feature = centerOnlyDraggedFeature {
                CenterOnlySectorShape(index: target, count: count)
                    .fill(accentColor.opacity(0.20))
                    .glassEffect(.regular.tint(accentColor.opacity(0.18)), in: CenterOnlySectorShape(index: target, count: count))
                    .overlay {
                        CenterOnlySectorShape(index: target, count: count)
                            .stroke(Color.white.opacity(0.68), lineWidth: 1.15)
                    }
                    .overlay {
                        centerOnlySectorIcon(feature, index: target, count: count, diameter: diameter)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .allowsHitTesting(false)
            }

            centerOnlySetupGear
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .onDrop(of: [UTType.text], delegate: CenterOnlyRingDropDelegate(
            diameter: diameter,
            count: count,
            targetIndex: $centerOnlyMagneticTargetIndex,
            perform: { target in
                centerOnlyCommitDrop(targetIndex: target, count: count)
            },
            cleanup: {
                withAnimation(.easeOut(duration: 0.14)) {
                    centerOnlyMagneticTargetIndex = nil
                }
                centerOnlyDraggedFeature = nil
                centerOnlyDraggedSourceIndex = nil
            }
        ))
        .clipShape(Circle())
        .animation(.spring(response: 0.22, dampingFraction: 0.80), value: centerOnlyMagneticTargetIndex)
    }

    private func centerOnlyCommitDrop(targetIndex: Int, count: Int) {
        guard let dropped = centerOnlyDraggedFeature,
              centerOnlyAssignableFeatures.contains(dropped) else { return }

        beginLayoutEditIfNeeded()
        var values = count == 2 ? settingsManager.centerOnlyTwoFeatures : settingsManager.centerOnlyFourFeatures
        guard values.indices.contains(targetIndex) else { return }

        let sourceIndex = centerOnlyDraggedSourceIndex
        let existingIndex = values.firstIndex(of: dropped)

        if let sourceIndex, values.indices.contains(sourceIndex) {
            // Installed tile -> installed tile: true Orange-Slice-style swap.
            if sourceIndex != targetIndex {
                values.swapAt(sourceIndex, targetIndex)
            }
        } else if let existingIndex, existingIndex != targetIndex {
            // Bank -> ring with a feature that already exists: move/swap it,
            // never create a duplicate feature in the same controller.
            values.swapAt(existingIndex, targetIndex)
        } else {
            values[targetIndex] = dropped
        }

        if count == 2 {
            settingsManager.centerOnlyTwoFeatures = values
        } else {
            settingsManager.centerOnlyFourFeatures = values
        }

        if dropped == .openShortcut || dropped == .runShortcut {
            DispatchQueue.main.async {
                presentCenterActionSetup(feature: dropped, index: targetIndex, count: count)
            }
        }
    }

    @ViewBuilder
    private func centerOnlySectorIcon(_ feature: ZestFeature, index: Int, count: Int, diameter: CGFloat) -> some View {
        let radius = diameter * 0.32
        let angle: Double = count == 2 ? (index == 0 ? -90 : 90) : [-90, 0, 90, 180][index]
        let radians = angle * Double.pi / 180
        Image(systemName: centerOnlyFeatureIcon(feature))
            .font(.system(size: count == 2 ? 29 : 24, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.84))
            .offset(x: cos(radians) * radius, y: sin(radians) * radius)
    }

    private func centerOnlyDropIndex(at location: CGPoint, count: Int, diameter: CGFloat) -> Int {
        let dx = location.x - diameter / 2
        let dy = location.y - diameter / 2

        if count == 2 {
            return dy < 0 ? 0 : 1
        }

        // Four-feature sectors are centered at 12, 3, 6 and 9 o'clock,
        // with their boundaries on the diagonals.
        let angle = atan2(dy, dx) * 180 / .pi
        if angle >= -135 && angle < -45 { return 0 } // top
        if angle >= -45 && angle < 45 { return 1 }   // right
        if angle >= 45 && angle < 135 { return 2 }   // bottom
        return 3                                      // left
    }

    private func centerOnlyFeatureSector(feature: ZestFeature, index: Int, count: Int, diameter: CGFloat) -> some View {
        let radius = diameter * 0.32
        let angle: Double = count == 2 ? (index == 0 ? -90 : 90) : [-90, 0, 90, 180][index]
        let radians = angle * Double.pi / 180
        return ZStack {
            CenterOnlySectorShape(index: index, count: count)
                .fill(feature == .empty ? Color.primary.opacity(0.018) : accentColor.opacity(0.075))
                .overlay {
                    CenterOnlySectorShape(index: index, count: count)
                        .stroke(feature == .empty ? Color.primary.opacity(0.18) : Color.white.opacity(0.28), style: StrokeStyle(lineWidth: feature == .empty ? 1.2 : 0.8, dash: feature == .empty ? [4,4] : []))
                }
            if feature != .empty {
                Image(systemName: centerOnlyFeatureIcon(feature))
                    .font(.system(size: count == 2 ? 29 : 24, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.82))
                .offset(x: cos(radians) * radius, y: sin(radians) * radius)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .offset(x: cos(radians) * radius, y: sin(radians) * radius)
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(CenterOnlySectorShape(index: index, count: count))
    }

    private func centerOnlyBankDragPreview(_ feature: ZestFeature) -> some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(accentColor.opacity(0.16))
            .glassEffect(.regular.tint(accentColor.opacity(0.14)), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                Image(systemName: centerOnlyFeatureIcon(feature))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.86))
            }
            .frame(width: 48, height: 42)
    }

    private func centerOnlySectorDragPreview(_ feature: ZestFeature, index: Int, count: Int, diameter: CGFloat) -> some View {
        ZStack {
            CenterOnlySectorShape(index: index, count: count)
                .fill(accentColor.opacity(0.22))
                .glassEffect(.regular.tint(accentColor.opacity(0.18)), in: CenterOnlySectorShape(index: index, count: count))
                .overlay { CenterOnlySectorShape(index: index, count: count).stroke(Color.white.opacity(0.52), lineWidth: 1) }
            centerOnlySectorIcon(feature, index: index, count: count, diameter: diameter)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
    }

    private func centerOnlyLanguageWing(systemImage: String, side: Int) -> some View {
        ZStack {
            Color.clear.frame(width: 72, height: 58)
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.72))
                .frame(width: 64, height: 46)
                .background {
                    Color.clear.frame(width: 64, height: 46)
                        .glassEffect(.regular.tint(accentColor.opacity(0.24)), in: UnevenRoundedRectangle(topLeadingRadius: side < 0 ? 23 : 6, bottomLeadingRadius: side < 0 ? 23 : 6, bottomTrailingRadius: side > 0 ? 23 : 6, topTrailingRadius: side > 0 ? 23 : 6))
                }
                .overlay {
                    UnevenRoundedRectangle(topLeadingRadius: side < 0 ? 23 : 6, bottomLeadingRadius: side < 0 ? 23 : 6, bottomTrailingRadius: side > 0 ? 23 : 6, topTrailingRadius: side > 0 ? 23 : 6)
                        .stroke(LinearGradient(colors: [Color.white.opacity(0.72), accentColor.opacity(0.22), settingsManager.accentDeepColor.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.9)
                }
        }
        .allowsHitTesting(false)
        .zIndex(-1)
    }

    private func centerOnlyModeNavigationButton(systemImage: String, direction: Int) -> some View {
        Button {
            beginLayoutEditIfNeeded()
            let current = centerOnlySelectionIndex
            let next = (current + direction + centerOnlyModes.count) % centerOnlyModes.count
            centerOnlySlideDirection = CGFloat(direction)
            withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                settingsManager.centerOnlyPage = centerOnlyModes[next]
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.70))
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background { Circle().fill(Color.primary.opacity(0.045)) }
        .overlay { Circle().stroke(Color.primary.opacity(0.10), lineWidth: 0.8) }
        .focusable(false)
    }

    private func featureDropCircle(
        _ feature:
            ZestFeature
    ) -> some View {

        VStack(
            spacing: 6
        ) {

            Image(
                systemName:
                    feature.systemImage
            )
            .font(
                .system(
                    size: 23,
                    weight: .medium
                )
            )

            Text(
                feature.title
            )
            .font(
                .system(
                    size: 9,
                    weight: .semibold
                )
            )
        }
        .foregroundStyle(
            Color.white.opacity(
                0.92
            )
        )
        .frame(
            width: 92,
            height: 92
        )
        .background {

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            settingsManager
                                .accentHighlightColor
                                .opacity(0.88),
                            accentColor.opacity(
                                0.78
                            ),
                            settingsManager
                                .accentDeepColor
                                .opacity(0.84)
                        ],
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    )
                )
        }
        .overlay {

            Circle()
                .stroke(
                    Color.white.opacity(
                        0.32
                    ),
                    lineWidth: 1
                )
        }
    }


    // MARK: Triple Editor

    private var tripleLayoutEditor: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(accentColor.opacity(0.08))
                    .frame(width: 199, height: 71)
                    .glassEffect(.regular.tint(accentColor.opacity(0.10)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.22), lineWidth: 0.8) }

                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { index in tripleDropTile(index) }
                }
            }

            HStack(spacing: 8) {
                ForEach(ZestFeature.allCases.filter { $0 != .empty && $0 != .settings }) { feature in
                    VStack(spacing: 3) {
                        Image(systemName: feature.systemImage).font(.system(size: 14, weight: .semibold))
                        Text(feature.title).font(.system(size: 7.5, weight: .semibold)).lineLimit(1)
                    }
                    .frame(width: 58, height: 48)
                    .background { RoundedRectangle(cornerRadius: 10).fill(accentColor.opacity(0.14)) }
                    .draggable(feature.rawValue) {
                        VStack(spacing: 3) { Image(systemName: feature.systemImage); Text(feature.title).font(.system(size: 8, weight: .semibold)) }
                            .frame(width: 57, height: 57)
                            .background { RoundedRectangle(cornerRadius: 13).fill(accentColor.opacity(0.62)) }
                    }
                }
            }

            HStack(spacing: 10) {
                Button { beginLayoutEditIfNeeded(); settingsManager.tripleFeatures = [.empty, .empty, .empty] } label: {
                    Label("Remove All", systemImage: "square.stack.3d.up.slash")
                        .font(.system(size: 10, weight: .semibold)).padding(.horizontal, 14).frame(height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background { Capsule().fill(Color.primary.opacity(0.045)) }
                .overlay { Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 0.8) }
                .contentShape(Capsule())
                .focusable(false)

                Button { resetCurrentLayout() } label: {
                    Label("Restore Defaults", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .semibold)).padding(.horizontal, 14).frame(height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(accentColor)
                .background { Capsule().fill(accentColor.opacity(0.10)) }
                .overlay { Capsule().stroke(accentColor.opacity(0.24), lineWidth: 0.8) }
                .focusable(false)

                if settingsManager.isLayoutEditing && !onboardingLayoutMode {
                    Button { saveLayoutChanges() } label: {
                        Label("Save", systemImage: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 15)
                            .frame(height: 32)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .background { Capsule().fill(accentColor.opacity(0.86)) }
                    .contentShape(Capsule())
                    .focusable(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
        }
        .frame(height: 245)
    }

    private func tripleDropTile(_ index: Int) -> some View {
        let feature = tripleFeatures[index]
        return Button { if feature == .settings { openSettings() } } label: {
            VStack(spacing: 3) {
                if feature == .empty { Image(systemName: "plus").opacity(0.35) }
                else {
                    Image(systemName: feature.systemImage).font(.system(size: 17, weight: .semibold))
                    Text(feature.title).font(.system(size: 7.5, weight: .semibold)).lineLimit(1)
                }
            }
            .frame(width: 57, height: 57)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(feature == .empty ? Color.primary.opacity(0.025) : accentColor.opacity(0.22))
                    .glassEffect(.regular.tint(accentColor.opacity(feature == .empty ? 0.04 : 0.15)), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .overlay { RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(feature == .empty ? 0.12 : 0.32), style: StrokeStyle(lineWidth: 0.8, dash: feature == .empty ? [4,4] : [])) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(feature == .empty ? "" : feature.rawValue)
        .dropDestination(for: String.self) { values, _ in
            guard let raw = values.first, let dropped = ZestFeature(rawValue: raw), dropped != .empty else { return false }
            beginLayoutEditIfNeeded()
            var values = tripleFeatures
            if let source = values.firstIndex(of: dropped), source != index {
                let displaced = values[index]
                values[index] = dropped
                values[source] = displaced
            } else { values[index] = dropped }
            tripleFeatures = values
            if dropped == .openShortcut || dropped == .runShortcut {
                presentCenterActionSetup(feature: dropped, index: index, count: 3)
            }
            return true
        }
    }


    // MARK: - Slice Editor

    private var sliceLayoutEditor:
        some View {

        ZStack(alignment: .topLeading) {

            GeometryReader { geometry in

                let contentWidth =
                    max(720, geometry.size.width)

                // Keep enough room for the complete RRCS toolbar.
                // The previous 1/3 column could become narrower than the
                // intrinsic button row, which pushed Save over the card edge.
                let sliceColumnWidth =
                    max(390, contentWidth * 0.37)

                let piecesColumnWidth =
                    max(500, contentWidth - sliceColumnWidth - 18)


                HStack(
                    alignment: .top,
                    spacing: 18
                ) {

                    featureLibrary
                        .frame(
                            width: piecesColumnWidth,
                            alignment: .topLeading
                        )


                    VStack(spacing: 6) {

                        HStack(spacing: 8) {
                            Spacer(minLength: 0)

                            Button {
                                withAnimation(
                                    .spring(
                                        response: 0.32,
                                        dampingFraction: 0.78
                                    )
                                ) {
                                    beginLayoutEditIfNeeded()
                                    settingsManager.removeAllSliceFeatures()
                                    sliceDropBounce = true
                                }

                                NSHapticFeedbackManager
                                    .defaultPerformer
                                    .perform(
                                        .alignment,
                                        performanceTime: .now
                                    )

                                Task { @MainActor in
                                    try? await Task.sleep(
                                        for: .milliseconds(115)
                                    )
                                    withAnimation(
                                        .spring(
                                            response: 0.26,
                                            dampingFraction: 0.72
                                        )
                                    ) {
                                        sliceDropBounce = false
                                    }
                                }
                            } label: {
                                Label(
                                    "Remove All",
                                    systemImage: "square.stack.3d.up.slash"
                                )
                                .font(
                                    .system(
                                        size: 9,
                                        weight: .semibold
                                    )
                                )
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .contentShape(Capsule())
                            .foregroundStyle(Color.secondary)
                            .background {
                                Capsule()
                                    .fill(Color.primary.opacity(0.045))
                            }
                            .overlay {
                                Capsule()
                                    .stroke(
                                        Color.primary.opacity(0.10),
                                        lineWidth: 0.8
                                    )
                            }
                            .focusable(false)
                            .fixedSize(horizontal: true, vertical: false)

                            Button {
                                withAnimation(
                                    .spring(
                                        response: 0.32,
                                        dampingFraction: 0.78
                                    )
                                ) {
                                    resetCurrentLayout()
                                    sliceDropBounce = true
                                }

                                NSHapticFeedbackManager
                                    .defaultPerformer
                                    .perform(
                                        .alignment,
                                        performanceTime: .now
                                    )

                                Task { @MainActor in
                                    try? await Task.sleep(
                                        for: .milliseconds(115)
                                    )
                                    withAnimation(
                                        .spring(
                                            response: 0.26,
                                            dampingFraction: 0.72
                                        )
                                    ) {
                                        sliceDropBounce = false
                                    }
                                }
                            } label: {
                                Label(
                                    "Revert to Defaults",
                                    systemImage: "arrow.counterclockwise"
                                )
                                .font(
                                    .system(
                                        size: 9,
                                        weight: .semibold
                                    )
                                )
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .contentShape(Capsule())
                            .foregroundStyle(accentColor)
                            .background {
                                Capsule()
                                    .fill(accentColor.opacity(0.10))
                            }
                            .overlay {
                                Capsule()
                                    .stroke(
                                        accentColor.opacity(0.24),
                                        lineWidth: 0.8
                                    )
                            }
                            .focusable(false)
                            .fixedSize(horizontal: true, vertical: false)

                            if settingsManager.isLayoutEditing && !onboardingLayoutMode {
                                Button {
                                    cancelLayoutChanges()
                                } label: {
                                    Text("Cancel")
                                        .font(.system(size: 9, weight: .semibold))
                                        .padding(.horizontal, 11)
                                        .frame(height: 28)
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .contentShape(Capsule())
                                .foregroundStyle(Color.secondary)
                                .background {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.045))
                                }
                                .overlay {
                                    Capsule()
                                        .stroke(Color.primary.opacity(0.10), lineWidth: 0.8)
                                }
                                .focusable(false)
                                .fixedSize(horizontal: true, vertical: false)

                                Button {
                                    saveLayoutChanges()
                                } label: {
                                    Label(
                                        "Save",
                                        systemImage: "checkmark"
                                    )
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 13)
                                    .frame(height: 28)
                                    .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .contentShape(Capsule())
                                .background {
                                    Capsule()
                                        .fill(accentColor.opacity(layoutIsComplete ? 0.86 : 0.32))
                                }
                                .focusable(false)
                                .fixedSize(horizontal: true, vertical: false)
                                .disabled(!layoutIsComplete)
                            }

                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 30,
                            maxHeight: 30,
                            alignment: .trailing
                        )
                        .padding(.trailing, 24)


                        ZestSliceAssemblyShell(
                            accentColor: accentColor,
                            accentHighlightColor:
                                settingsManager.accentHighlightColor,
                            accentDeepColor:
                                settingsManager.accentDeepColor,
                            showInstalledGlass: false,
                            installedFeatures:
                                settingsManager.sliceAssignments,
                            unconfiguredSlots:
                                unconfiguredActionSlots,
                            onInstalledFeatureTap: { feature, slot in
                                guard feature == .openShortcut || feature == .runShortcut else { return }
                                presentActionSetup(feature: feature, slot: slot)
                            },
                            acceptsFeatureDrops: false,
                            onFeatureDrop: nil,
                            magneticTargetSlot:
                                magneticSliceSlot
                        )
                        .frame(
                            width: 280,
                            height: 280
                        )
                        .scaleEffect(
                            sliceDropBounce ? 1.018 : 1
                        )
                        .background {
                            GeometryReader { proxy in
                                let frame = proxy.frame(
                                    in: .named(
                                        "slicePhysicalEditor"
                                    )
                                )

                                Color.clear
                                    .preference(
                                        key:
                                            SliceAssemblyCenterPreferenceKey.self,
                                        value:
                                            CGPoint(
                                                x: frame.midX,
                                                y: frame.midY
                                            )
                                    )
                            }
                        }

                    }
                    .frame(
                        width: sliceColumnWidth,
                        alignment: .top
                    )
                    .offset(y: -22)
                }
            }


            physicalDraggedSlicePiece
        }
        .coordinateSpace(name: "slicePhysicalEditor")
        .onPreferenceChange(
            SliceAssemblyCenterPreferenceKey.self
        ) { center in
            // Scrolling changes the editor's position in the parent document,
            // but not its own internal geometry. Avoid feeding that motion back
            // into @State on every scroll/layout pass.
            guard
                !parentScrollActive
            else {
                return
            }

            if center != .zero {
                let dx = center.x - sliceAssemblyCenter.x
                let dy = center.y - sliceAssemblyCenter.y
                // Preference propagation can jitter by fractions of a point while
                // the parent Settings ScrollView lays out.  Ignore that noise so
                // geometry does not feed back into another full editor pass.
                if sliceAssemblyCenter == .zero || hypot(dx, dy) >= 0.75 {
                    var transaction = Transaction()
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        sliceAssemblyCenter = center
                    }
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 350,
            alignment: .topLeading
        )
    }


    private func assemblyLegendRow(
        symbol: String,
        title: String,
        description: String
    ) -> some View {

        HStack(
            spacing: 9
        ) {

            Image(
                systemName:
                    symbol
            )
            .font(
                .system(
                    size: 12,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                accentColor
            )
            .frame(
                width: 22,
                height: 22
            )
            .background {

                RoundedRectangle(
                    cornerRadius: 6,
                    style: .continuous
                )
                .fill(
                    accentColor.opacity(
                        0.09
                    )
                )
            }


            VStack(
                alignment: .leading,
                spacing: 1
            ) {

                Text(
                    title
                )
                .font(
                    .system(
                        size: 10,
                        weight: .semibold
                    )
                )


                Text(
                    description
                )
                .font(
                    .system(
                        size: 8,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    Color.secondary
                )
            }
        }
    }


    private func sliceDropTile(
        _ slot:
            ZestSliceSlot
    ) -> some View {

        let feature =
            settingsManager.feature(
                for: slot
            )


        return VStack(
            spacing: 3
        ) {

            Image(
                systemName:
                    feature.systemImage
            )
            .font(
                .system(
                    size: 14,
                    weight: .semibold
                )
            )

            Text(
                feature.title
            )
            .font(
                .system(
                    size: 7,
                    weight: .semibold
                )
            )
            .lineLimit(1)
        }
        .foregroundStyle(
            Color.white.opacity(
                0.92
            )
        )
        .frame(
            width: 72,
            height: 52
        )
        .background {

            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [
                        settingsManager
                            .accentHighlightColor
                            .opacity(0.56),
                        accentColor.opacity(
                            0.52
                        ),
                        settingsManager
                            .accentDeepColor
                            .opacity(0.60)
                    ],
                    startPoint:
                        .topLeading,
                    endPoint:
                        .bottomTrailing
                )
            )
        }
        .overlay {

            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .stroke(
                accentColor.opacity(
                    0.74
                ),
                lineWidth: 1
            )
        }
        .shadow(
            color:
                accentColor.opacity(
                    0.12
                ),
            radius: 7
        )
        .dropDestination(
            for: String.self
        ) { values, _ in

            guard
                let raw =
                    values.first,
                let feature =
                    ZestFeature(
                        rawValue: raw
                    )
            else {
                return false
            }


            beginLayoutEditIfNeeded()
            settingsManager.assign(
                feature,
                to: slot
            )

            return true
        }
    }


    private func sliceOffset(
        for slot:
            ZestSliceSlot
    ) -> CGSize {

        switch slot {

        case .slot2:
            return CGSize(
                width: -82,
                height: -67
            )

        case .slot3:
            return CGSize(
                width: 0,
                height: -91
            )

        case .slot4:
            return CGSize(
                width: 82,
                height: -67
            )

        case .slot5:
            return CGSize(
                width: 92,
                height: 16
            )

        case .slot6:
            return CGSize(
                width: 45,
                height: 87
            )

        case .slot7:
            return CGSize(
                width: -45,
                height: 87
            )
        }
    }


    private var previewSurface:
        some View {

        RoundedRectangle(
            cornerRadius: 16,
            style: .continuous
        )
        .fill(
            Color.black.opacity(
                0.13
            )
        )
        .overlay {

            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(
                    0.10
                ),
                lineWidth: 0.8
            )
        }
    }


    private var layoutHelpText:
        String {

        switch settingsManager.formFactor {

        case .centerOnly:

            return
                "Drag a feature onto the circle. The central language control can later remain fixed or become assignable."


        case .orangeSlice:

            return
                "Drag features from the list onto any slice position. Existing features swap automatically."


        case .tripleSquare:

            return
                "Drag a feature onto any of the three tiles. Runtime support for this layout comes next."
        }
    }


    private func resetCurrentLayout() {

        beginLayoutEditIfNeeded()

        withAnimation(
            .spring(
                response: 0.22,
                dampingFraction: 0.86
            )
        ) {

            switch settingsManager.formFactor {

            case .centerOnly:

                centerFeature = .emoji
                if settingsManager.centerOnlyPage == "twoFeature" {
                    settingsManager.centerOnlyTwoFeatures = [.clipboard, .emoji]
                } else if settingsManager.centerOnlyPage == "fourFeature" {
                    settingsManager.centerOnlyFourFeatures = [.size, .font, .clipboard, .emoji]
                }


            case .orangeSlice:

                let defaults =
                    ZestSettingsManager
                        .defaultSliceAssignments

                for slot
                    in ZestSliceSlot.allCases {

                    if let feature =
                        defaults[slot] {

                        settingsManager
                            .assign(
                                feature,
                                to: slot
                            )
                    }
                }


            case .tripleSquare:

                tripleFeatures = [
                    .clipboard,
                    .emoji,
                    .symbols
                ]
            }
        }
    }


    // MARK: - Shortcuts

    private var shortcutsSection:
        some View {

        VStack(
            alignment: .leading,
            spacing: 18
        ) {

            pageHeader(
                "Keyboard Shortcuts",
                subtitle:
                    "Control how Zest is summoned."
            )


            settingsCard(
                title:
                    "Show Zest",
                subtitle:
                    "The global shortcut that will open Zest beside the active text caret."
            ) {

                ZestShortcutRecorderRow("Show Zest", shortcut: $settingsManager.showZestShortcut)

                Text("Click the shortcut field and press the combination you want. Zest saves it automatically and uses it immediately.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.secondary)
            }

            settingsCard(
                title: "Rapid Input Source Switching",
                subtitle: "Switch keyboard input sources instantly from any Zest form factor."
            ) {
                Toggle("Rapid Input Source Switching", isOn: $settingsManager.rapidInputSourceSwitching)
                    .toggleStyle(.switch)

                if settingsManager.rapidInputSourceSwitching {
                    ZestShortcutRecorderRow("Previous Input Source", shortcut: $settingsManager.saturnPreviousShortcut)
                    ZestShortcutRecorderRow("Next Input Source", shortcut: $settingsManager.saturnNextShortcut)
                    Text("The shortcuts save automatically. When the Saturn Language Switcher is on screen, these same controls animate its turntable; otherwise Zest briefly shows the Saturn HUD.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
            }

        }
    }





    // MARK: - Permissions

    private var permissionsSection:
        some View {

        VStack(
            alignment: .leading,
            spacing: 18
        ) {

            pageHeader(
                "Permissions & Startup",
                subtitle:
                    "See what Zest needs in order to work across your Mac."
            )


            settingsCard(
                title:
                    "Permissions",
                subtitle:
                    "Zest needs Accessibility access to interact with text in other applications."
            ) {

                permissionRow(
                    title:
                        "Accessibility",
                    symbol:
                        "accessibility",
                    granted:
                        AXIsProcessTrusted()
                )


                permissionRow(
                    title:
                        "Pages Automation",
                    symbol:
                        "doc.text",
                    granted:
                        false
                )


                Text(
                    "Pages Automation status will be connected to the native Apple Events authorization check in the permissions pass."
                )
                .font(
                    .system(
                        size: 9,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    Color.secondary
                )
            }


            settingsCard(
                title:
                    "Startup",
                subtitle:
                    "Choose whether Zest should be available immediately after you sign in."
            ) {

                Toggle(
                    "Open Zest at Login",
                    isOn:
                        $settingsManager
                            .launchAtLogin
                )
                .toggleStyle(
                    .switch
                )


                Text(
                    "Native login-item registration will be connected in the startup pass."
                )
                .font(
                    .system(
                        size: 9,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    Color.secondary
                )
            }
        }
    }


    private func permissionRow(
        title: String,
        symbol: String,
        granted: Bool
    ) -> some View {

        HStack(
            spacing: 11
        ) {

            Image(
                systemName:
                    symbol
            )
            .font(
                .system(
                    size: 15,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                granted
                ? accentColor
                : Color.secondary
            )
            .frame(
                width: 22
            )


            Text(
                title
            )
            .font(
                .system(
                    size: 11,
                    weight: .medium
                )
            )


            Spacer()


            Text(
                granted
                ? "Granted"
                : "Required"
            )
            .font(
                .system(
                    size: 9,
                    weight: .bold
                )
            )
            .foregroundStyle(
                granted
                ? accentColor
                : Color.secondary
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
                        granted
                        ? accentColor.opacity(
                            0.12
                        )
                        : Color.primary.opacity(
                            0.045
                        )
                    )
            }
        }
        .frame(
            height: 36
        )
    }


    // MARK: - Reset

    private var resetSection:
        some View {

        VStack(
            alignment: .leading,
            spacing: 18
        ) {

            pageHeader(
                "Reset",
                subtitle:
                    "Restore Zest without touching macOS permissions."
            )


            settingsCard(
                title:
                    "Appearance",
                subtitle:
                    "Restore the original Orange Slice appearance and layout."
            ) {

                settingsActionButton(
                    "Reset Appearance",
                    symbol:
                        "paintpalette"
                ) {

                    settingsManager
                        .resetAppearance()
                }
            }


            settingsCard(
                title:
                    "Onboarding",
                subtitle:
                    "Make Zest show the first-run experience again on the next launch."
            ) {

                settingsActionButton(
                    "Reset Onboarding State",
                    symbol:
                        "sparkles.rectangle.stack"
                ) {
                    settingsManager.resetOnboardingState()
                }

                Text("This does not change your current Zest preferences. The onboarding will appear the next time Zest launches.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.secondary)
            }


            settingsCard(
                title:
                    "Full Reset",
                subtitle:
                    "Restore all Zest preferences to their defaults."
            ) {

                settingsActionButton(
                    "Reset Zest",
                    symbol:
                        "arrow.counterclockwise",
                    destructive:
                        true
                ) {

                    showResetConfirmation =
                        true
                }
            }


            Text(
                "There is currently no user-facing cache that needs manual cleaning, so Zest does not expose a fake Clean Cache button."
            )
            .font(
                .system(
                    size: 10,
                    weight: .medium
                )
            )
            .foregroundStyle(
                Color.secondary
            )
        }
    }


    // MARK: - About

    private var aboutSection:
        some View {

        VStack(
            alignment: .leading,
            spacing: 18
        ) {

            pageHeader(
                "About Zest",
                subtitle:
                    "A little bit of citrus for your Mac."
            )


            settingsCard(
                title:
                    "Zest",
                subtitle:
                    versionDescription
            ) {

                HStack(
                    spacing: 14
                ) {

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    settingsManager
                                        .accentHighlightColor,
                                    accentColor,
                                    settingsManager
                                        .accentDeepColor
                                ],
                                startPoint:
                                    .topLeading,
                                endPoint:
                                    .bottomTrailing
                            )
                        )
                        .frame(
                            width: 58,
                            height: 58
                        )
                        .overlay {

                            Image(
                                systemName:
                                    "sparkles"
                            )
                            .font(
                                .system(
                                    size: 22,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                Color.white.opacity(
                                    0.92
                                )
                            )
                        }


                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {

                        Text(
                            "Zest"
                        )
                        .font(
                            .system(
                                size: 20,
                                weight: .bold,
                                design: .rounded
                            )
                        )

                        Text(
                            "Created by Peter Grigorian"
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
                    }


                    Spacer()
                }


                Divider()
                    .opacity(0.35)


                HStack(
                    spacing: 8
                ) {

                    Button(
                        "Contact"
                    ) {

                        print(
                            "🍊 SETTINGS → Contact"
                        )
                    }

                    Button(
                        "Report a Bug"
                    ) {

                        print(
                            "🍊 SETTINGS → Report a Bug"
                        )
                    }
                }
                .buttonStyle(
                    .bordered
                )
            }
        }
    }


    // MARK: - Shared Components

    private func pageHeader(
        _ title: String,
        subtitle: String
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 4
        ) {

            Text(
                title
            )
            .font(
                .system(
                    size: 25,
                    weight: .bold,
                    design: .rounded
                )
            )

            Text(
                subtitle
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
        }
    }


    private func settingsCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content:
            () -> Content
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 13
        ) {

            VStack(
                alignment: .leading,
                spacing: 3
            ) {

                Text(
                    title
                )
                .font(
                    .system(
                        size: 13,
                        weight: .semibold
                    )
                )

                Text(
                    subtitle
                )
                .font(
                    .system(
                        size: 10,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    Color.secondary
                )
            }


            content()
        }
        .padding(16)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background {

            // Settings cards intentionally use a compositor-stable surface rather
            // than live Liquid Glass.  The cards sit inside a scrolling NSScrollView;
            // backdrop-sampling every card while that scroll view moves was forcing
            // the window compositor to rebuild several glass regions every frame.
            // The visual recipe below keeps the same translucent raised appearance
            // but is made only from ordinary fills/gradients, so scrolling does not
            // continuously resample the window behind each card.
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .fill(
                colorScheme == .light
                ? Color.white.opacity(0.36)
                : Color.white.opacity(0.055)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(colorScheme == .light ? 0.030 : 0.045),
                                Color.clear,
                                settingsManager.accentHighlightColor.opacity(colorScheme == .light ? 0.018 : 0.028)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .overlay {

            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(
                    0.18
                ),
                lineWidth: 0.7
            )
        }
        .overlay {

            RoundedRectangle(
                cornerRadius: 15,
                style: .continuous
            )
            .inset(
                by: 1
            )
            .stroke(
                accentColor.opacity(
                    0.075
                ),
                lineWidth: 0.7
            )
        }
    }


    private func settingsActionButton(
        _ title: String,
        symbol: String,
        destructive: Bool = false,
        action:
            @escaping () -> Void
    ) -> some View {

        Button(
            action: action
        ) {

            Label(
                title,
                systemImage:
                    symbol
            )
            .font(
                .system(
                    size: 11,
                    weight: .semibold
                )
            )
            .padding(
                .horizontal,
                12
            )
            .frame(
                height: 34
            )
        }
        .buttonStyle(
            .bordered
        )
        .tint(
            destructive
            ? Color.red
            : accentColor
        )
        .focusable(false)
    }


    // MARK: - Version

    private var versionDescription:
        String {

        let dictionary =
            Bundle.main
                .infoDictionary

        let version =
            dictionary?[
                "CFBundleShortVersionString"
            ] as? String
            ?? "Development"

        let build =
            dictionary?[
                "CFBundleVersion"
            ] as? String
            ?? "—"

        return
            "Version \(version) • Build \(build)"
    }


    // MARK: - Background

    private var settingsBackground:
        some View {

        ZStack {

            Color(
                nsColor:
                    .windowBackgroundColor
            )


            LinearGradient(
                colors: [
                    accentColor.opacity(
                        0.075
                    ),
                    Color.clear,
                    settingsManager
                        .accentHighlightColor
                        .opacity(
                            0.028
                        )
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            )


            // Keep the Settings window background visually translucent without a
            // full-window live material layer.  A live material behind a scrolling
            // hierarchy makes every scroll tick a backdrop-compositing event.
            LinearGradient(
                colors: [
                    colorScheme == .light ? Color.white.opacity(0.16) : Color.white.opacity(0.018),
                    accentColor.opacity(colorScheme == .light ? 0.018 : 0.026),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}
