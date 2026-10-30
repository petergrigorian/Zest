//
//  ZestWelcomeHeroAnimation.swift
//  Zest
//
//  Shared onboarding / post-update intro animation.
//

import SwiftUI

struct ZestWelcomeHeroAnimation: View {
    let accent: ZestAccent
    let assembled: Bool
    let centerPowered: Bool
    let centerShineProgress: CGFloat
    let reduceMotion: Bool
    var scale: CGFloat = 1.55

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = accent.palette
        let heroSize = 210 * scale

        ZStack {
            ZestV34SliceAssemblyShell(
                accentColor: palette.primary,
                accentHighlightColor: palette.highlight,
                accentDeepColor: palette.deep,
                showInstalledGlass: false,
                showsEmptySockets: false,
                centerOpacity: 0,
                centerGlowIntensity: 0
            )
            .frame(width: heroSize, height: heroSize)
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.34 : 0.18),
                radius: 18 * scale,
                y: 9 * scale
            )

            ForEach(ZestV34SliceVisualSlot.all) { slot in
                let i = slot.id
                let radians = slot.centerAngle * .pi / 180
                let travel = 76.0 * scale
                let colors = accent.displayColors
                let pieceColor = colors[i % colors.count]

                ZestV34LiquidGlassWedgePiece(
                    accentColor: pieceColor,
                    accentHighlightColor: pieceColor,
                    accentDeepColor: pieceColor,
                    symbol: "circle",
                    title: "",
                    installed: true,
                    labelCounterRotationDegrees: 0,
                    usesLiveGlass: true,
                    labelOpacity: 0,
                    labelRevealScale: 1,
                    visualSlotID: slot.id
                )
                .frame(width: heroSize, height: heroSize)
                .rotationEffect(.degrees(assembled || reduceMotion ? 0 : (i.isMultiple(of: 2) ? -7 : 7)))
                .offset(
                    x: assembled || reduceMotion ? 0 : cos(radians) * travel,
                    y: assembled || reduceMotion ? 0 : sin(radians) * travel
                )
                .scaleEffect(assembled || reduceMotion ? 1 : 0.86)
                .brightness(colorScheme == .dark ? 0.055 : 0)
                .shadow(
                    color: pieceColor.opacity(colorScheme == .dark ? 0.22 : 0.12),
                    radius: assembled ? 4 * scale : 8 * scale
                )
                .animation(
                    reduceMotion ? nil : .spring(response: 0.52 + Double(i) * 0.035, dampingFraction: 0.76).delay(Double(i) * 0.045),
                    value: assembled
                )
            }

            ZestV34SliceAssemblyShell(
                accentColor: palette.primary,
                accentHighlightColor: palette.highlight,
                accentDeepColor: palette.deep,
                showInstalledGlass: false,
                showsEmptySockets: false,
                centerOpacity: assembled || reduceMotion ? 1 : 0,
                centerGlowIntensity: centerPowered ? 1 : 0,
                centerShineProgress: centerShineProgress
            )
            .frame(width: heroSize, height: heroSize)
            .mask {
                Circle().frame(width: 96 * scale, height: 96 * scale)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.40, dampingFraction: 0.82).delay(0.22), value: assembled)
        }
        .frame(width: heroSize, height: heroSize)
    }
}
