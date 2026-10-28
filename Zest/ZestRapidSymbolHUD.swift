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

    func show(
        title: String,
        symbol: String,
        subtitle: String
    ) {
        hideWorkItem?.cancel()

        let accent =
            ZestAccent(
                rawValue:
                    UserDefaults.standard.string(
                        forKey: "zest.settings.accent"
                    ) ?? "orange"
            ) ?? .orange

        let panel = panel ?? makePanel()
        self.panel = panel

        panel.contentView = NSHostingView(
            rootView:
                ZestRapidSymbolHUDView(
                    title: title,
                    symbol: symbol,
                    subtitle: subtitle,
                    accent: accent
                )
        )

        guard let screen =
                NSScreen.main ??
                NSScreen.screens.first else {
            return
        }

        let size =
            NSSize(width: 260, height: 150)

        let frame =
            NSRect(
                x: screen.visibleFrame.midX -
                    size.width / 2,
                y: screen.visibleFrame.midY -
                    size.height / 2,
                width: size.width,
                height: size.height
            )

        panel.setFrame(
            frame,
            display: true
        )

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup {
            context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        let work = DispatchWorkItem {
            [weak self, weak panel] in

            guard let self,
                  let panel else {
                return
            }

            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = 0.18
                    panel.animator().alphaValue = 0
                },
                completionHandler: {
                    panel.orderOut(nil)
                }
            )

            self.hideWorkItem = nil
        }

        hideWorkItem = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 1.0,
            execute: work
        )
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect:
                NSRect(
                    x: 0,
                    y: 0,
                    width: 260,
                    height: 150
                ),
            styleMask: [
                .borderless,
                .nonactivatingPanel
            ],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient
        ]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false

        return panel
    }
}

private struct ZestRapidSymbolHUDView: View {
    let title: String
    let symbol: String
    let subtitle: String
    let accent: ZestAccent

    var body: some View {
        let palette = accent.palette

        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        palette.primary.opacity(0.22)
                    )
                    .frame(width: 70, height: 70)
                    .glassEffect(
                        .regular.tint(
                            palette.primary.opacity(0.38)
                        ),
                        in: Circle()
                    )

                Text(symbol)
                    .font(
                        .system(
                            size: 28,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)
            }

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(title)
                    .font(
                        .system(
                            size: 14,
                            weight: .bold,
                            design: .rounded
                        )
                    )

                Text(subtitle)
                    .font(
                        .system(
                            size: 10,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 260, height: 150)
        .background {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .fill(.regularMaterial)
            .glassEffect(
                .regular.tint(
                    palette.primary.opacity(0.18)
                ),
                in:
                    RoundedRectangle(
                        cornerRadius: 26,
                        style: .continuous
                    )
            )
        }
    }
}
