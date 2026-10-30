//
//  ZestLayoutFixShortcutUI.swift
//  Zest
//
//  0.1.2 — shortcut-first Layout Fix configuration + circular confirmation HUD.
//

import SwiftUI
import AppKit
import Combine
import Carbon

struct ZestLayoutFixSetupView: View {
    @ObservedObject var settingsManager: ZestSettingsManager
    @StateObject private var inputSources = InputSourceManager()
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                Label("Layout Fix", systemImage: "keyboard.badge.ellipsis")
                    .font(.system(size: 16, weight: .bold, design: .rounded))

                Spacer()

                Toggle("Enabled", isOn: $settingsManager.layoutFixEnabled)
                    .toggleStyle(.switch)
                    .tint(accentColor)
                    .labelsHidden()
            }

            Text("Layout Fix uses the native macOS Services text pipeline. Select text in any compatible app and press the native shortcut shown beside the target language. The source app hands the real selection directly to Zest and accepts the corrected text back in place.")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Image(systemName: "arrow.left.arrow.right.square")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(accentColor.opacity(0.10)))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Native shortcut transport")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    Text("Save installs contextual macOS Service shortcuts: ⌃⇧1 through ⌃⇧9. The Services menu remains available as a fallback. If a source app was already open when you changed assignments, reopen that app once so macOS refreshes its Services shortcuts.")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Installed input sources")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("Refresh") { inputSources.refresh() }
                        .buttonStyle(.plain)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sortedSources) { source in
                            sourceRow(source)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(.vertical, 2)
                    .animation(
                        .spring(response: 0.30, dampingFraction: 0.86),
                        value: settingsManager.layoutFixTargets
                    )
                }
                .frame(maxHeight: 360)
            }

            Text("Selected languages move to the top. The number is the final native shortcut: 1 = ⌃⇧1, 2 = ⌃⇧2, and so on. Latin and Cyrillic keyboard layouts are supported in this build; IME-based input methods such as Chinese remain visible but cannot be assigned yet.")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 980, alignment: .topLeading)
        .onAppear { inputSources.refresh() }
    }

    private var sortedSources: [ZestInputSource] {
        inputSources.sources.sorted { lhs, rhs in
            let leftEnabled = target(for: lhs) != nil
            let rightEnabled = target(for: rhs) != nil

            if leftEnabled != rightEnabled {
                return leftEnabled && !rightEnabled
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func target(for source: ZestInputSource) -> ZestLayoutFixTarget? {
        settingsManager.layoutFixTargets.first(where: { $0.inputSourceID == source.id })
    }

    @ViewBuilder
    private func sourceRow(_ source: ZestInputSource) -> some View {
        let kind = ZestPhysicalKeyboardLayoutMapper.shared.supportKind(for: source)
        let supported = kind != .unsupported
        let currentTarget = target(for: source)
        let enabled = currentTarget != nil

        HStack(spacing: 12) {
            Toggle(
                isOn: Binding(
                    get: { target(for: source) != nil },
                    set: { setSource(source, enabled: $0) }
                )
            ) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(enabled ? accentColor.opacity(0.14) : Color.primary.opacity(0.045))
                            .frame(width: 44, height: 34)

                        Text(source.shortLabel)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(enabled ? accentColor : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.name)
                            .font(.system(size: 11, weight: .semibold))
                        Text(supported ? "\(kind.rawValue) keyboard layout" : "Not supported yet")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.checkbox)
            .tint(accentColor)
            .disabled(!supported)

            Spacer()

            if currentTarget != nil {
                HStack(spacing: 6) {
                    Text("⌃⇧")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    TextField(
                        "1",
                        text: digitBinding(for: source)
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(width: 22)
                    .help("Native Layout Fix shortcut: Control + Shift + this number")
                }
                .foregroundStyle(accentColor)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background {
                    Capsule().fill(accentColor.opacity(0.09))
                }
                .overlay {
                    Capsule()
                        .stroke(accentColor.opacity(0.20), lineWidth: 0.7)
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(enabled ? accentColor.opacity(0.045) : Color.primary.opacity(0.025))
        }
        .opacity(supported ? 1 : 0.48)
    }

    private func digitBinding(for source: ZestInputSource) -> Binding<String> {
        Binding(
            get: {
                target(for: source)?.triggerLabel ?? ""
            },
            set: { newValue in
                guard let digit = newValue.reversed().first(where: { "123456789".contains($0) }),
                      let option = ZestLayoutFixTarget.digitOptions.first(where: { $0.label == String(digit) })
                else { return }

                assignTrigger(option.keyCode, to: source)
            }
        )
    }

    private func setSource(_ source: ZestInputSource, enabled: Bool) {
        var targets = settingsManager.layoutFixTargets
        targets.removeAll(where: { $0.inputSourceID == source.id })

        if enabled {
            let used = Set(targets.map(\.triggerKeyCode))
            let option = ZestLayoutFixTarget.digitOptions.first(where: { !used.contains($0.keyCode) })
                ?? ZestLayoutFixTarget.digitOptions[targets.count % ZestLayoutFixTarget.digitOptions.count]

            targets.append(
                ZestLayoutFixTarget(
                    inputSourceID: source.id,
                    name: source.name,
                    shortLabel: source.shortLabel,
                    triggerKeyCode: option.keyCode
                )
            )
        }

        settingsManager.layoutFixTargets = targets
    }

    private func assignTrigger(_ keyCode: UInt16, to source: ZestInputSource) {
        var targets = settingsManager.layoutFixTargets
        guard let index = targets.firstIndex(where: { $0.inputSourceID == source.id }) else { return }

        let previousCode = targets[index].triggerKeyCode

        if let conflict = targets.firstIndex(where: {
            $0.triggerKeyCode == keyCode && $0.inputSourceID != source.id
        }) {
            targets[conflict].triggerKeyCode = previousCode
        }

        targets[index].triggerKeyCode = keyCode
        settingsManager.layoutFixTargets = targets
    }
}


@MainActor
private final class ZestLayoutFixHUDModel: ObservableObject {
    @Published var code = "…"
    @Published var targetName = "Press 1–9"
    @Published var transitionID = 0
    @Published var accent: ZestAccent = .orange

    func update(code: String, targetName: String, accent: ZestAccent, animated: Bool) {
        let changes = {
            self.code = code
            self.targetName = targetName
            self.accent = accent
            if animated { self.transitionID += 1 }
        }

        if animated {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) { changes() }
        } else {
            changes()
        }
    }
}

@MainActor
final class ZestLayoutFixHUDController {
    static let shared = ZestLayoutFixHUDController()

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?
    private let model = ZestLayoutFixHUDModel()

    func showArmed() {
        presentIfNeeded()
        update(code: "…", targetName: "Press 1–9", animated: false, hideAfter: 1.95)
    }

    func showPending(targetCode: String, targetName: String) {
        presentIfNeeded()
        update(code: targetCode, targetName: "Fixing to \(targetName)…", animated: true, hideAfter: 1.65)
    }

    func showFailure(message: String) {
        presentIfNeeded()
        update(code: "!", targetName: message, animated: true, hideAfter: 1.25)
    }

    func show(targetCode: String, targetName: String) {
        presentIfNeeded()
        update(code: targetCode, targetName: targetName, animated: true, hideAfter: 1.20)
    }

    private func update(
        code: String,
        targetName: String,
        animated: Bool,
        hideAfter delay: TimeInterval
    ) {
        hideWorkItem?.cancel()

        let accent = ZestAccent(
            rawValue: UserDefaults.standard.string(forKey: "zest.settings.accent") ?? "orange"
        ) ?? .orange

        model.update(code: code, targetName: targetName, accent: accent, animated: animated)

        guard let panel else { return }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.20
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
            self.hideWorkItem = nil
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func presentIfNeeded() {
        let panel = panel ?? makePanel()
        self.panel = panel

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size = NSSize(width: 245, height: 245)
        panel.setFrame(
            NSRect(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            ),
            display: true
        )

        if !panel.isVisible || panel.alphaValue < 0.01 {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 245, height: 245),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false

        // NSPanel already owns an empty contentView by default. Install the
        // SwiftUI host when the panel is created so the HUD can never become
        // an invisible transparent window.
        panel.contentView = NSHostingView(
            rootView: ZestLayoutFixHUDView(model: model)
        )

        return panel
    }
}

private struct ZestLayoutFixHUDView: View {
    @ObservedObject var model: ZestLayoutFixHUDModel
    @State private var appeared = false

    private var palette: ZestAccentPalette { model.accent.palette }

    var body: some View {
        ZStack {
            Circle()
                .fill(palette.deep.opacity(0.13))
                .frame(width: 194, height: 194)
                .glassEffect(.regular.tint(palette.primary.opacity(0.17)), in: Circle())
                .overlay {
                    Circle().stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.72),
                                palette.highlight.opacity(0.30),
                                palette.deep.opacity(0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                }
                .shadow(color: .black.opacity(0.22), radius: 14, y: 8)

            Circle()
                .fill(
                    RadialGradient(
                        colors: model.accent.displayColors.map { $0.opacity(0.29) },
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: 102
                    )
                )
                .frame(width: 180, height: 180)
                .glassEffect(.regular.tint(palette.primary.opacity(0.28)), in: Circle())
                .overlay { Circle().stroke(Color.white.opacity(0.48), lineWidth: 0.8) }

            ZStack {
                Text(model.code)
                    .id(model.transitionID)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                    )
            }
            .frame(width: 120, height: 48)
            .clipped()
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.96))
            .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
            .offset(y: -48)

            Circle()
                .fill(palette.deep.opacity(0.17))
                .frame(width: 62, height: 62)
                .glassEffect(.regular.tint(palette.primary.opacity(0.44)), in: Circle())
                .overlay { Circle().stroke(Color.white.opacity(0.56), lineWidth: 0.9) }
                .overlay {
                    Image(systemName: "keyboard.badge.ellipsis")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.96))
                }

            // Match the Center-Only language HUD: the feature name follows
            // the lower half of the circle instead of sitting across the top.
            curvedText("Layout Fix", radius: 72)

            // No horizontal Layout Fix/status text box in the HUD.
        }
        .frame(width: 245, height: 245)
        .scaleEffect(appeared ? 1 : 0.88)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                appeared = true
            }
        }
    }

    private func curvedText(_ text: String, radius: CGFloat) -> some View {
        let characters = Array(text)
        let count = max(characters.count, 1)
        let maximumSpan = min(150.0, 58.0 + Double(max(count - 1, 0)) * 11.5)
        let startAngle = 90.0 + maximumSpan / 2.0
        let step = count > 1 ? maximumSpan / Double(count - 1) : 0

        return ZStack {
            ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                let angle = startAngle - Double(index) * step
                let radians = angle * Double.pi / 180

                Text(String(character))
                    .font(.system(size: 6.8, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .rotationEffect(.degrees(angle - 90))
                    .offset(
                        x: CGFloat(cos(radians)) * radius,
                        y: CGFloat(sin(radians)) * radius
                    )
            }
        }
    }
}
