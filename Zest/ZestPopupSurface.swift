//
//  ZestPopupSurface.swift
//  Zest
//
//  0.1.2 — canonical runtime popup material.
//  The default surface intentionally mirrors Clipboard's original rear glass.
//

import SwiftUI
import AppKit

private struct ZestPopupSurfaceModifier: ViewModifier {
    let accentColor: Color
    let cornerRadius: CGFloat

    @AppStorage("zest.settings.increaseVisibility")
    private var increaseVisibility = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )

        content
            .background {
                ZStack {
                    // Canonical Zest popup glass: copied from the original
                    // Clipboard panel rear material.
                    Color.clear
                        .glassEffect(
                            .regular.tint(accentColor.opacity(0.035)),
                            in: shape
                        )

                    shape
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.18), location: 0),
                                    .init(color: Color.white.opacity(0.065), location: 0.28),
                                    .init(color: Color.clear, location: 0.62),
                                    .init(color: Color.black.opacity(0.035), location: 1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    shape
                        .fill(
                            RadialGradient(
                                colors: [
                                    accentColor.opacity(0.075),
                                    Color.clear
                                ],
                                center: UnitPoint(x: 0.86, y: 0.18),
                                startRadius: 0,
                                endRadius: 170
                            )
                        )

                    // Accessibility visibility mode deliberately adds an
                    // opaque backing, but it sits on top of the same factory
                    // glass recipe rather than replacing it with another style.
                    if increaseVisibility {
                        shape
                            .fill(
                                Color(nsColor: .windowBackgroundColor)
                                    .opacity(0.76)
                            )
                    }

                    shape
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(increaseVisibility ? 0.55 : 0.88),
                                    Color.white.opacity(increaseVisibility ? 0.24 : 0.36),
                                    Color.white.opacity(increaseVisibility ? 0.10 : 0.14)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.9
                        )
                }
                .allowsHitTesting(false)
            }
            .shadow(
                color: Color.black.opacity(increaseVisibility ? 0.20 : 0.13),
                radius: increaseVisibility ? 18 : 15,
                y: 8
            )
            .clipShape(shape)
    }
}

extension View {
    func zestPopupSurface(
        accentColor: Color,
        cornerRadius: CGFloat = 22
    ) -> some View {
        modifier(
            ZestPopupSurfaceModifier(
                accentColor: accentColor,
                cornerRadius: cornerRadius
            )
        )
    }
}

private struct ZestVisibilityBackdropModifier: ViewModifier {
    let cornerRadius: CGFloat

    @AppStorage("zest.settings.increaseVisibility")
    private var increaseVisibility = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if increaseVisibility {
            content.background {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .fill(
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(0.78)
                )
                .shadow(
                    color: Color.black.opacity(0.18),
                    radius: 18,
                    y: 8
                )
            }
        } else {
            content
        }
    }
}

extension View {
    func zestVisibilityBackdrop(cornerRadius: CGFloat = 24) -> some View {
        modifier(ZestVisibilityBackdropModifier(cornerRadius: cornerRadius))
    }
}
