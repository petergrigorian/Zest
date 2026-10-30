//
//  ZestRapidSymbolHUD.swift
//  Zest
//

import SwiftUI
import AppKit

@MainActor
final class ZestRapidSymbolHUDController {
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    func showMappings(_ mappings: [String: String]) {
        hideWorkItem?.cancel()
        let panel = panel ?? makePanel()
        self.panel = panel

        panel.contentView = NSHostingView(
            rootView: ZestRapidSymbolMappingHUDView(
                mappings: mappings,
                accent: currentAccent
            )
        )

        show(panel, size: NSSize(width: 360, height: 245), autoHideAfter: nil)
    }

    func showMessage(title: String, symbol: String, subtitle: String) {
        hideWorkItem?.cancel()
        let panel = panel ?? makePanel()
        self.panel = panel

        panel.contentView = NSHostingView(
            rootView: ZestRapidSymbolMessageHUDView(
                title: title,
                symbol: symbol,
                subtitle: subtitle,
                accent: currentAccent
            )
        )

        show(panel, size: NSSize(width: 260, height: 150), autoHideAfter: 1.0)
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        panel?.orderOut(nil)
    }

    private var currentAccent: ZestAccent {
        ZestAccent(
            rawValue: UserDefaults.standard.string(forKey: "zest.settings.accent") ?? "orange"
        ) ?? .orange
    }

    private func show(_ panel: NSPanel, size: NSSize, autoHideAfter: TimeInterval?) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        panel.setFrame(
            NSRect(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            ),
            display: true
        )

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        guard let autoHideAfter else { return }
        let work = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
            self.hideWorkItem = nil
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHideAfter, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 245),
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
        return panel
    }
}

private struct ZestRapidSymbolMappingHUDView: View {
    let mappings: [String: String]
    let accent: ZestAccent

    private let order = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]

    var body: some View {
        let palette = accent.palette
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("Rapid Symbols", systemImage: "sparkles")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Text("press one key · esc cancels")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(order, id: \.self) { key in
                    if let symbol = mappings[key] {
                        HStack(spacing: 8) {
                            Text(key)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 24)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                            Text(symbol)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 40)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.035))
                                .glassEffect(
                                    .regular.tint(palette.primary.opacity(0.025)),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.22), lineWidth: 0.7)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 360, height: 245)
        .zestPopupSurface(
            accentColor: palette.primary,
            cornerRadius: 26
        )
    }
}

private struct ZestRapidSymbolMessageHUDView: View {
    let title: String
    let symbol: String
    let subtitle: String
    let accent: ZestAccent

    var body: some View {
        let palette = accent.palette
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(palette.primary.opacity(0.22))
                    .frame(width: 70, height: 70)
                    .glassEffect(.regular.tint(palette.primary.opacity(0.38)), in: Circle())
                Text(symbol)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .frame(width: 260, height: 150)
        .zestPopupSurface(
            accentColor: palette.primary,
            cornerRadius: 26
        )
    }
}
