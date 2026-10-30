import SwiftUI


// MARK: - Production Center Only Language Turntable

/// Shared production renderer for the Center Only language turntable.
///
/// This is intentionally used by both the in-field Zest runtime and the
/// onboarding guide. Keeping one renderer prevents the tutorial from drifting
/// away from the real control as its glass, geometry, or typography evolves.
struct ZestV34CenterOnlyLanguageTurntable: View {

    let accentColor: Color
    let accentBrightColor: Color
    let accentHighlightColor: Color
    let accentDeepColor: Color
    let rearGlassPrimaryColor: Color
    let rearGlassBrightColor: Color

    let shortLabel: String
    let sourceName: String

    var languageRotation: Double = 0
    var languageOpacity: Double = 1
    var forceVibrantRendering: Bool = false

    /// Tutorial-only press states. Production leaves these at their defaults
    /// and gets its normal interactive glass response from the Buttons.
    var pressedDirection: Int = 0
    var settingsPressed: Bool = false

    var onPrevious: () -> Void = {}
    var onNext: () -> Void = {}
    var onSettings: () -> Void = {}

    @State private var settingsGearHover = false

    private let diameter: CGFloat = 78

    var body: some View {
        ZStack {
            // One continuous glossy shell surrounds both language tabs.
            Capsule()
                .fill(rearGlassBrightColor.opacity(0.10))
                .frame(width: diameter + 68, height: 37)
                .glassEffect(
                    .regular.tint(rearGlassPrimaryColor.opacity(0.12)),
                    in: Capsule()
                )
                .overlay {
                    Capsule().stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.56),
                                accentHighlightColor.opacity(0.16),
                                accentDeepColor.opacity(0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
                }
                .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
                .zIndex(-4)

            languageWing(systemImage: "chevron.left", direction: -1)
                .offset(x: -(diameter / 2 + 10))

            languageWing(systemImage: "chevron.right", direction: 1)
                .offset(x: diameter / 2 + 10)

            // Physical outer ring.
            Circle()
                .fill(
                    (forceVibrantRendering ? accentColor : accentBrightColor)
                        .opacity(forceVibrantRendering ? 0.66 : 0.030)
                )
                .frame(width: diameter + 8, height: diameter + 8)
                .offset(y: 1.1)

            Color.clear
                .frame(width: diameter + 8, height: diameter + 8)
                .glassEffect(
                    .regular.tint(accentColor.opacity(0.095)),
                    in: Circle()
                )

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.86),
                            Color.white.opacity(0.28),
                            accentHighlightColor.opacity(0.13),
                            accentDeepColor.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.85
                )
                .frame(width: diameter + 8, height: diameter + 8)

            // Main CRT face.
            Circle()
                .fill(
                    (forceVibrantRendering ? accentColor : accentBrightColor)
                        .opacity(forceVibrantRendering ? 0.70 : 0.050)
                )
                .frame(width: diameter, height: diameter)
                .offset(y: 1.2)

            Color.clear
                .frame(width: diameter, height: diameter)
                .glassEffect(
                    .regular
                        .tint(accentColor.opacity(forceVibrantRendering ? 0.68 : 0.24))
                        .interactive(),
                    in: Circle()
                )

            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.16), location: 0),
                            .init(color: accentHighlightColor.opacity(0.09), location: 0.30),
                            .init(color: Color.clear, location: 0.72)
                        ],
                        center: UnitPoint(x: 0.28, y: 0.16),
                        startRadius: 0,
                        endRadius: 65
                    )
                )
                .frame(width: diameter, height: diameter)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.clear,
                            accentColor.opacity(0.018),
                            Color.black.opacity(0.075)
                        ],
                        center: .center,
                        startRadius: diameter * 0.22,
                        endRadius: diameter * 0.50
                    )
                )
                .frame(width: diameter - 5, height: diameter - 5)
                .allowsHitTesting(false)

            VStack(spacing: 3.2) {
                ForEach(0..<13, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.018))
                        .frame(height: 0.7)
                }
            }
            .frame(width: diameter - 13, height: diameter - 13)
            .clipShape(Circle())
            .allowsHitTesting(false)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.92),
                            Color.white.opacity(0.34),
                            accentHighlightColor.opacity(0.16),
                            accentColor.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
                .frame(width: diameter, height: diameter)

            languageDial

            settingsBadge
                .zIndex(20)
        }
        .frame(width: diameter + 100, height: diameter + 72)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private var languageDial: some View {
        ZStack {
            Text(shortLabel)
                .font(.system(size: 16.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.86))
                .offset(y: -25)

            arcText(sourceName, radius: 27)
        }
        .rotationEffect(.degrees(languageRotation))
        .opacity(languageOpacity)
        .allowsHitTesting(false)
        .frame(width: diameter, height: diameter)
    }

    private func arcText(_ text: String, radius: CGFloat) -> some View {
        let characters = Array(text)
        let count = max(characters.count, 1)
        let maximumSpan = min(150.0, 58.0 + Double(max(count - 1, 0)) * 11.5)
        let startAngle = 90.0 + maximumSpan / 2.0
        let step = count > 1 ? maximumSpan / Double(count - 1) : 0

        return ZStack {
            ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                let angle = startAngle - Double(index) * step
                let radians = angle * Double.pi / 180
                let x = cos(radians) * radius
                let y = sin(radians) * radius

                Text(String(character))
                    .font(.system(size: 6.8, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.80))
                    .rotationEffect(.degrees(angle - 90))
                    .offset(x: x, y: y)
            }
        }
    }

    private func languageWing(systemImage: String, direction: Int) -> some View {
        Button {
            if direction < 0 { onPrevious() } else { onNext() }
        } label: {
            ZStack {
                Color.clear
                    .frame(width: 48, height: 42)

                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.76))
                    .frame(width: 40, height: 29)
                    .offset(x: direction < 0 ? -4 : 4)
                    .background {
                        Color.clear
                            .frame(width: 40, height: 29)
                            .glassEffect(
                                .regular.tint(accentColor.opacity(0.24)).interactive(),
                                in: UnevenRoundedRectangle(
                                    topLeadingRadius: direction < 0 ? 15 : 4,
                                    bottomLeadingRadius: direction < 0 ? 15 : 4,
                                    bottomTrailingRadius: direction > 0 ? 15 : 4,
                                    topTrailingRadius: direction > 0 ? 15 : 4
                                )
                            )
                    }
                    .overlay {
                        UnevenRoundedRectangle(
                            topLeadingRadius: direction < 0 ? 15 : 4,
                            bottomLeadingRadius: direction < 0 ? 15 : 4,
                            bottomTrailingRadius: direction > 0 ? 15 : 4,
                            topTrailingRadius: direction > 0 ? 15 : 4
                        )
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.72),
                                    accentHighlightColor.opacity(0.20),
                                    accentDeepColor.opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                    }
            }
            .contentShape(Rectangle())
            .scaleEffect(pressedDirection == direction ? 0.86 : 1)
            .brightness(pressedDirection == direction ? 0.08 : 0)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .zIndex(-1)
    }

    private var settingsBadge: some View {
        let buttonSize: CGFloat = 29

        return Button(action: onSettings) {
            ZStack {
                Circle()
                    .fill(accentDeepColor.opacity(0.18))
                    .frame(width: buttonSize + 3, height: buttonSize + 3)
                    .offset(y: 1.8)

                Circle()
                    .fill(accentBrightColor.opacity(0.060))
                    .frame(width: buttonSize, height: buttonSize)

                Color.clear
                    .frame(width: buttonSize, height: buttonSize)
                    .glassEffect(
                        .regular.tint(accentColor.opacity(0.23)).interactive(),
                        in: Circle()
                    )

                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.20), location: 0),
                                .init(color: accentHighlightColor.opacity(0.10), location: 0.38),
                                .init(color: Color.clear, location: 0.82)
                            ],
                            center: UnitPoint(x: 0.30, y: 0.18),
                            startRadius: 0,
                            endRadius: buttonSize
                        )
                    )
                    .frame(width: buttonSize - 2, height: buttonSize - 2)

                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.84))
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(settingsGearHover ? 180 : 0))
            }
            .overlay {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.82),
                                Color.white.opacity(0.28),
                                accentHighlightColor.opacity(0.18),
                                accentDeepColor.opacity(0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.85
                    )
            }
            .shadow(color: .black.opacity(0.18), radius: 3.5, y: 2.4)
            .shadow(color: accentColor.opacity(0.09), radius: 3, y: 1)
            .contentShape(Circle())
            .scaleEffect(settingsPressed ? 0.88 : 1)
            .brightness(settingsPressed ? 0.08 : 0)
        }
        .buttonStyle(.plain)
        .frame(width: 38, height: 38)
        .contentShape(Circle())
        .focusable(false)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.58)) {
                settingsGearHover = hovering
            }
        }
    }
}


// MARK: - Production Center Only Clock / Calendar Turntable

enum ZestV34CenterTopDisplayKind {
    case clock
    case calendar
}

/// One physical Center Only face that flips between Clock and Calendar.
/// Its interaction and face-transition state are intentionally driven by the
/// parent exactly like the production language turntable.
struct ZestV34CenterOnlyClockCalendarTurntable: View {
    let accentColor: Color
    let accentBrightColor: Color
    let accentHighlightColor: Color
    let accentDeepColor: Color
    let rearGlassPrimaryColor: Color
    let rearGlassBrightColor: Color

    var showsCalendar: Bool
    var faceRotation: Double = 0
    var faceOpacity: Double = 1
    var forceVibrantRendering: Bool = false
    var diameter: CGFloat = 78

    var onToggle: () -> Void = {}
    var onSettings: () -> Void = {}
    var onDragChanged: ((_ translation: CGSize, _ ended: Bool) -> Void)? = nil

    @State private var settingsGearHover = false

    private var scale: CGFloat { min(max(diameter / 78, 1), 2.35) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack {
                Capsule()
                    .fill(rearGlassBrightColor.opacity(0.10))
                    .frame(width: diameter + 68 * scale, height: 37 * scale)
                    .glassEffect(.regular.tint(rearGlassPrimaryColor.opacity(0.12)), in: Capsule())
                    .overlay {
                        Capsule().stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.56),
                                    accentHighlightColor.opacity(0.16),
                                    accentDeepColor.opacity(0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8 * scale
                        )
                    }
                    .shadow(color: .black.opacity(0.12), radius: 3 * scale, y: 2 * scale)
                    .zIndex(-4)

                dragWing
                    .offset(x: -(diameter / 2 + 10 * scale))

                toggleWing
                    .offset(x: diameter / 2 + 10 * scale)

                ringShell

                faceContent(now: context.date)
                    .rotationEffect(.degrees(faceRotation))
                    .opacity(faceOpacity)
                    .allowsHitTesting(false)

                settingsBadge
                    .zIndex(30)
            }
        }
        .frame(width: 178 * scale, height: 150 * scale)
        .shadow(color: .black.opacity(0.15), radius: 4 * scale, y: 2 * scale)
    }

    private var ringShell: some View {
        ZStack {
            Circle()
                .fill((forceVibrantRendering ? accentColor : accentBrightColor).opacity(forceVibrantRendering ? 0.66 : 0.030))
                .frame(width: diameter + 8 * scale, height: diameter + 8 * scale)
                .offset(y: 1.1 * scale)

            Color.clear
                .frame(width: diameter + 8 * scale, height: diameter + 8 * scale)
                .glassEffect(.regular.tint(accentColor.opacity(0.095)), in: Circle())

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.86), Color.white.opacity(0.28), accentHighlightColor.opacity(0.13), accentDeepColor.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.85 * scale
                )
                .frame(width: diameter + 8 * scale, height: diameter + 8 * scale)

            Circle()
                .fill((forceVibrantRendering ? accentColor : accentBrightColor).opacity(forceVibrantRendering ? 0.70 : 0.050))
                .frame(width: diameter, height: diameter)
                .offset(y: 1.2 * scale)

            Color.clear
                .frame(width: diameter, height: diameter)
                .glassEffect(.regular.tint(accentColor.opacity(forceVibrantRendering ? 0.68 : 0.24)).interactive(), in: Circle())

            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.16), location: 0),
                            .init(color: accentHighlightColor.opacity(0.09), location: 0.30),
                            .init(color: Color.clear, location: 0.72)
                        ],
                        center: UnitPoint(x: 0.28, y: 0.16),
                        startRadius: 0,
                        endRadius: diameter * 0.82
                    )
                )
                .frame(width: diameter, height: diameter)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.clear, accentColor.opacity(0.018), Color.black.opacity(0.075)],
                        center: .center,
                        startRadius: diameter * 0.22,
                        endRadius: diameter * 0.50
                    )
                )
                .frame(width: diameter - 5 * scale, height: diameter - 5 * scale)
                .allowsHitTesting(false)

            VStack(spacing: 3.2 * scale) {
                ForEach(0..<13, id: \.self) { _ in
                    Rectangle().fill(Color.black.opacity(0.018)).frame(height: max(0.7, 0.7 * scale))
                }
            }
            .frame(width: diameter - 13 * scale, height: diameter - 13 * scale)
            .clipShape(Circle())
            .allowsHitTesting(false)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.92), Color.white.opacity(0.34), accentHighlightColor.opacity(0.16), accentColor.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9 * scale
                )
                .frame(width: diameter, height: diameter)
        }
    }

    @ViewBuilder
    private func faceContent(now: Date) -> some View {
        if showsCalendar {
            calendarFace(now: now)
        } else {
            analogClockFace(now: now)
        }
    }

    private func analogClockFace(now: Date) -> some View {
        let calendar = Calendar.current
        let hour = Double(calendar.component(.hour, from: now) % 12)
        let minute = Double(calendar.component(.minute, from: now))
        let second = Double(calendar.component(.second, from: now))
        let hourAngle = (hour + minute / 60) * 30
        let minuteAngle = minute * 6 + second * 0.1

        return ZStack {
            // Keep only the intermediate hour marks. 12 / 3 / 6 / 9 are
            // represented by their numerals, so those four divider ticks stay clear.
            ForEach([1, 2, 4, 5, 7, 8, 10, 11], id: \.self) { index in
                let angle = Double(index) * 30.0 - 90.0
                let radians = angle * Double.pi / 180
                let outer = diameter * 0.40
                let inner = diameter * 0.355
                Path { path in
                    path.move(
                        to: CGPoint(
                            x: diameter / 2 + CGFloat(cos(radians)) * inner,
                            y: diameter / 2 + CGFloat(sin(radians)) * inner
                        )
                    )
                    path.addLine(
                        to: CGPoint(
                            x: diameter / 2 + CGFloat(cos(radians)) * outer,
                            y: diameter / 2 + CGFloat(sin(radians)) * outer
                        )
                    )
                }
                .stroke(
                    Color.primary.opacity(0.34),
                    style: StrokeStyle(
                        lineWidth: max(0.85, diameter * 0.009),
                        lineCap: .round
                    )
                )
            }

            Text("12").offset(y: -diameter * 0.395)
            Text("3").offset(x: diameter * 0.395)
            Text("6").offset(y: diameter * 0.395)
            Text("9").offset(x: -diameter * 0.395)

            clockHand(angle: hourAngle, length: diameter * 0.34, width: max(2.3, diameter * 0.030))
            clockHand(angle: minuteAngle, length: diameter * 0.405, width: max(1.25, diameter * 0.016))
        }
        .font(.system(size: 9.4 * scale, weight: .bold, design: .rounded))
        .foregroundStyle(Color.primary.opacity(0.80))
        .frame(width: diameter, height: diameter)
    }

    private func clockHand(angle: Double, length: CGFloat, width: CGFloat) -> some View {
        let radians = (angle - 90) * Double.pi / 180
        let center = CGPoint(x: diameter / 2, y: diameter / 2)
        let end = CGPoint(
            x: center.x + CGFloat(cos(radians)) * length,
            y: center.y + CGFloat(sin(radians)) * length
        )

        return Path { path in
            path.move(to: center)
            path.addLine(to: end)
        }
        .stroke(Color.primary.opacity(0.72), style: StrokeStyle(lineWidth: width, lineCap: .round))
        .frame(width: diameter, height: diameter)
    }

    private func calendarFace(now: Date) -> some View {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: now)
        let year = String(calendar.component(.year, from: now))
        let firstHalf = String(year.prefix(2))
        let secondHalf = String(year.suffix(2))
        let month = Self.monthFormatter.string(from: now).uppercased()

        return ZStack {
            Text(String(day))
                .font(.system(size: 16.5 * scale, weight: .bold, design: .rounded))
                .offset(y: -25 * scale)

            HStack {
                Text(firstHalf)
                Spacer()
                Text(secondHalf)
            }
            .font(.system(size: 8.9 * scale, weight: .bold, design: .rounded))
            .frame(width: diameter * 0.82)
            .offset(y: -diameter * 0.02)

            Text(month)
                .font(.system(size: 10.4 * scale, weight: .bold, design: .rounded))
                .tracking(0.9 * scale)
                .offset(y: diameter * 0.34)
        }
        .foregroundStyle(Color.primary.opacity(0.82))
        .frame(width: diameter, height: diameter)
    }

    // Exact Language Turntable side-control hardware. The only differences are
    // semantic: the left badge drags the runtime panel and the right badge toggles
    // Clock / Calendar. Geometry, glass, masking and depth are copied verbatim.
    private var dragWing: some View {
        ZStack {
            Color.clear
                .frame(width: 48 * scale, height: 42 * scale)

            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 10.5 * scale, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.76))
                .frame(width: 40 * scale, height: 29 * scale)
                .offset(x: -4 * scale)
                .background {
                    Color.clear
                        .frame(width: 40 * scale, height: 29 * scale)
                        .glassEffect(
                            .regular.tint(accentColor.opacity(0.24)).interactive(),
                            in: UnevenRoundedRectangle(
                                topLeadingRadius: 15 * scale,
                                bottomLeadingRadius: 15 * scale,
                                bottomTrailingRadius: 4 * scale,
                                topTrailingRadius: 4 * scale
                            )
                        )
                }
                .overlay {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 15 * scale,
                        bottomLeadingRadius: 15 * scale,
                        bottomTrailingRadius: 4 * scale,
                        topTrailingRadius: 4 * scale
                    )
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.72),
                                accentHighlightColor.opacity(0.20),
                                accentDeepColor.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75 * scale
                    )
                }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    onDragChanged?(value.translation, false)
                }
                .onEnded { value in
                    onDragChanged?(value.translation, true)
                }
        )
        // The Language Turntable deliberately places its tabs behind the circle;
        // this is the key detail that makes the inner curtain disappear under the rim.
        .zIndex(-1)
    }

    // This is intentionally the exact same SwiftUI Button construction used by
    // the proven Language Turntable. The glass badge and the hit target are one
    // control again: same 48×42 interaction box, same 40×29 curtain, same +4 pt
    // icon inset, same rear z-index, and the same plain/focusless button behavior.
    private var toggleWing: some View {
        Button(action: onToggle) {
            ZStack {
                Color.clear
                    .frame(width: 48 * scale, height: 42 * scale)

                Image(systemName: showsCalendar ? "clock" : "calendar")
                    .font(.system(size: 10.5 * scale, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.76))
                    .frame(width: 40 * scale, height: 29 * scale)
                    .offset(x: 4 * scale)
                    .background {
                        Color.clear
                            .frame(width: 40 * scale, height: 29 * scale)
                            .glassEffect(
                                .regular.tint(accentColor.opacity(0.24)).interactive(),
                                in: UnevenRoundedRectangle(
                                    topLeadingRadius: 4 * scale,
                                    bottomLeadingRadius: 4 * scale,
                                    bottomTrailingRadius: 15 * scale,
                                    topTrailingRadius: 15 * scale
                                )
                            )
                    }
                    .overlay {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 4 * scale,
                            bottomLeadingRadius: 4 * scale,
                            bottomTrailingRadius: 15 * scale,
                            topTrailingRadius: 15 * scale
                        )
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.72),
                                    accentHighlightColor.opacity(0.20),
                                    accentDeepColor.opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75 * scale
                        )
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .zIndex(-1)
    }

    private var settingsBadge: some View {
        let buttonSize = min(max(diameter * 0.372, 29), 56)

        return Button(action: onSettings) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.20))
                    .frame(width: buttonSize + 6 * scale, height: buttonSize + 6 * scale)
                    .offset(y: 2.2 * scale)

                Circle()
                    .fill(accentDeepColor.opacity(0.18))
                    .frame(width: buttonSize + 3 * scale, height: buttonSize + 3 * scale)
                    .offset(y: 1.8 * scale)

                Circle()
                    .fill(accentBrightColor.opacity(0.060))
                    .frame(width: buttonSize, height: buttonSize)

                Color.clear
                    .frame(width: buttonSize, height: buttonSize)
                    .glassEffect(.regular.tint(accentColor.opacity(0.23)).interactive(), in: Circle())

                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.20), location: 0),
                                .init(color: accentHighlightColor.opacity(0.10), location: 0.38),
                                .init(color: Color.clear, location: 0.82)
                            ],
                            center: UnitPoint(x: 0.30, y: 0.18),
                            startRadius: 0,
                            endRadius: buttonSize
                        )
                    )
                    .frame(width: buttonSize - 2 * scale, height: buttonSize - 2 * scale)

                Image(systemName: "gearshape.fill")
                    .font(.system(size: min(11.5 * scale, 21), weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.84))
                    .rotationEffect(.degrees(settingsGearHover ? 180 : 0))
            }
            .overlay {
                Circle().stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.82), Color.white.opacity(0.28), accentHighlightColor.opacity(0.18), accentDeepColor.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.85 * scale
                )
            }
            .shadow(color: .black.opacity(0.18), radius: 3.5 * scale, y: 2.4 * scale)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: buttonSize + 10 * scale, height: buttonSize + 10 * scale)
        .contentShape(Circle())
        .focusable(false)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.58)) {
                settingsGearHover = hovering
            }
        }
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "MMM"
        return formatter
    }()
}



// MARK: - Production Turntable Language + Clock Hybrid

/// Language turntable hardware with a fixed Nokia-style clock occupying the
/// lower half. The language label rotates behind that fixed clock plate, while
/// the center Settings extrusion remains physically above both surfaces.
struct ZestV35LanguageClockTurntable: View {
    let accentColor: Color
    let accentBrightColor: Color
    let accentHighlightColor: Color
    let accentDeepColor: Color
    let rearGlassPrimaryColor: Color
    let rearGlassBrightColor: Color

    let shortLabel: String
    var languageRotation: Double = 0
    var languageOpacity: Double = 1
    var forceVibrantRendering: Bool = false
    var diameter: CGFloat = 78

    var onRotateLanguage: () -> Void = {}
    var onSettings: () -> Void = {}
    var onDragChanged: ((_ translation: CGSize, _ ended: Bool) -> Void)? = nil

    @State private var settingsGearHover = false

    private var scale: CGFloat { min(max(diameter / 78, 1), 2.35) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack {
                rearCapsule

                dragWing
                    .offset(x: -(diameter / 2 + 10 * scale))

                rotateWing
                    .offset(x: diameter / 2 + 10 * scale)

                ringShell

                languageLayer
                    .zIndex(2)

                bottomClockPlate(now: context.date)
                    .zIndex(6)

                settingsBadge
                    .zIndex(20)
            }
        }
        .frame(width: diameter + 100 * scale, height: diameter + 72 * scale)
        .shadow(color: .black.opacity(0.15), radius: 4 * scale, y: 2 * scale)
    }

    private var rearCapsule: some View {
        Capsule()
            .fill(rearGlassBrightColor.opacity(0.10))
            .frame(width: diameter + 68 * scale, height: 37 * scale)
            .glassEffect(.regular.tint(rearGlassPrimaryColor.opacity(0.12)), in: Capsule())
            .overlay {
                Capsule().stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.56),
                            accentHighlightColor.opacity(0.16),
                            accentDeepColor.opacity(0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8 * scale
                )
            }
            .shadow(color: .black.opacity(0.12), radius: 3 * scale, y: 2 * scale)
            .zIndex(-4)
    }

    private var ringShell: some View {
        ZStack {
            Circle()
                .fill((forceVibrantRendering ? accentColor : accentBrightColor).opacity(forceVibrantRendering ? 0.66 : 0.030))
                .frame(width: diameter + 8 * scale, height: diameter + 8 * scale)
                .offset(y: 1.1 * scale)

            Color.clear
                .frame(width: diameter + 8 * scale, height: diameter + 8 * scale)
                .glassEffect(.regular.tint(accentColor.opacity(0.095)), in: Circle())

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.86), Color.white.opacity(0.28), accentHighlightColor.opacity(0.13), accentDeepColor.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.85 * scale
                )
                .frame(width: diameter + 8 * scale, height: diameter + 8 * scale)

            Circle()
                .fill((forceVibrantRendering ? accentColor : accentBrightColor).opacity(forceVibrantRendering ? 0.70 : 0.050))
                .frame(width: diameter, height: diameter)
                .offset(y: 1.2 * scale)

            Color.clear
                .frame(width: diameter, height: diameter)
                .glassEffect(.regular.tint(accentColor.opacity(forceVibrantRendering ? 0.68 : 0.24)).interactive(), in: Circle())

            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.16), location: 0),
                            .init(color: accentHighlightColor.opacity(0.09), location: 0.30),
                            .init(color: Color.clear, location: 0.72)
                        ],
                        center: UnitPoint(x: 0.28, y: 0.16),
                        startRadius: 0,
                        endRadius: diameter * 0.82
                    )
                )
                .frame(width: diameter, height: diameter)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.clear, accentColor.opacity(0.018), Color.black.opacity(0.075)],
                        center: .center,
                        startRadius: diameter * 0.22,
                        endRadius: diameter * 0.50
                    )
                )
                .frame(width: diameter - 5 * scale, height: diameter - 5 * scale)
                .allowsHitTesting(false)

            VStack(spacing: 3.2 * scale) {
                ForEach(0..<13, id: \.self) { _ in
                    Rectangle().fill(Color.black.opacity(0.018)).frame(height: max(0.7, 0.7 * scale))
                }
            }
            .frame(width: diameter - 13 * scale, height: diameter - 13 * scale)
            .clipShape(Circle())
            .allowsHitTesting(false)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.92), Color.white.opacity(0.34), accentHighlightColor.opacity(0.16), accentColor.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9 * scale
                )
                .frame(width: diameter, height: diameter)
        }
    }

    private var languageLayer: some View {
        Text(shortLabel)
            .font(.system(size: 16.5 * scale, weight: .bold, design: .rounded))
            .foregroundStyle(Color.primary.opacity(0.88))
            .offset(y: -diameter * 0.320)
            .rotationEffect(.degrees(languageRotation))
            .opacity(languageOpacity)
            .frame(width: diameter, height: diameter)
            .allowsHitTesting(false)
    }

    private func bottomClockPlate(now: Date) -> some View {
        let bodyShape = ZestCenterOnlyTopPlateShape()
        let gasket = ZestCenterOnlyDisplayDomeShape(
            inset: diameter * 0.072,
            baselineOffset: -diameter * 0.016,
            bottomCornerRadius: diameter * 0.038,
            verticalScale: 0.88
        )
        let silverLip = ZestCenterOnlyDisplayDomeShape(
            inset: diameter * 0.088,
            baselineOffset: -diameter * 0.028,
            bottomCornerRadius: diameter * 0.033,
            verticalScale: 0.86
        )
        let lcd = ZestCenterOnlyDisplayDomeShape(
            inset: diameter * 0.105,
            baselineOffset: -diameter * 0.041,
            bottomCornerRadius: diameter * 0.029,
            verticalScale: 0.84
        )
        let rawTimeText = Self.timeFormatter.string(from: now)
        let second = Calendar.current.component(.second, from: now)
        let timeText = second.isMultiple(of: 2)
            ? rawTimeText
            : rawTimeText.replacingOccurrences(of: ":", with: "·")

        return ZStack {
            // Reuse the Clock+3 handset geometry detail-for-detail, mirrored into
            // the lower half of the same circular ring.
            bodyShape
                .fill(
                    LinearGradient(
                        colors: [
                            accentHighlightColor.opacity(forceVibrantRendering ? 0.72 : 0.18),
                            accentBrightColor.opacity(forceVibrantRendering ? 0.76 : 0.11),
                            accentDeepColor.opacity(forceVibrantRendering ? 0.58 : 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .glassEffect(.regular.tint(accentColor.opacity(forceVibrantRendering ? 0.66 : 0.28)), in: bodyShape)
                .overlay { bodyShape.stroke(Color.white.opacity(0.42), lineWidth: 0.75 * scale) }
                .scaleEffect(x: 1, y: -1)

            gasket
                .fill(Color.black.opacity(0.58))
                .scaleEffect(x: 1, y: -1)

            silverLip
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.56), Color.black.opacity(0.24), Color.white.opacity(0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(x: 1, y: -1)

            lcd
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.51, green: 0.55, blue: 0.34).opacity(0.96),
                            Color(red: 0.63, green: 0.67, blue: 0.42).opacity(0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    VStack(spacing: 1.55 * scale) {
                        ForEach(0..<14, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.black.opacity(0.045))
                                .frame(height: max(0.45, 0.45 * scale))
                        }
                    }
                    .frame(width: diameter * 0.69, height: diameter * 0.28)
                    .offset(y: diameter * 0.265)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                    )
                }
                .scaleEffect(x: 1, y: -1)

            // Curved glass reflection that follows the mirrored LCD dome.
            lcd
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.34), location: 0.00),
                            .init(color: Color.white.opacity(0.18), location: 0.18),
                            .init(color: Color.white.opacity(0.05), location: 0.34),
                            .init(color: Color.clear, location: 0.56)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(x: 1, y: -1)
                .mask(
                    Ellipse()
                        .frame(width: diameter * 0.43, height: diameter * 0.11)
                        .rotationEffect(.degrees(-8))
                        .offset(x: -diameter * 0.11, y: diameter * 0.198)
                )
                .blendMode(.screen)
                .allowsHitTesting(false)

            lcd
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.10), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .scaleEffect(x: 1, y: -1)
                .mask(
                    Ellipse()
                        .frame(width: diameter * 0.22, height: diameter * 0.19)
                        .rotationEffect(.degrees(-20))
                        .offset(x: -diameter * 0.22, y: diameter * 0.175)
                )
                .blendMode(.screen)
                .allowsHitTesting(false)

            ZestLCDPixelText(
                text: timeText,
                pixel: max(0.95, diameter * 0.0165),
                color: Color.black.opacity(0.72)
            )
            .offset(y: diameter * 0.255)
            .allowsHitTesting(false)
        }
        .frame(width: diameter, height: diameter)
    }

    private var dragWing: some View {
        ZStack {
            Color.clear.frame(width: 48 * scale, height: 42 * scale)

            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 10.5 * scale, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.76))
                .frame(width: 40 * scale, height: 29 * scale)
                .offset(x: -4 * scale)
                .background {
                    Color.clear
                        .frame(width: 40 * scale, height: 29 * scale)
                        .glassEffect(
                            .regular.tint(accentColor.opacity(0.24)).interactive(),
                            in: UnevenRoundedRectangle(
                                topLeadingRadius: 15 * scale,
                                bottomLeadingRadius: 15 * scale,
                                bottomTrailingRadius: 4 * scale,
                                topTrailingRadius: 4 * scale
                            )
                        )
                }
                .overlay {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 15 * scale,
                        bottomLeadingRadius: 15 * scale,
                        bottomTrailingRadius: 4 * scale,
                        topTrailingRadius: 4 * scale
                    )
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.72), accentHighlightColor.opacity(0.20), accentDeepColor.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75 * scale
                    )
                }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in onDragChanged?(value.translation, false) }
                .onEnded { value in onDragChanged?(value.translation, true) }
        )
        .zIndex(-1)
    }

    private var rotateWing: some View {
        Button(action: onRotateLanguage) {
            ZStack {
                Color.clear.frame(width: 48 * scale, height: 42 * scale)

                Image(systemName: "gearshape.arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.system(size: 10.5 * scale, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.76))
                    .frame(width: 40 * scale, height: 29 * scale)
                    .offset(x: 4 * scale)
                    .background {
                        Color.clear
                            .frame(width: 40 * scale, height: 29 * scale)
                            .glassEffect(
                                .regular.tint(accentColor.opacity(0.24)).interactive(),
                                in: UnevenRoundedRectangle(
                                    topLeadingRadius: 4 * scale,
                                    bottomLeadingRadius: 4 * scale,
                                    bottomTrailingRadius: 15 * scale,
                                    topTrailingRadius: 15 * scale
                                )
                            )
                    }
                    .overlay {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 4 * scale,
                            bottomLeadingRadius: 4 * scale,
                            bottomTrailingRadius: 15 * scale,
                            topTrailingRadius: 15 * scale
                        )
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.72), accentHighlightColor.opacity(0.20), accentDeepColor.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75 * scale
                        )
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .zIndex(-1)
    }

    private var settingsBadge: some View {
        let buttonSize = 29 * scale

        return Button(action: onSettings) {
            ZStack {
                Circle()
                    .fill(accentDeepColor.opacity(0.18))
                    .frame(width: buttonSize + 3 * scale, height: buttonSize + 3 * scale)
                    .offset(y: 1.8 * scale)

                Circle()
                    .fill(accentBrightColor.opacity(0.060))
                    .frame(width: buttonSize, height: buttonSize)

                Color.clear
                    .frame(width: buttonSize, height: buttonSize)
                    .glassEffect(.regular.tint(accentColor.opacity(0.23)).interactive(), in: Circle())

                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.20), location: 0),
                                .init(color: accentHighlightColor.opacity(0.10), location: 0.38),
                                .init(color: Color.clear, location: 0.82)
                            ],
                            center: UnitPoint(x: 0.30, y: 0.18),
                            startRadius: 0,
                            endRadius: buttonSize
                        )
                    )
                    .frame(width: buttonSize - 2 * scale, height: buttonSize - 2 * scale)

                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11.5 * scale, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.84))
                    .rotationEffect(.degrees(settingsGearHover ? 180 : 0))
            }
            .overlay {
                Circle().stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.82), Color.white.opacity(0.28), accentHighlightColor.opacity(0.18), accentDeepColor.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.85 * scale
                )
            }
            .shadow(color: .black.opacity(0.18), radius: 3.5 * scale, y: 2.4 * scale)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 38 * scale, height: 38 * scale)
        .contentShape(Circle())
        .focusable(false)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.58)) {
                settingsGearHover = hovering
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}


// MARK: - Production Center Only Calendar/Clock + 3

/// The hardware-like upper section in the reference: a circular dome that ends
/// in a flat lower rail immediately above the three physical lower keys.
private struct ZestCenterOnlyTopPlateShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let left = CGPoint(x: center.x - radius, y: center.y)

        var path = Path()
        path.move(to: left)
        path.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        path.addLine(to: left)
        path.closeSubpath()
        return path
    }
}

/// Rounded-bottom dome used for the black gasket, silver trim and LCD itself.
/// The tiny straight sidewalls and radiused lower corners are what distinguish
/// the Nokia-style window from a plain semicircle.
private struct ZestCenterOnlyDisplayDomeShape: Shape {
    let inset: CGFloat
    let baselineOffset: CGFloat
    let bottomCornerRadius: CGFloat
    var verticalScale: CGFloat = 0.86

    func path(in rect: CGRect) -> Path {
        let outerRadius = min(rect.width, rect.height) / 2
        let radius = max(1, outerRadius - inset)
        let rise = radius * verticalScale
        let corner = min(max(0, bottomCornerRadius), radius * 0.22)
        let baselineY = rect.midY + baselineOffset
        let arcBaseY = baselineY - corner
        let leftX = rect.midX - radius
        let rightX = rect.midX + radius
        let topY = arcBaseY - rise
        let k: CGFloat = 0.5522847498

        var path = Path()
        path.move(to: CGPoint(x: leftX, y: arcBaseY))

        // Left half of the flattened handset dome.
        path.addCurve(
            to: CGPoint(x: rect.midX, y: topY),
            control1: CGPoint(x: leftX, y: arcBaseY - rise * k),
            control2: CGPoint(x: rect.midX - radius * k, y: topY)
        )

        // Right half of the dome.
        path.addCurve(
            to: CGPoint(x: rightX, y: arcBaseY),
            control1: CGPoint(x: rect.midX + radius * k, y: topY),
            control2: CGPoint(x: rightX, y: arcBaseY - rise * k)
        )

        // Short sidewalls and rounded bottom corners, as in the Nokia bezel.
        path.addLine(to: CGPoint(x: rightX, y: baselineY - corner))
        path.addQuadCurve(
            to: CGPoint(x: rightX - corner, y: baselineY),
            control: CGPoint(x: rightX, y: baselineY)
        )
        path.addLine(to: CGPoint(x: leftX + corner, y: baselineY))
        path.addQuadCurve(
            to: CGPoint(x: leftX, y: baselineY - corner),
            control: CGPoint(x: leftX, y: baselineY)
        )
        path.closeSubpath()
        return path
    }
}

private struct ZestCenterOnlyBottomThirdSectorShape: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let start = 120.0 - Double(index) * 60.0
        let end = start + 60.0

        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// A tiny 5×7 raster typeface used instead of SF Mono so the LCD reads like a
/// real monochrome handset display rather than desktop typography.
private struct ZestLCDPixelText: View {
    let text: String
    let pixel: CGFloat
    let color: Color

    var body: some View {
        HStack(spacing: pixel * 0.78) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                glyph(character)
            }
        }
    }

    private func glyph(_ character: Character) -> some View {
        let rows = Self.patterns[character] ?? Self.patterns["?"]!
        return VStack(spacing: pixel * 0.16) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: pixel * 0.14) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                        Rectangle()
                            .fill(value == "1" ? color : Color.clear)
                            .frame(width: pixel, height: pixel)
                    }
                }
            }
        }
        .drawingGroup()
    }

    private static let patterns: [Character: [String]] = [
        "0": ["01110","10001","10011","10101","11001","10001","01110"],
        "1": ["00100","01100","00100","00100","00100","00100","01110"],
        "2": ["01110","10001","00001","00010","00100","01000","11111"],
        "3": ["11110","00001","00001","01110","00001","00001","11110"],
        "4": ["00010","00110","01010","10010","11111","00010","00010"],
        "5": ["11111","10000","10000","11110","00001","00001","11110"],
        "6": ["01110","10000","10000","11110","10001","10001","01110"],
        "7": ["11111","00001","00010","00100","01000","01000","01000"],
        "8": ["01110","10001","10001","01110","10001","10001","01110"],
        "9": ["01110","10001","10001","01111","00001","00001","01110"],
        ":": ["00000","00100","00100","00000","00100","00100","00000"],
        "·": ["00000","00000","00000","00000","00000","00000","00000"],
        "A": ["01110","10001","10001","11111","10001","10001","10001"],
        "B": ["11110","10001","10001","11110","10001","10001","11110"],
        "C": ["01111","10000","10000","10000","10000","10000","01111"],
        "D": ["11110","10001","10001","10001","10001","10001","11110"],
        "E": ["11111","10000","10000","11110","10000","10000","11111"],
        "F": ["11111","10000","10000","11110","10000","10000","10000"],
        "G": ["01111","10000","10000","10111","10001","10001","01110"],
        "J": ["00111","00010","00010","00010","00010","10010","01100"],
        "L": ["10000","10000","10000","10000","10000","10000","11111"],
        "M": ["10001","11011","10101","10101","10001","10001","10001"],
        "N": ["10001","11001","10101","10011","10001","10001","10001"],
        "O": ["01110","10001","10001","10001","10001","10001","01110"],
        "P": ["11110","10001","10001","11110","10000","10000","10000"],
        "R": ["11110","10001","10001","11110","10100","10010","10001"],
        "S": ["01111","10000","10000","01110","00001","00001","11110"],
        "T": ["11111","00100","00100","00100","00100","00100","00100"],
        "U": ["10001","10001","10001","10001","10001","10001","01110"],
        "V": ["10001","10001","10001","10001","10001","01010","00100"],
        "Y": ["10001","10001","01010","00100","00100","00100","00100"],
        " ": ["000","000","000","000","000","000","000"],
        "?": ["01110","10001","00010","00100","00100","00000","00100"]
    ]
}


private struct ZestLCDBoldDigitText: View {
    let text: String
    let pixel: CGFloat
    let color: Color

    var body: some View {
        HStack(spacing: pixel * 0.42) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                glyph(character)
            }
        }
    }

    private func glyph(_ character: Character) -> some View {
        let rows = Self.patterns[character] ?? Self.patterns["0"]!
        return VStack(spacing: pixel * 0.08) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: pixel * 0.06) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                        Rectangle()
                            .fill(value == "1" ? color : Color.clear)
                            .frame(width: pixel, height: pixel)
                    }
                }
            }
        }
        .drawingGroup()
    }

    private static let patterns: [Character: [String]] = [
        "0": ["011110","111111","110011","110011","110011","111111","011110"],
        "1": ["001100","011100","001100","001100","001100","001100","111111"],
        "2": ["011110","111111","000011","001110","011000","110000","111111"],
        "3": ["111110","000011","000011","011110","000011","000011","111110"],
        "4": ["000111","001111","011011","110011","111111","000011","000011"],
        "5": ["111111","110000","110000","111110","000011","000011","111110"],
        "6": ["011111","110000","110000","111110","110011","110011","011110"],
        "7": ["111111","000011","000110","001100","011000","011000","011000"],
        "8": ["011110","110011","110011","011110","110011","110011","011110"],
        "9": ["011110","110011","110011","011111","000011","000011","111110"]
    ]
}



// MARK: - Nokia Today Tile Faces

/// A compact Nokia-inspired LCD face for Triple Square / Tower tiles.
/// The tile itself remains the existing Today action; this only changes its
/// physical presentation while preserving Today-panel behavior.
struct ZestNokiaTodaySquareFace: View {
    let accentColor: Color
    let accentHighlightColor: Color
    let accentDeepColor: Color
    var forceVibrantRendering: Bool = false
    var size: CGFloat = 57

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let calendar = Calendar.current
            let hourText = String(format: "%02d", calendar.component(.hour, from: context.date))
            let minuteText = String(format: "%02d", calendar.component(.minute, from: context.date))
            let scale = size / 57
            let outer = RoundedRectangle(cornerRadius: 13 * scale, style: .continuous)
            let gasket = RoundedRectangle(cornerRadius: 11.0 * scale, style: .continuous)
            let lcd = RoundedRectangle(cornerRadius: 9.2 * scale, style: .continuous)

            ZStack {
                outer
                    .fill(
                        LinearGradient(
                            colors: [
                                accentHighlightColor.opacity(forceVibrantRendering ? 0.80 : 0.26),
                                accentColor.opacity(forceVibrantRendering ? 0.76 : 0.21),
                                accentDeepColor.opacity(forceVibrantRendering ? 0.52 : 0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .glassEffect(.regular.tint(accentColor.opacity(forceVibrantRendering ? 0.60 : 0.23)), in: outer)
                    .overlay { outer.stroke(Color.white.opacity(0.52), lineWidth: 0.75 * scale) }

                gasket
                    .fill(Color.black.opacity(0.64))
                    .frame(width: size * 0.91, height: size * 0.88)
                    .shadow(color: .black.opacity(0.20), radius: 1.5 * scale, y: 1 * scale)

                RoundedRectangle(cornerRadius: 9.8 * scale, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.54), Color.black.opacity(0.24), Color.white.opacity(0.26)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.855, height: size * 0.825)

                ZStack {
                    lcd
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.52, green: 0.56, blue: 0.35).opacity(0.99),
                                    Color(red: 0.65, green: 0.68, blue: 0.43).opacity(0.96)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    VStack(spacing: 0.9 * scale) {
                        ForEach(0..<14, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.black.opacity(0.045))
                                .frame(height: max(0.30, 0.30 * scale))
                        }
                    }
                    .padding(3.2 * scale)
                    .clipShape(lcd)

                    // Two large stacked time fields fill the small LCD. No date line:
                    // HH on top, mm below, matching the compact sketch treatment.
                    ZStack(alignment: .topTrailing) {
                        VStack(spacing: 2.15 * scale) {
                            ZestLCDBoldDigitText(
                                text: hourText,
                                pixel: max(1.36, 2.18 * scale),
                                color: Color.black.opacity(0.93)
                            )
                            ZestLCDBoldDigitText(
                                text: minuteText,
                                pixel: max(1.36, 2.18 * scale),
                                color: Color.black.opacity(0.93)
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        Circle()
                            .fill(Color.black.opacity(secondPulseOpacity(for: context.date)))
                            .frame(width: 3.4 * scale, height: 3.4 * scale)
                            .scaleEffect(secondPulseScale(for: context.date))
                            .padding(.top, 4.2 * scale)
                            .padding(.trailing, 4.8 * scale)
                            .animation(.easeInOut(duration: 0.44), value: Calendar.current.component(.second, from: context.date))
                    }

                    Ellipse()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.34), Color.white.opacity(0.08), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: size * 0.56, height: size * 0.15)
                        .rotationEffect(.degrees(-10))
                        .offset(x: -size * 0.11, y: -size * 0.20)
                        .blendMode(.screen)
                }
                .frame(width: size * 0.79, height: size * 0.765)
                .clipShape(lcd)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.13), radius: 2.4 * scale, y: 1.8 * scale)
        }
    }

    private func secondPulseOpacity(for date: Date) -> Double {
        Calendar.current.component(.second, from: date).isMultiple(of: 2) ? 0.78 : 0.26
    }

    private func secondPulseScale(for date: Date) -> CGFloat {
        Calendar.current.component(.second, from: date).isMultiple(of: 2) ? 1.12 : 0.82
    }
}


/// Nokia LCD adapted to an Orange Slice annular-sector tile. The bezel and
/// screen follow the wedge itself rather than using a rectangular inset.
struct ZestNokiaTodayWedgeFace: View {
    let startAngle: Double
    let endAngle: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let gapInset: CGFloat
    var startGapInset: CGFloat? = nil
    var endGapInset: CGFloat? = nil
    let canvasSize: CGFloat
    let accentColor: Color
    let accentHighlightColor: Color
    let accentDeepColor: Color
    var counterRotationDegrees: Double = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let calendar = Calendar.current
            let hourText = String(format: "%02d", calendar.component(.hour, from: context.date))
            let minuteText = String(format: "%02d", calendar.component(.minute, from: context.date))
            let second = calendar.component(.second, from: context.date)
            let scale = canvasSize / 210
            let centerAngle = (startAngle + endAngle) / 2
            let radians = centerAngle * Double.pi / 180

            let gasketInner = innerRadius + 5.0 * scale
            let gasketOuter = outerRadius - 5.0 * scale
            let lcdInner = innerRadius + 8.0 * scale
            let lcdOuter = outerRadius - 8.0 * scale

            let gasket = ZestTileShape(
                startAngle: startAngle,
                endAngle: endAngle,
                innerRadius: gasketInner,
                outerRadius: gasketOuter,
                gapInset: gapInset + 4.0 * scale,
                startGapInset: startGapInset.map { $0 + 3.0 * scale },
                endGapInset: endGapInset.map { $0 + 3.0 * scale }
            )
            let lip = ZestTileShape(
                startAngle: startAngle,
                endAngle: endAngle,
                innerRadius: innerRadius + 6.5 * scale,
                outerRadius: outerRadius - 6.5 * scale,
                gapInset: gapInset + 5.3 * scale,
                startGapInset: startGapInset.map { $0 + 4.2 * scale },
                endGapInset: endGapInset.map { $0 + 4.2 * scale }
            )
            let lcd = ZestTileShape(
                startAngle: startAngle,
                endAngle: endAngle,
                innerRadius: lcdInner,
                outerRadius: lcdOuter,
                gapInset: gapInset + 6.7 * scale,
                startGapInset: startGapInset.map { $0 + 5.5 * scale },
                endGapInset: endGapInset.map { $0 + 5.5 * scale }
            )

            let textRadius = (lcdInner + lcdOuter) / 2
            let textX = canvasSize / 2 + CGFloat(cos(radians)) * textRadius
            let textY = canvasSize / 2 + CGFloat(sin(radians)) * textRadius

            ZStack {
                gasket
                    .fill(Color.black.opacity(0.60))
                    .frame(width: canvasSize, height: canvasSize)

                lip
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.48), Color.black.opacity(0.22), Color.white.opacity(0.24)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: canvasSize, height: canvasSize)

                lcd
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.52, green: 0.56, blue: 0.35).opacity(0.98),
                                Color(red: 0.65, green: 0.68, blue: 0.43).opacity(0.95)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: canvasSize, height: canvasSize)
                    .overlay {
                        lcd
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.23), Color.white.opacity(0.05), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: canvasSize, height: canvasSize)
                            .mask(
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white, Color.clear],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                    }

                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 1.75 * scale) {
                        ZestLCDBoldDigitText(
                            text: hourText,
                            pixel: max(1.06, 1.78 * scale),
                            color: Color.black.opacity(0.93)
                        )
                        ZestLCDBoldDigitText(
                            text: minuteText,
                            pixel: max(1.06, 1.78 * scale),
                            color: Color.black.opacity(0.93)
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Circle()
                        .fill(Color.black.opacity(second.isMultiple(of: 2) ? 0.78 : 0.26))
                        .frame(width: 3.2 * scale, height: 3.2 * scale)
                        .scaleEffect(second.isMultiple(of: 2) ? 1.12 : 0.82)
                        .padding(.top, 1.5 * scale)
                        .padding(.trailing, 2.0 * scale)
                        .animation(.easeInOut(duration: 0.44), value: second)
                }
                .frame(width: 35 * scale, height: 35 * scale)
                .rotationEffect(.degrees(counterRotationDegrees))
                .position(x: textX, y: textY)
            }
            .frame(width: canvasSize, height: canvasSize)
        }
    }
}

/// Center Only face with a fixed handset-like Clock/Calendar display on top and
/// three glass physical Zest keys below it.
struct ZestV34CenterOnlyTopThreeView: View {
    let features: [ZestFeature]
    let featureColors: [Color]
    let displayKind: ZestV34CenterTopDisplayKind

    let accentColor: Color
    let accentBrightColor: Color
    let accentHighlightColor: Color
    let accentDeepColor: Color
    var forceVibrantRendering: Bool = false
    var diameter: CGFloat = 93.6

    var onFeature: (ZestFeature, Int) -> Void = { _, _ in }
    var onSettings: () -> Void = {}

    @State private var settingsGearHover = false
    @State private var hoveredFeatureIndex: Int? = nil

    private var scale: CGFloat { min(max(diameter / 93.6, 1), 2.35) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack {
                ringShell

                topPlate(now: context.date)
                    .zIndex(4)

                ForEach(0..<3, id: \.self) { index in
                    let feature = features.indices.contains(index) ? features[index] : .empty

                    Button {
                        guard feature != .empty else { return }
                        onFeature(feature, index)
                    } label: {
                        ZestCenterOnlyBottomThirdSectorShape(index: index)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        accentHighlightColor.opacity(forceVibrantRendering ? 0.56 : 0.15),
                                        accentBrightColor.opacity(forceVibrantRendering ? 0.68 : 0.10),
                                        accentDeepColor.opacity(forceVibrantRendering ? 0.55 : 0.09)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .glassEffect(
                                .regular.tint(accentColor.opacity(forceVibrantRendering ? 0.56 : 0.25)).interactive(),
                                in: ZestCenterOnlyBottomThirdSectorShape(index: index)
                            )
                            .overlay {
                                ZestCenterOnlyBottomThirdSectorShape(index: index)
                                    .stroke(Color.black.opacity(0.22), lineWidth: 1.45 * scale)
                            }
                            .overlay {
                                ZestCenterOnlyBottomThirdSectorShape(index: index)
                                    .stroke(Color.white.opacity(hoveredFeatureIndex == index ? 0.72 : 0.42), lineWidth: 0.65 * scale)
                                    .padding(1.1 * scale)
                            }
                            .overlay { featureIcon(feature, index: index) }
                            .brightness(hoveredFeatureIndex == index ? 0.035 : 0)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.13)) {
                            hoveredFeatureIndex = hovering ? index : (hoveredFeatureIndex == index ? nil : hoveredFeatureIndex)
                        }
                    }
                }

                outerRim

                settingsBadge
                    .zIndex(30)
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .shadow(color: .black.opacity(0.17), radius: 4.5 * scale, y: 2.3 * scale)
    }

    private var ringShell: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.17))
                .frame(width: diameter + 10 * scale, height: diameter + 10 * scale)
                .offset(y: 1.7 * scale)

            Circle()
                .fill((forceVibrantRendering ? accentColor : accentBrightColor).opacity(forceVibrantRendering ? 0.74 : 0.055))
                .frame(width: diameter + 7 * scale, height: diameter + 7 * scale)
                .offset(y: 1.0 * scale)

            Color.clear
                .frame(width: diameter + 7 * scale, height: diameter + 7 * scale)
                .glassEffect(.regular.tint(accentColor.opacity(0.12)), in: Circle())

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.92), Color.white.opacity(0.40), accentHighlightColor.opacity(0.17), Color.black.opacity(0.20)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9 * scale
                )
                .frame(width: diameter + 7 * scale, height: diameter + 7 * scale)

            Circle()
                .fill((forceVibrantRendering ? accentColor : accentBrightColor).opacity(forceVibrantRendering ? 0.72 : 0.060))
                .frame(width: diameter, height: diameter)

            Color.clear
                .frame(width: diameter, height: diameter)
                .glassEffect(.regular.tint(accentColor.opacity(forceVibrantRendering ? 0.72 : 0.24)), in: Circle())
        }
    }

    private func topPlate(now: Date) -> some View {
        let bodyShape = ZestCenterOnlyTopPlateShape()
        let gasket = ZestCenterOnlyDisplayDomeShape(
            inset: diameter * 0.072,
            baselineOffset: -diameter * 0.016,
            bottomCornerRadius: diameter * 0.038,
            verticalScale: 0.88
        )
        let silverLip = ZestCenterOnlyDisplayDomeShape(
            inset: diameter * 0.088,
            baselineOffset: -diameter * 0.028,
            bottomCornerRadius: diameter * 0.033,
            verticalScale: 0.86
        )
        let lcd = ZestCenterOnlyDisplayDomeShape(
            inset: diameter * 0.105,
            baselineOffset: -diameter * 0.041,
            bottomCornerRadius: diameter * 0.029,
            verticalScale: 0.84
        )

        let rawTimeText = Self.timeFormatter.string(from: now)
        let second = Calendar.current.component(.second, from: now)
        // Preserve the exact five-column separator width while hiding only the
        // colon pixels on alternating seconds, so the digits never jump sideways.
        let timeText = second.isMultiple(of: 2)
            ? rawTimeText
            : rawTimeText.replacingOccurrences(of: ":", with: "·")
        let dateText = "\(Calendar.current.component(.day, from: now)) \(Self.monthFormatter.string(from: now).uppercased())"

        return ZStack {
            // Thick orange upper housing, continuous with the outer ring.
            bodyShape
                .fill(
                    LinearGradient(
                        colors: [
                            accentHighlightColor.opacity(forceVibrantRendering ? 0.78 : 0.20),
                            accentBrightColor.opacity(forceVibrantRendering ? 0.76 : 0.13),
                            accentColor.opacity(forceVibrantRendering ? 0.68 : 0.11),
                            accentDeepColor.opacity(forceVibrantRendering ? 0.62 : 0.10)
                        ],
                        startPoint: UnitPoint(x: 0.30, y: 0.02),
                        endPoint: .bottom
                    )
                )
                .glassEffect(.regular.tint(accentColor.opacity(forceVibrantRendering ? 0.72 : 0.31)), in: bodyShape)
                .overlay {
                    bodyShape.stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.88), Color.white.opacity(0.32), accentHighlightColor.opacity(0.20), Color.black.opacity(0.22)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.95 * scale
                    )
                }
                .shadow(color: .black.opacity(0.14), radius: 2.5 * scale, y: 1.7 * scale)

            // Inner orange highlight rail seen around the black gasket in the render.
            bodyShape
                .stroke(accentHighlightColor.opacity(0.46), lineWidth: 1.45 * scale)
                .padding(3.2 * scale)
                .blendMode(.screen)

            // Black rubber/plastic gasket.
            gasket
                .fill(Color.black.opacity(0.78))
                .overlay {
                    gasket.stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.30), Color.black.opacity(0.84), Color.black.opacity(0.56)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.25 * scale
                    )
                }
                .shadow(color: .black.opacity(0.38), radius: 2.2 * scale, y: 1.2 * scale)

            // Narrow metallic/plastic lip between gasket and LCD.
            silverLip
                .fill(Color.white.opacity(0.13))
                .overlay {
                    silverLip.stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.60), Color.gray.opacity(0.20), Color.black.opacity(0.58), Color.white.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.95 * scale
                    )
                }

            // Nokia-style olive LCD/backlight.
            ZStack {
                lcd.fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.72, green: 0.73, blue: 0.52),
                            Color(red: 0.63, green: 0.65, blue: 0.43),
                            Color(red: 0.56, green: 0.59, blue: 0.37)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Fine LCD pixel lattice.
                VStack(spacing: max(1.05, 1.15 * scale)) {
                    ForEach(0..<28, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.black.opacity(0.035))
                            .frame(height: max(0.32, 0.32 * scale))
                    }
                }
                .frame(width: diameter, height: diameter)
                .clipShape(lcd)

                HStack(spacing: max(1.25, 1.35 * scale)) {
                    ForEach(0..<34, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.black.opacity(0.018))
                            .frame(width: max(0.30, 0.30 * scale))
                    }
                }
                .frame(width: diameter, height: diameter)
                .clipShape(lcd)

                // Slight center glow/backlight bloom.
                lcd.fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.12), Color.clear, Color.black.opacity(0.055)],
                        center: UnitPoint(x: 0.50, y: 0.39),
                        startRadius: 0,
                        endRadius: diameter * 0.42
                    )
                )

                Group {
                    switch displayKind {
                    case .clock:
                        ZestLCDPixelText(
                            text: timeText,
                            pixel: 1.72 * scale,
                            color: Color(red: 0.08, green: 0.09, blue: 0.055).opacity(0.86)
                        )
                    case .calendar:
                        ZestLCDPixelText(
                            text: dateText,
                            pixel: 1.32 * scale,
                            color: Color(red: 0.08, green: 0.09, blue: 0.055).opacity(0.86)
                        )
                    }
                }
                .offset(y: -diameter * 0.235)
                .allowsHitTesting(false)

                // Broad curved glass reflection like the reference render.
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.46), Color.white.opacity(0.12), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: diameter * 0.57, height: diameter * 0.22)
                    .rotationEffect(.degrees(-18))
                    .offset(x: -diameter * 0.17, y: -diameter * 0.315)
                    .blur(radius: 0.25 * scale)
                    .clipShape(lcd)
                    .blendMode(.screen)

                // A second faint glare strip across the upper glass.
                lcd.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.clear, Color.clear],
                        startPoint: UnitPoint(x: 0.08, y: 0.03),
                        endPoint: UnitPoint(x: 0.78, y: 0.64)
                    )
                )
                .blendMode(.screen)

                lcd.stroke(Color.black.opacity(0.34), lineWidth: 0.75 * scale)
            }
            .frame(width: diameter, height: diameter)
            .clipShape(lcd)
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }

    private func featureIcon(_ feature: ZestFeature, index: Int) -> some View {
        let angles: [Double] = [150, 90, 30]
        let radians = angles[index] * Double.pi / 180
        let radius = diameter * 0.36
        let icon = centerOnlyFeatureIcon(feature)

        return Image(systemName: icon)
            .font(.system(size: min(14.8 * scale, 29), weight: .semibold))
            .foregroundStyle(Color.primary.opacity(feature == .empty ? 0.32 : 0.90))
            .shadow(color: .black.opacity(0.17), radius: 1.2 * scale, y: 0.8 * scale)
            .offset(x: CGFloat(cos(radians)) * radius, y: CGFloat(sin(radians)) * radius)
    }

    private func centerOnlyFeatureIcon(_ feature: ZestFeature) -> String {
        switch feature {
        case .size: return "textformat.size"
        case .font: return "bold.italic.underline"
        default: return feature.systemImage
        }
    }

    private var outerRim: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.94), Color.white.opacity(0.36), accentHighlightColor.opacity(0.18), Color.black.opacity(0.20)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.95 * scale
            )
            .frame(width: diameter, height: diameter)
            .allowsHitTesting(false)
    }

    private var settingsBadge: some View {
        let buttonSize = min(max(diameter * 0.31, 29), 56)

        return Button(action: onSettings) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.30))
                    .frame(width: buttonSize + 7 * scale, height: buttonSize + 7 * scale)
                    .offset(y: 2.4 * scale)

                Circle()
                    .fill(accentDeepColor.opacity(0.24))
                    .frame(width: buttonSize + 4 * scale, height: buttonSize + 4 * scale)
                    .offset(y: 1.8 * scale)

                Circle()
                    .fill(accentBrightColor.opacity(forceVibrantRendering ? 0.62 : 0.095))
                    .frame(width: buttonSize, height: buttonSize)

                Color.clear
                    .frame(width: buttonSize, height: buttonSize)
                    .glassEffect(.regular.tint(accentColor.opacity(0.30)).interactive(), in: Circle())

                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.24), location: 0),
                                .init(color: accentHighlightColor.opacity(0.12), location: 0.38),
                                .init(color: Color.clear, location: 0.82)
                            ],
                            center: UnitPoint(x: 0.30, y: 0.18),
                            startRadius: 0,
                            endRadius: buttonSize
                        )
                    )
                    .frame(width: buttonSize - 2 * scale, height: buttonSize - 2 * scale)

                Image(systemName: "gearshape.fill")
                    .font(.system(size: min(11.5 * scale, 21), weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.90))
                    .rotationEffect(.degrees(settingsGearHover ? 180 : 0))
            }
            .overlay {
                Circle().stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.86), Color.white.opacity(0.30), accentHighlightColor.opacity(0.20), Color.black.opacity(0.24)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9 * scale
                )
            }
            .shadow(color: .black.opacity(0.20), radius: 3.8 * scale, y: 2.5 * scale)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: buttonSize + 10 * scale, height: buttonSize + 10 * scale)
        .contentShape(Circle())
        .focusable(false)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.58)) {
                settingsGearHover = hovering
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "MMM"
        return formatter
    }()
}


// MARK: - Production Center Only 2/4 Split

private struct ZestCenterOnlySplitSectorShape: Shape {
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

/// Shared production renderer for Center Only's 2/4 Split modes.
///
/// The live runtime and onboarding guide both use this exact component. The
/// guide only drives the optional `pressedFeatureIndex` / `settingsPressed`
/// presentation states; normal runtime hover and click behaviour remains here.
struct ZestV34CenterOnlySplitView: View {
    let features: [ZestFeature]
    let count: Int
    let featureColors: [Color]

    let accentColor: Color
    let accentBrightColor: Color
    let accentHighlightColor: Color
    let accentDeepColor: Color
    var forceVibrantRendering: Bool = false

    var pressedFeatureIndex: Int? = nil
    var settingsPressed: Bool = false
    var onFeature: (ZestFeature, Int) -> Void = { _, _ in }
    var onSettings: () -> Void = {}

    @State private var hoveredFeatureIndex: Int? = nil
    @State private var settingsGearHover = false

    private let diameter: CGFloat = 93.6 // production centerRadius(39) * 2 * 1.20

    var body: some View {
        ZStack {
            Circle()
                .fill((forceVibrantRendering ? accentColor : accentBrightColor).opacity(forceVibrantRendering ? 0.66 : 0.030))
                .frame(width: diameter + 8, height: diameter + 8)
                .offset(y: 1.1)

            Color.clear
                .frame(width: diameter + 8, height: diameter + 8)
                .glassEffect(.regular.tint(accentColor.opacity(0.095)), in: Circle())

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.86), Color.white.opacity(0.28), accentHighlightColor.opacity(0.13), accentDeepColor.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.85
                )
                .frame(width: diameter + 8, height: diameter + 8)

            Circle()
                .fill((forceVibrantRendering ? accentColor : accentBrightColor).opacity(forceVibrantRendering ? 0.70 : 0.050))
                .frame(width: diameter, height: diameter)
                .offset(y: 1.2)

            Color.clear
                .frame(width: diameter, height: diameter)
                .glassEffect(.regular.tint(accentColor.opacity(forceVibrantRendering ? 0.68 : 0.24)).interactive(), in: Circle())

            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.16), location: 0),
                            .init(color: accentHighlightColor.opacity(0.09), location: 0.30),
                            .init(color: Color.clear, location: 0.72)
                        ],
                        center: UnitPoint(x: 0.28, y: 0.16),
                        startRadius: 0,
                        endRadius: 65
                    )
                )
                .frame(width: diameter, height: diameter)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.clear, accentColor.opacity(0.018), Color.black.opacity(0.075)],
                        center: .center,
                        startRadius: diameter * 0.22,
                        endRadius: diameter * 0.50
                    )
                )
                .frame(width: diameter - 5, height: diameter - 5)
                .allowsHitTesting(false)

            VStack(spacing: 3.2) {
                ForEach(0..<13, id: \.self) { _ in
                    Rectangle().fill(Color.black.opacity(0.018)).frame(height: 0.7)
                }
            }
            .frame(width: diameter - 13, height: diameter - 13)
            .clipShape(Circle())
            .allowsHitTesting(false)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.92), Color.white.opacity(0.34), accentHighlightColor.opacity(0.16), accentColor.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
                .frame(width: diameter, height: diameter)

            featureDisk
            settingsBadge.zIndex(20)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private var featureDisk: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let feature = index < features.count ? features[index] : .empty
                let tileAccent = index < featureColors.count ? featureColors[index] : accentColor
                let radius = diameter * 0.32
                let angle: Double = count == 2 ? (index == 0 ? -90 : 90) : [-90, 0, 90, 180][index]
                let radians = angle * Double.pi / 180
                let isHovered = hoveredFeatureIndex == index
                let isPressed = pressedFeatureIndex == index

                Button { onFeature(feature, index) } label: {
                    ZStack {
                        ZestCenterOnlySplitSectorShape(index: index, count: count)
                            .fill(tileAccent.opacity(feature == .empty ? 0.018 : (forceVibrantRendering ? (isHovered ? 0.78 : 0.70) : (isHovered ? 0.145 : 0.085))))
                            .glassEffect(
                                .regular.tint(tileAccent.opacity(feature == .empty ? 0.04 : (forceVibrantRendering ? 0.60 : 0.20))).interactive(),
                                in: ZestCenterOnlySplitSectorShape(index: index, count: count)
                            )
                            .overlay {
                                ZestCenterOnlySplitSectorShape(index: index, count: count)
                                    .stroke(Color.white.opacity(feature == .empty ? 0.12 : (isHovered || isPressed ? 0.48 : 0.24)), lineWidth: isHovered || isPressed ? 0.95 : 0.65)
                            }

                        if feature != .empty {
                            Image(systemName: feature == .font ? "bold.italic.underline" : feature.systemImage)
                                .font(.system(size: count == 2 ? 17 : 14, weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(isHovered || isPressed ? 0.98 : 0.82))
                                .scaleEffect(isHovered ? 1.10 : 1.0)
                                .offset(x: cos(radians) * radius, y: sin(radians) * radius)
                        }
                    }
                    .frame(width: diameter, height: diameter)
                    .contentShape(ZestCenterOnlySplitSectorShape(index: index, count: count))
                    .shadow(color: tileAccent.opacity(isHovered || isPressed ? 0.15 : 0), radius: isHovered || isPressed ? 6 : 0, y: 2)
                    .scaleEffect(isPressed ? 0.965 : (isHovered ? 1.012 : 1.0))
                    .brightness(isPressed ? 0.08 : 0)
                    .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isHovered)
                    .animation(.spring(response: 0.22, dampingFraction: 0.80), value: isPressed)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(feature == .empty)
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let dx = location.x - diameter / 2
                let dy = location.y - diameter / 2
                let r = hypot(dx, dy)
                guard r > diameter * 0.22 else { hoveredFeatureIndex = nil; return }
                var degrees = atan2(dy, dx) * 180 / .pi
                if degrees < 0 { degrees += 360 }
                if count == 2 {
                    hoveredFeatureIndex = (degrees >= 180 && degrees < 360) ? 0 : 1
                } else {
                    if degrees >= 315 || degrees < 45 { hoveredFeatureIndex = 1 }
                    else if degrees < 135 { hoveredFeatureIndex = 2 }
                    else if degrees < 225 { hoveredFeatureIndex = 3 }
                    else { hoveredFeatureIndex = 0 }
                }
            case .ended:
                hoveredFeatureIndex = nil
            }
        }
    }

    private var settingsBadge: some View {
        let buttonSize: CGFloat = 29
        return Button(action: onSettings) {
            ZStack {
                Circle().fill(accentDeepColor.opacity(0.18)).frame(width: buttonSize + 3, height: buttonSize + 3).offset(y: 1.8)
                Circle().fill(accentBrightColor.opacity(0.060)).frame(width: buttonSize, height: buttonSize)
                Color.clear.frame(width: buttonSize, height: buttonSize)
                    .glassEffect(.regular.tint(accentColor.opacity(0.23)).interactive(), in: Circle())
                Circle()
                    .fill(RadialGradient(stops: [.init(color: Color.white.opacity(0.20), location: 0), .init(color: accentHighlightColor.opacity(0.10), location: 0.38), .init(color: Color.clear, location: 0.82)], center: UnitPoint(x: 0.30, y: 0.18), startRadius: 0, endRadius: buttonSize))
                    .frame(width: buttonSize - 2, height: buttonSize - 2)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.84))
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(settingsGearHover ? 180 : 0))
            }
            .overlay {
                Circle().stroke(LinearGradient(colors: [Color.white.opacity(0.82), Color.white.opacity(0.28), accentHighlightColor.opacity(0.18), accentDeepColor.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.85)
            }
            .shadow(color: .black.opacity(0.18), radius: 3.5, y: 2.4)
            .shadow(color: accentColor.opacity(0.09), radius: 3, y: 1)
            .contentShape(Circle())
            .scaleEffect(settingsPressed ? 0.88 : 1)
            .brightness(settingsPressed ? 0.08 : 0)
        }
        .buttonStyle(.plain)
        .frame(width: 38, height: 38)
        .contentShape(Circle())
        .focusable(false)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.58)) { settingsGearHover = hovering }
        }
    }
}


// MARK: - Production Triple Square Control

/// Shared production renderer for Triple Square.
///
/// The live in-field Zest and onboarding guide both use this component. This
/// keeps the tutorial pixel-consistent with the runtime control instead of
/// maintaining a second approximation.
struct ZestV34TripleTileControl: View {
    let features: [ZestFeature]
    let featureColors: [Color]

    let accentColor: Color
    let accentBrightColor: Color
    let accentHighlightColor: Color
    let accentDeepColor: Color
    let rearGlassPrimaryColor: Color
    let rearGlassBrightColor: Color

    var forceVibrantRendering: Bool = false

    /// Tutorial-only press states. Runtime leaves these at their defaults and
    /// gets ordinary interactive feedback from hover/buttons.
    var pressedFeatureIndex: Int? = nil
    var settingsPressed: Bool = false

    /// Runtime shows the physical grab handle and supplies the drag callback.
    /// The onboarding guide can still show the exact handle without making it
    /// interactive by leaving `onDrag` nil.
    var showsDragHandle: Bool = true

    /// Runtime can supply a target-aware icon for configured Application,
    /// Shortcut, and URL tiles. Onboarding/settings previews use the normal
    /// feature symbol by leaving this nil.
    var featureIcon: ((ZestFeature, Int) -> AnyView)? = nil

    var onFeature: (ZestFeature, Int) -> Void = { _, _ in }
    var onSettings: () -> Void = {}
    var onDrag: ((CGSize, Bool) -> Void)? = nil

    @State private var hoveredFeatureIndex: Int? = nil
    @State private var settingsGearHover = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(rearGlassBrightColor.opacity(0.060))
                .frame(width: 199, height: 71)
                .glassEffect(
                    .regular.tint(
                        rearGlassPrimaryColor.opacity(
                            forceVibrantRendering ? 0.20 : 0.11
                        )
                    ),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 0.8)
                }
                .offset(y: -18)
                .zIndex(2)

            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    let feature = index < features.count ? features[index] : .empty
                    let tileAccent = index < featureColors.count ? featureColors[index] : accentColor
                    let isHovered = hoveredFeatureIndex == index
                    let isPressed = pressedFeatureIndex == index

                    ZStack(alignment: .topTrailing) {
                        Button {
                            guard feature != .empty else { return }
                            onFeature(feature, index)
                        } label: {
                            Group {
                                if feature == .today {
                                    AnyView(
                                        ZestNokiaTodaySquareFace(
                                            accentColor: tileAccent,
                                            accentHighlightColor: accentHighlightColor,
                                            accentDeepColor: accentDeepColor,
                                            forceVibrantRendering: forceVibrantRendering,
                                            size: 57
                                        )
                                    )
                                } else if let featureIcon {
                                    featureIcon(feature, index)
                                        .foregroundStyle(
                                            Color.primary.opacity(
                                                isHovered || isPressed ? 0.96 : 0.84
                                            )
                                        )
                                        .frame(width: 57, height: 57)
                                        .background {
                                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                                .fill(
                                                    tileAccent.opacity(
                                                        forceVibrantRendering
                                                        ? (isHovered || isPressed ? 0.76 : 0.68)
                                                        : (isHovered || isPressed ? 0.18 : 0.12)
                                                    )
                                                )
                                                .glassEffect(
                                                    .regular.tint(tileAccent.opacity(forceVibrantRendering ? 0.64 : 0.18)).interactive(),
                                                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                                                )
                                                .overlay {
                                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                                        .stroke(Color.white.opacity(isHovered || isPressed ? 0.58 : 0.30), lineWidth: isHovered || isPressed ? 1.0 : 0.7)
                                                }
                                        }
                                } else {
                                    AnyView(
                                        Image(systemName: feature.systemImage)
                                            .font(.system(size: 19, weight: .semibold))
                                            .foregroundStyle(Color.primary.opacity(isHovered || isPressed ? 0.96 : 0.84))
                                            .frame(width: 57, height: 57)
                                            .background {
                                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                                    .fill(tileAccent.opacity(forceVibrantRendering ? (isHovered || isPressed ? 0.76 : 0.68) : (isHovered || isPressed ? 0.18 : 0.12)))
                                                    .glassEffect(.regular.tint(tileAccent.opacity(forceVibrantRendering ? 0.64 : 0.18)).interactive(), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                                    .overlay {
                                                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                                                            .stroke(Color.white.opacity(isHovered || isPressed ? 0.58 : 0.30), lineWidth: isHovered || isPressed ? 1.0 : 0.7)
                                                    }
                                            }
                                    )
                                }
                            }
                            .shadow(color: tileAccent.opacity(isHovered || isPressed ? 0.18 : 0.06), radius: isHovered || isPressed ? 7 : 3, y: isHovered || isPressed ? 3 : 2)
                            .scaleEffect(isPressed ? 0.94 : (isHovered ? 1.045 : 1.0))
                            .offset(y: isPressed ? 0 : (isHovered ? -2 : 0))
                            .brightness(isPressed ? 0.08 : 0)
                            .contentShape(Rectangle())
                            .animation(.spring(response: 0.22, dampingFraction: 0.76), value: isHovered)
                            .animation(.spring(response: 0.22, dampingFraction: 0.80), value: isPressed)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .disabled(feature == .empty)
                    }
                    .frame(width: 57, height: 57)
                }
            }
            .frame(width: 185, height: 71)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let slotWidth = 64.0
                    let index = min(2, max(0, Int(location.x / slotWidth)))
                    let feature = index < features.count ? features[index] : .empty
                    hoveredFeatureIndex = feature == .empty ? nil : index
                case .ended:
                    hoveredFeatureIndex = nil
                }
            }
            .offset(y: -18)
            .zIndex(3)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.20), location: 0.00),
                                .init(color: accentColor.opacity(0.10), location: 0.48),
                                .init(color: accentDeepColor.opacity(0.11), location: 1.00)
                            ],
                            center: UnitPoint(x: 0.34, y: 0.22),
                            startRadius: 0,
                            endRadius: 28
                        )
                    )
                    .frame(width: 42, height: 42)
                    .glassEffect(.regular.tint(accentColor.opacity(0.11)), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.72),
                                        Color.white.opacity(0.24),
                                        accentDeepColor.opacity(0.20)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.9
                            )
                    }
                    .shadow(color: .black.opacity(0.15), radius: 3.5, y: 2.2)
                    .shadow(color: accentColor.opacity(0.10), radius: 4, y: 1)

                Button(action: onSettings) {
                    ZStack {
                        Circle()
                            .fill(accentDeepColor.opacity(0.20))
                            .frame(width: 34, height: 34)
                            .offset(y: 1.5)

                        Color.clear
                            .frame(width: 31, height: 31)
                            .glassEffect(
                                .regular
                                    .tint(
                                        accentColor.opacity(
                                            forceVibrantRendering ? 0.68 : 0.24
                                        )
                                    )
                                    .interactive(),
                                in: Circle()
                            )

                        Circle()
                            .fill(
                                RadialGradient(
                                    stops: [
                                        .init(color: Color.white.opacity(0.22), location: 0),
                                        .init(color: accentHighlightColor.opacity(0.10), location: 0.38),
                                        .init(color: Color.clear, location: 0.84)
                                    ],
                                    center: UnitPoint(x: 0.30, y: 0.18),
                                    startRadius: 0,
                                    endRadius: 31
                                )
                            )
                            .frame(width: 29, height: 29)

                        Circle()
                            .stroke(Color.white.opacity(0.72), lineWidth: 0.85)
                            .frame(width: 31, height: 31)

                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.84))
                            .frame(width: 18, height: 18)
                            .rotationEffect(
                                .degrees(settingsGearHover ? 180 : 0),
                                anchor: .center
                            )
                    }
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
                    .scaleEffect(settingsPressed ? 0.88 : 1)
                    .brightness(settingsPressed ? 0.08 : 0)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.58)) {
                        settingsGearHover = hovering
                    }
                }
            }
            .frame(width: 42, height: 42)
            .offset(y: 4)
            .zIndex(4)

            if showsDragHandle {
                tripleDragHandle
                    .offset(x: -101, y: -42)
                    .zIndex(20)
            }
        }
        .frame(width: 215, height: 116)
        .contentShape(Rectangle())
    }

    private var tripleDragHandle: some View {
        ZStack {
            Circle()
                .fill(rearGlassBrightColor.opacity(0.16))
                .glassEffect(
                    .regular.tint(
                        accentColor.opacity(forceVibrantRendering ? 0.60 : 0.18)
                    ),
                    in: Circle()
                )
                .overlay {
                    Circle().stroke(Color.white.opacity(0.70), lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(0.14), radius: 2.2, y: 1.3)

            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 8.8, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.78))
        }
        .frame(width: 22, height: 22)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in onDrag?(value.translation, false) }
                .onEnded { value in onDrag?(value.translation, true) }
        )
    }
}


// MARK: - Visual Slot

struct ZestV34SliceVisualSlot: Identifiable {

    let id: Int
    let startAngle: Double
    let endAngle: Double

    var centerAngle: Double {

        let correctedEnd =
            endAngle < startAngle
            ? endAngle + 360
            : endAngle

        return (
            startAngle
            + correctedEnd
        ) / 2
    }


    var settingsSlot: ZestSliceSlot {
        ZestSliceSlot(
            rawValue: id + 2
        ) ?? .slot2
    }


    static let all: [ZestV34SliceVisualSlot] = [

        .init(
            id: 0,
            startAngle: 210,
            endAngle: 260
        ),

        .init(
            id: 1,
            startAngle: 260,
            endAngle: 310
        ),

        .init(
            id: 2,
            startAngle: 310,
            endAngle: 360
        ),

        .init(
            id: 3,
            startAngle: 0,
            endAngle: 50
        ),

        .init(
            id: 4,
            startAngle: 50,
            endAngle: 100
        ),

        .init(
            id: 5,
            startAngle: 100,
            endAngle: 150
        )
    ]
}


// MARK: - Exact Zest Slice Assembly Shell

struct ZestV34SliceAssemblyShell: View {

    @Environment(\.colorScheme)
    private var colorScheme

    let accentColor: Color
    let accentHighlightColor: Color
    let accentDeepColor: Color

    var showInstalledGlass: Bool = false

    // Presentation controls used by lightweight previews/onboarding. Defaults
    // preserve the production Zest exactly.
    var showsEmptySockets: Bool = true
    var centerOpacity: Double = 1
    var centerGlowIntensity: Double = 0
    // 0...1 horizontal specular sweep used by onboarding's power-on moment.
    // Defaults to 0 and is visually inert when centerGlowIntensity is zero.
    var centerShineProgress: CGFloat = 0

    var installedFeatures:
        [ZestSliceSlot: ZestFeature] = [:]

    var unconfiguredSlots: Set<ZestSliceSlot> = []

    var onInstalledFeatureTap:
        ((ZestFeature, ZestSliceSlot) -> Void)? = nil

    // Drag-and-drop is opt-in so miniature previews and
    // completed Zest renders continue behaving as before.

    var acceptsFeatureDrops: Bool = false

    var onFeatureDrop:
        ((ZestFeature, ZestSliceSlot) -> Void)? = nil

    @State
    private var nativeTargetedSlotID: Int?

    @State
    private var setupAlertBlink = false

    // Used by the physical puzzle-drag system.
    // SettingsView can now tell the shell which socket the
    // loose piece is magnetically approaching without using
    // macOS' native drop-target appearance.
    var magneticTargetSlot: ZestSliceSlot? = nil


    private var targetedSlotID: Int? {

        if let magneticTargetSlot {

            return ZestV34SliceVisualSlot.all
                .first {
                    $0.settingsSlot == magneticTargetSlot
                }?
                .id
        }

        return nativeTargetedSlotID
    }


    // Same proportions as the real 210 pt Zest.

    private let referenceSize:
        CGFloat = 210

    private let referenceInnerRadius:
        CGFloat = 43

    private let referenceOuterRadius:
        CGFloat = 98

    private let referenceGap:
        CGFloat = 2

    private let referenceEndGap:
        CGFloat = 4


    var body: some View {

        GeometryReader { proxy in

            let size =
                min(
                    proxy.size.width,
                    proxy.size.height
                )

            let scale =
                size / referenceSize

            let innerRadius =
                referenceInnerRadius
                * scale

            let outerRadius =
                referenceOuterRadius
                * scale

            let gap =
                referenceGap
                * scale

            let endGap =
                referenceEndGap
                * scale


            ZStack {

                // MARK: Real Zest chassis / rind

                exactRind(
                    size: size,
                    innerRadius: innerRadius
                )


                // MARK: Six exact tile positions

                ForEach(
                    ZestV34SliceVisualSlot.all
                ) { slot in

                    if showInstalledGlass
                        || installedFeatures[slot.settingsSlot] != nil {

                        exactTile(
                            slot: slot,
                            size: size,
                            innerRadius: innerRadius,
                            outerRadius: outerRadius,
                            gap: gap,
                            endGap: endGap
                        )

                        if let feature =
                            installedFeatures[slot.settingsSlot] {

                            exactInstalledFeatureLabel(
                                feature: feature,
                                slot: slot,
                                size: size,
                                innerRadius: innerRadius,
                                outerRadius: outerRadius
                            )

                            if let onInstalledFeatureTap {
                                Button {
                                    onInstalledFeatureTap(feature, slot.settingsSlot)
                                } label: {
                                    ZestTileShape(
                                        startAngle: slot.startAngle,
                                        endAngle: slot.endAngle,
                                        innerRadius: innerRadius,
                                        outerRadius: outerRadius,
                                        gapInset: gap,
                                        startGapInset: slot.id == 0 ? endGap : nil,
                                        endGapInset: slot.id == 5 ? endGap : nil
                                    )
                                    .fill(Color.clear)
                                    .contentShape(
                                        ZestTileShape(
                                            startAngle: slot.startAngle,
                                            endAngle: slot.endAngle,
                                            innerRadius: innerRadius,
                                            outerRadius: outerRadius,
                                            gapInset: gap,
                                            startGapInset: slot.id == 0 ? endGap : nil,
                                            endGapInset: slot.id == 5 ? endGap : nil
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                                .frame(width: size, height: size)
                                .focusable(false)
                            }
                        }

                    } else if showsEmptySockets {

                        exactSocket(
                            slot: slot,
                            size: size,
                            innerRadius: innerRadius,
                            outerRadius: outerRadius,
                            gap: gap,
                            endGap: endGap
                        )
                    }
                }


                // MARK: Center ring

                exactCenterRing(
                    innerRadius: innerRadius
                )
                .opacity(centerOpacity)


                // MARK: Center button

                exactCenterButton(
                    size: size,
                    innerRadius: innerRadius
                )
                .opacity(centerOpacity)
            }
            .frame(
                width: size,
                height: size
            )
            .position(
                x: proxy.size.width / 2,
                y: proxy.size.height / 2
            )
        }
        .aspectRatio(
            1,
            contentMode: .fit
        )
    }


    // MARK: - Rind

    @ViewBuilder
    private func exactRind(
        size: CGFloat,
        innerRadius: CGFloat
    ) -> some View {

        let scale =
            size / referenceSize

        let shape =
            ZestBodyShape(
                innerRadius:
                    innerRadius
            )


        ZStack {

            shape
                .fill(
                    accentHighlightColor.opacity(0.022)
                )
                .frame(
                    width: size,
                    height: size
                )
                .offset(
                    y: 1.2 * scale
                )


            Color.clear
                .frame(
                    width: size,
                    height: size
                )
                .glassEffect(
                    .regular.tint(
                        accentColor
                            .opacity(0.10)
                    ),
                    in: shape
                )


            shape
                .stroke(
                    LinearGradient(
                        stops: [

                            .init(
                                color:
                                    Color.clear,
                                location:
                                    0.35
                            ),

                            .init(
                                color:
                                    accentHighlightColor
                                        .opacity(0.16),
                                location:
                                    0.68
                            ),

                            .init(
                                color:
                                    accentDeepColor
                                        .opacity(0.22),
                                location:
                                    1
                            )
                        ],
                        startPoint:
                            .top,
                        endPoint:
                            .bottom
                    ),
                    lineWidth:
                        max(
                            0.7,
                            2.2 * scale
                        )
                )
                .frame(
                    width: size,
                    height: size
                )


            shape
                .stroke(
                    LinearGradient(
                        stops: [

                            .init(
                                color:
                                    Color.white
                                        .opacity(0.82),
                                location:
                                    0
                            ),

                            .init(
                                color:
                                    Color.white
                                        .opacity(0.32),
                                location:
                                    0.28
                            ),

                            .init(
                                color:
                                    accentHighlightColor
                                        .opacity(0.13),
                                location:
                                    0.65
                            ),

                            .init(
                                color:
                                    Color.clear,
                                location:
                                    1
                            )
                        ],
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    ),
                    lineWidth:
                        max(
                            0.45,
                            0.85 * scale
                        )
                )
                .frame(
                    width: size,
                    height: size
                )
        }
        .frame(
            width: size,
            height: size
        )
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.0)
                .repeatForever(autoreverses: true)
            ) {
                setupAlertBlink = true
            }
        }
        .shadow(
            color:
                Color.black.opacity(0.15),
            radius:
                10 * scale,
            x: 0,
            y:
                6 * scale
        )
        .shadow(
            color:
                accentColor.opacity(0.08),
            radius:
                6 * scale,
            x: 0,
            y:
                3 * scale
        )
    }


    // MARK: - Puzzle Socket

    @ViewBuilder
    private func exactSocket(
        slot: ZestV34SliceVisualSlot,
        size: CGFloat,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        gap: CGFloat,
        endGap: CGFloat
    ) -> some View {

        let scale =
            size / referenceSize

        let shape =
            ZestTileShape(
                startAngle:
                    slot.startAngle,
                endAngle:
                    slot.endAngle,
                innerRadius:
                    innerRadius,
                outerRadius:
                    outerRadius,
                gapInset:
                    gap,
                startGapInset:
                    slot.id == 0
                    ? endGap
                    : nil,
                endGapInset:
                    slot.id == 5
                    ? endGap
                    : nil
            )


        ZStack {

            // Deep recess

            shape
                .fill(
                    LinearGradient(
                        stops: [

                            .init(
                                color:
                                    colorScheme == .dark
                                    ? Color.black.opacity(0.42)
                                    : Color.white.opacity(0.32),
                                location:
                                    0
                            ),

                            .init(
                                color:
                                    colorScheme == .dark
                                    ? Color.black.opacity(0.62)
                                    : Color.white.opacity(0.20),
                                location:
                                    0.50
                            ),

                            .init(
                                color:
                                    colorScheme == .dark
                                    ? Color.black.opacity(0.76)
                                    : Color.white.opacity(0.10),
                                location:
                                    1
                            )
                        ],
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    )
                )
                .frame(
                    width: size,
                    height: size
                )


            // Slight accent underneath the socket

            shape
                .fill(
                    RadialGradient(
                        stops: [

                            .init(
                                color:
                                    accentColor
                                        .opacity(0.055),
                                location:
                                    0
                            ),

                            .init(
                                color:
                                    accentDeepColor
                                        .opacity(0.035),
                                location:
                                    0.48
                            ),

                            .init(
                                color:
                                    Color.clear,
                                location:
                                    1
                            )
                        ],
                        center:
                            UnitPoint(
                                x: 0.32,
                                y: 0.24
                            ),
                        startRadius:
                            0,
                        endRadius:
                            105 * scale
                    )
                )
                .frame(
                    width: size,
                    height: size
                )


            // Inner upper lip

            shape
                .stroke(
                    LinearGradient(
                        stops: [

                            .init(
                                color:
                                    Color.black
                                        .opacity(0.70),
                                location:
                                    0
                            ),

                            .init(
                                color:
                                    Color.black
                                        .opacity(0.28),
                                location:
                                    0.30
                            ),

                            .init(
                                color:
                                    accentColor
                                        .opacity(0.16),
                                location:
                                    0.68
                            ),

                            .init(
                                color:
                                    accentHighlightColor
                                        .opacity(0.24),
                                location:
                                    1
                            )
                        ],
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    ),
                    lineWidth:
                        max(
                            0.8,
                            2.4 * scale
                        )
                )
                .frame(
                    width: size,
                    height: size
                )


            // Fine polished socket rim

            shape
                .stroke(
                    LinearGradient(
                        stops: [

                            .init(
                                color:
                                    accentHighlightColor
                                        .opacity(0.46),
                                location:
                                    0
                            ),

                            .init(
                                color:
                                    Color.white
                                        .opacity(0.16),
                                location:
                                    0.20
                            ),

                            .init(
                                color:
                                    accentColor
                                        .opacity(0.26),
                                location:
                                    0.56
                            ),

                            .init(
                                color:
                                    accentDeepColor
                                        .opacity(0.34),
                                location:
                                    1
                            )
                        ],
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    ),
                    lineWidth:
                        max(
                            0.45,
                            0.90 * scale
                        )
                )
                .frame(
                    width: size,
                    height: size
                )


            // Tiny lower inner shadow

            shape
                .stroke(
                    Color.black.opacity(0.22),
                    lineWidth:
                        max(
                            0.5,
                            1.25 * scale
                        )
                )
                .frame(
                    width: size,
                    height: size
                )
                .offset(
                    y:
                        max(
                            0.5,
                            1.0 * scale
                        )
                )
                .mask(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.black
                        ],
                        startPoint:
                            .top,
                        endPoint:
                            .bottom
                    )
                )


            // MARK: Magnetic puzzle target

            if targetedSlotID == slot.id {

                // Instead of painting the entire socket with a loud
                // selection color, illuminate the recess itself.
                //
                // The idea is:
                //
                //      "this piece fits here"
                //
                // rather than:
                //
                //      "macOS accepts a drop here"

                shape
                    .fill(
                        RadialGradient(
                            stops: [

                                .init(
                                    color:
                                        accentHighlightColor
                                            .opacity(
                                                colorScheme == .dark
                                                ? 0.10
                                                : 0.085
                                            ),
                                    location: 0
                                ),

                                .init(
                                    color:
                                        accentColor
                                            .opacity(
                                                colorScheme == .dark
                                                ? 0.075
                                                : 0.050
                                            ),
                                    location: 0.48
                                ),

                                .init(
                                    color:
                                        Color.clear,
                                    location: 1
                                )
                            ],
                            center:
                                UnitPoint(
                                    x: 0.42,
                                    y: 0.36
                                ),
                            startRadius: 0,
                            endRadius:
                                max(
                                    34,
                                    105 * scale
                                )
                        )
                    )
                    .frame(
                        width: size,
                        height: size
                    )
                    .allowsHitTesting(false)


                // Inner illuminated lip.
                //
                // This is deliberately thin. It should feel like light
                // catching the polished wall of the socket rather than
                // a glowing selection outline.

                shape
                    .stroke(
                        LinearGradient(
                            stops: [

                                .init(
                                    color:
                                        Color.white
                                            .opacity(
                                                colorScheme == .dark
                                                ? 0.34
                                                : 0.66
                                            ),
                                    location: 0
                                ),

                                .init(
                                    color:
                                        accentHighlightColor
                                            .opacity(0.54),
                                    location: 0.34
                                ),

                                .init(
                                    color:
                                        accentColor
                                            .opacity(0.32),
                                    location: 0.72
                                ),

                                .init(
                                    color:
                                        accentDeepColor
                                            .opacity(0.24),
                                    location: 1
                                )
                            ],
                            startPoint:
                                .topLeading,
                            endPoint:
                                .bottomTrailing
                        ),
                        lineWidth:
                            max(
                                0.75,
                                1.45 * scale
                            )
                    )
                    .frame(
                        width: size,
                        height: size
                    )
                    .shadow(
                        color:
                            accentColor.opacity(
                                colorScheme == .dark
                                ? 0.18
                                : 0.12
                            ),
                        radius:
                            max(
                                2,
                                4.5 * scale
                            )
                    )
                    .allowsHitTesting(false)


                // Tiny specular reflection inside the socket.
                //
                // This is what should make the attraction feel more
                // physical instead of like a software highlight.

                shape
                    .stroke(
                        Color.white.opacity(
                            colorScheme == .dark
                            ? 0.16
                            : 0.38
                        ),
                        lineWidth:
                            max(
                                0.35,
                                0.65 * scale
                            )
                    )
                    .frame(
                        width: size,
                        height: size
                    )
                    .mask(
                        LinearGradient(
                            colors: [
                                Color.white,
                                Color.white.opacity(0.22),
                                Color.clear
                            ],
                            startPoint:
                                .topLeading,
                            endPoint:
                                .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
            }


            // MARK: Shape-accurate drop surface

            if acceptsFeatureDrops {

                shape
                    .fill(Color.clear)
                    .frame(
                        width: size,
                        height: size
                    )
                    .contentShape(shape)
                    .dropDestination(
                        for: String.self
                    ) { items, _ in

                        guard
                            let rawValue =
                                items.first,
                            let feature =
                                ZestFeature(
                                    rawValue:
                                        rawValue
                                )
                        else {
                            return false
                        }


                        onFeatureDrop?(
                            feature,
                            slot.settingsSlot
                        )


                        nativeTargetedSlotID =
                            nil

                        return true

                    } isTargeted: { targeted in

                        withAnimation(
                            .spring(
                                response: 0.20,
                                dampingFraction: 0.78
                            )
                        ) {

                            if targeted {

                                nativeTargetedSlotID =
                                    slot.id

                            } else if
                                nativeTargetedSlotID
                                == slot.id {

                                nativeTargetedSlotID =
                                    nil
                            }
                        }
                    }
            }
        }
        .frame(
            width: size,
            height: size
        )
    }


    // MARK: - Installed Feature Label

    @ViewBuilder
    private func exactInstalledFeatureLabel(
        feature: ZestFeature,
        slot: ZestV34SliceVisualSlot,
        size: CGFloat,
        innerRadius: CGFloat,
        outerRadius: CGFloat
    ) -> some View {

        let scale = size / referenceSize
        let angle = slot.centerAngle * Double.pi / 180
        let labelRadius = (innerRadius + outerRadius) / 2
        let x = size / 2 + CGFloat(cos(angle)) * labelRadius
        let y = size / 2 + CGFloat(sin(angle)) * labelRadius
        let needsSetup = unconfiguredSlots.contains(slot.settingsSlot)
        let gap = referenceGap * scale
        let endGap = referenceEndGap * scale

        if feature == .today && !needsSetup {
            ZestNokiaTodayWedgeFace(
                startAngle: slot.startAngle,
                endAngle: slot.endAngle,
                innerRadius: innerRadius,
                outerRadius: outerRadius,
                gapInset: gap,
                startGapInset: slot.id == 0 ? endGap : nil,
                endGapInset: slot.id == 5 ? endGap : nil,
                canvasSize: size,
                accentColor: accentColor,
                accentHighlightColor: accentHighlightColor,
                accentDeepColor: accentDeepColor
            )
            .frame(width: size, height: size)
            .allowsHitTesting(false)
        } else {
            VStack(spacing: max(1, 1.5 * scale)) {
                if needsSetup {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: max(13, 21 * scale), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.88))

                    Text(feature == .openShortcut ? "Application" : "Shortcut")
                        .font(.system(size: max(7, 8 * scale), weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.88))
                        .lineLimit(1)
                } else {
                    Image(systemName: feature.systemImage)
                        .font(.system(size: max(10, 17 * scale), weight: .semibold, design: .rounded))

                    Text(feature.title)
                        .font(.system(size: max(7, 8 * scale), weight: .medium))
                }
            }
            .foregroundStyle(needsSetup ? Color.black.opacity(0.88) : Color.primary.opacity(0.82))
            .position(x: x, y: y)
            .frame(width: size, height: size)
            .allowsHitTesting(false)
        }
    }


    // MARK: - Installed Tile

    @ViewBuilder
    private func exactTile(
        slot: ZestV34SliceVisualSlot,
        size: CGFloat,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        gap: CGFloat,
        endGap: CGFloat
    ) -> some View {

        let scale =
            size / referenceSize

        let needsSetup =
            unconfiguredSlots.contains(
                slot.settingsSlot
            )

        let tileAccentColor =
            needsSetup
            ? Color(
                red: 0.92,
                green: 0.16,
                blue: 0.08
            )
            : accentColor

        let tileHighlightColor =
            needsSetup
            ? Color(
                red: 1.00,
                green: 0.64,
                blue: 0.08
            )
            : accentHighlightColor

        let shape =
            ZestTileShape(
                startAngle:
                    slot.startAngle,
                endAngle:
                    slot.endAngle,
                innerRadius:
                    innerRadius,
                outerRadius:
                    outerRadius,
                gapInset:
                    gap,
                startGapInset:
                    slot.id == 0
                    ? endGap
                    : nil,
                endGapInset:
                    slot.id == 5
                    ? endGap
                    : nil
            )


        ZStack {

            shape
                .fill(
                    tileHighlightColor.opacity(0.045)
                )
                .frame(
                    width: size,
                    height: size
                )
                .offset(
                    y: 1.1 * scale
                )


            Color.clear
                .frame(
                    width: size,
                    height: size
                )
                .glassEffect(
                    .regular.tint(
                        tileAccentColor
                            .opacity(0.31)
                    ),
                    in: shape
                )


            shape
                .fill(
                    RadialGradient(
                        stops: [

                            .init(
                                color:
                                    Color.white
                                        .opacity(0.10),
                                location:
                                    0
                            ),

                            .init(
                                color:
                                    tileHighlightColor
                                        .opacity(0.08),
                                location:
                                    0.28
                            ),

                            .init(
                                color:
                                    tileHighlightColor
                                        .opacity(0.025),
                                location:
                                    0.62
                            ),

                            .init(
                                color:
                                    Color.clear,
                                location:
                                    1
                            )
                        ],
                        center:
                            UnitPoint(
                                x: 0.28,
                                y: 0.16
                            ),
                        startRadius:
                            0,
                        endRadius:
                            110 * scale
                    )
                )
                .frame(
                    width: size,
                    height: size
                )


            shape
                .stroke(
                    LinearGradient(
                        stops: [

                            .init(
                                color:
                                    Color.clear,
                                location:
                                    0.40
                            ),

                            .init(
                                color:
                                    tileHighlightColor
                                        .opacity(0.11),
                                location:
                                    0.66
                            ),

                            .init(
                                color:
                                    accentDeepColor
                                        .opacity(0.20),
                                location:
                                    1
                            )
                        ],
                        startPoint:
                            .top,
                        endPoint:
                            .bottom
                    ),
                    lineWidth:
                        max(
                            0.6,
                            2 * scale
                        )
                )
                .frame(
                    width: size,
                    height: size
                )


            shape
                .stroke(
                    LinearGradient(
                        stops: [

                            .init(
                                color:
                                    Color.white
                                        .opacity(0.82),
                                location:
                                    0
                            ),

                            .init(
                                color:
                                    Color.white
                                        .opacity(0.38),
                                location:
                                    0.22
                            ),

                            .init(
                                color:
                                    tileHighlightColor
                                        .opacity(0.12),
                                location:
                                    0.62
                            ),

                            .init(
                                color:
                                    accentDeepColor
                                        .opacity(0.14),
                                location:
                                    1
                            )
                        ],
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    ),
                    lineWidth:
                        max(
                            0.45,
                            0.85 * scale
                        )
                )
                .frame(
                    width: size,
                    height: size
                )
        }
        .opacity(
            needsSetup
            ? (setupAlertBlink ? 1.0 : 0.50)
            : 1.0
        )
        .frame(
            width: size,
            height: size
        )
        .shadow(
            color:
                Color.black.opacity(0.12),
            radius:
                max(
                    1,
                    3 * scale
                ),
            x: 0,
            y:
                max(
                    1,
                    2 * scale
                )
        )
    }


    // MARK: - Center Ring

    @ViewBuilder
    private func exactCenterRing(
        innerRadius: CGFloat
    ) -> some View {

        let diameter =
            innerRadius * 2

        let scale =
            diameter
            / (
                referenceInnerRadius
                * 2
            )


        ZStack {

            Circle()
                .fill(
                    accentDeepColor
                        .opacity(0.16)
                )
                .frame(
                    width:
                        diameter + 7 * scale,
                    height:
                        diameter + 7 * scale
                )


            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white
                                .opacity(0.62),
                            accentHighlightColor
                                .opacity(0.32),
                            accentDeepColor
                                .opacity(0.30)
                        ],
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    ),
                    lineWidth:
                        max(
                            0.7,
                            1.2 * scale
                        )
                )
                .frame(
                    width:
                        diameter + 7 * scale,
                    height:
                        diameter + 7 * scale
                )
        }
    }


    // MARK: - Center Button

    @ViewBuilder
    private func exactCenterButton(
        size: CGFloat,
        innerRadius: CGFloat
    ) -> some View {

        let scale =
            size / referenceSize

        let diameter =
            innerRadius * 2


        ZStack {

            Circle()
                .fill(
                    accentHighlightColor.opacity(0.050)
                )
                .frame(
                    width: diameter,
                    height: diameter
                )
                .offset(
                    y: 1.1 * scale
                )


            Color.clear
                .frame(
                    width: diameter,
                    height: diameter
                )
                .glassEffect(
                    .regular.tint(
                        accentColor
                            .opacity(0.36)
                    ),
                    in: Circle()
                )


            Circle()
                .fill(
                    RadialGradient(
                        stops: [

                            .init(
                                color:
                                    Color.white
                                        .opacity(0.13),
                                location:
                                    0
                            ),

                            .init(
                                color:
                                    accentHighlightColor
                                        .opacity(0.10),
                                location:
                                    0.28
                            ),

                            .init(
                                color:
                                    Color.clear,
                                location:
                                    0.78
                            )
                        ],
                        center:
                            UnitPoint(
                                x: 0.30,
                                y: 0.18
                            ),
                        startRadius:
                            0,
                        endRadius:
                            70 * scale
                    )
                )
                .frame(
                    width: diameter,
                    height: diameter
                )


            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white
                                .opacity(0.82),
                            Color.white
                                .opacity(0.32),
                            accentHighlightColor
                                .opacity(0.16),
                            accentDeepColor
                                .opacity(0.18)
                        ],
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    ),
                    lineWidth:
                        max(
                            0.45,
                            0.85 * scale
                        )
                )
                .frame(
                    width: diameter,
                    height: diameter
                )


            // Full-tile power-on illumination. This deliberately covers the
            // complete production center disc edge-to-edge; the bloom is a
            // separate outer shadow rather than a small radial lamp in its middle.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.50 * centerGlowIntensity),
                            accentHighlightColor.opacity(0.42 * centerGlowIntensity),
                            accentColor.opacity(0.32 * centerGlowIntensity)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: diameter, height: diameter)
                .overlay {
                    Circle()
                        .stroke(
                            Color.white.opacity(0.58 * centerGlowIntensity),
                            lineWidth: max(0.8, 1.5 * scale)
                        )
                }
                .shadow(
                    color: accentColor.opacity(0.72 * centerGlowIntensity),
                    radius: 22 * scale * centerGlowIntensity
                )
                .shadow(
                    color: Color.white.opacity(0.20 * centerGlowIntensity),
                    radius: 8 * scale * centerGlowIntensity
                )

            // A narrow specular reflection travels sideways across the complete
            // center glass tile while it is powered. It is clipped to the same
            // production circle, so this reads as moving glass reflection rather
            // than another small light source in the middle.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: Color.white.opacity(0.02 * centerGlowIntensity), location: 0.34),
                    .init(color: Color.white.opacity(0.62 * centerGlowIntensity), location: 0.50),
                    .init(color: Color.white.opacity(0.10 * centerGlowIntensity), location: 0.64),
                    .init(color: .clear, location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: diameter * 0.46, height: diameter * 1.35)
            .rotationEffect(.degrees(16))
            .offset(x: (-diameter * 0.82) + (diameter * 1.64 * centerShineProgress))
            .blur(radius: max(0.4, 1.4 * scale))
            .mask {
                Circle().frame(width: diameter, height: diameter)
            }
            .allowsHitTesting(false)

            VStack(
                spacing:
                    max(
                        0,
                        1 * scale
                    )
            ) {

                Text("EN")
                    .font(
                        .system(
                            size:
                                max(
                                    12,
                                    20 * scale
                                ),
                            weight:
                                .bold,
                            design:
                                .rounded
                        )
                    )


                Text("ABC")
                    .font(
                        .system(
                            size:
                                max(
                                    6,
                                    8 * scale
                                ),
                            weight:
                                .medium,
                            design:
                                .rounded
                        )
                    )
            }
            .foregroundStyle(
                Color.primary.opacity(0.82)
            )
        }
        .shadow(
            color:
                Color.black.opacity(0.13),
            radius:
                max(
                    1,
                    4 * scale
                ),
            x: 0,
            y:
                max(
                    1,
                    3 * scale
                )
        )
    }
}


// MARK: - Mini Form Factor Preview

struct ZestV34MiniSlicePreview: View {

    let accentColor: Color
    let accentHighlightColor: Color
    let accentDeepColor: Color


    var body: some View {

        ZestV34SliceAssemblyShell(
            accentColor:
                accentColor,
            accentHighlightColor:
                accentHighlightColor,
            accentDeepColor:
                accentDeepColor,
            showInstalledGlass:
                true
        )
        .frame(
            width: 78,
            height: 78
        )
    }
}


// MARK: - Detached REAL Zest Puzzle Tile

struct ZestV34LiquidGlassWedgePiece: View {

    let accentColor: Color
    let accentHighlightColor: Color
    let accentDeepColor: Color

    let symbol: String
    let title: String

    var installed:
        Bool = false

    // Used by the Settings assembly editor when the physical wedge itself
    // rotates. Applying the opposite angle to the label keeps its icon/text
    // vertically readable while the glass tile turns underneath it.
    var labelCounterRotationDegrees:
        Double = 0

    // High-frequency interactions (notably Settings dragging) use a cheap
    // painted approximation instead of asking Liquid Glass to re-composite
    // on every pointer event. Stationary Zest pieces still use real glass.
    var usesLiveGlass:
        Bool = true

    // Palette previews can use the exact physical wedge while keeping
    // their icon/title typography quieter than the installed slice.
    var labelScale:
        CGFloat = 1

    // Presentation-only controls for onboarding's sequential feature reveal.
    // Defaults preserve every production/Settings call site exactly.
    var labelOpacity: Double = 1
    var labelRevealScale: CGFloat = 1

    // Presentation-only optical centering. The production midpoint remains the
    // default. When enabled, the label uses the true area centroid of the
    // annular sector instead of requiring six hand-tuned X/Y offsets.
    var labelUsesSectorCentroid: Bool = false
    var labelRadialOffset: CGFloat = 0

    // Presentation-only X/Y optical correction in reference-size points.
    // It is scaled with the wedge, so callers can tune glyph placement with
    // simple coordinates without changing production geometry.
    var labelCartesianOffset: CGSize = .zero

    // Optional canonical production slot. The loose Settings piece keeps the
    // historical slot-0 default; onboarding can render each of the six exact
    // final Orange Slice shapes without rotating an approximation into place.
    var visualSlotID: Int = 0


    private let referenceSize:
        CGFloat = 210

    private let referenceInnerRadius:
        CGFloat = 43

    private let referenceOuterRadius:
        CGFloat = 98

    private let referenceGap:
        CGFloat = 2

    private let referenceEndGap:
        CGFloat = 4


    var body: some View {

        GeometryReader { proxy in

            let size =
                min(
                    proxy.size.width,
                    proxy.size.height
                )

            let scale =
                size / referenceSize

            let innerRadius =
                referenceInnerRadius
                * scale

            let outerRadius =
                referenceOuterRadius
                * scale

            let gap =
                referenceGap
                * scale

            let endGap =
                referenceEndGap
                * scale

            let slot =
                ZestV34SliceVisualSlot.all[
                    min(max(visualSlotID, 0), ZestV34SliceVisualSlot.all.count - 1)
                ]

            let shape =
                ZestTileShape(
                    startAngle:
                        slot.startAngle,
                    endAngle:
                        slot.endAngle,
                    innerRadius:
                        innerRadius,
                    outerRadius:
                        outerRadius,
                    gapInset:
                        gap,
                    startGapInset:
                        slot.id == 0 ? endGap : nil,
                    endGapInset:
                        slot.id == 5 ? endGap : nil
                )


            let angle =
                slot.centerAngle
                * Double.pi
                / 180

            let angularSpanDegrees = max(0.1, slot.endAngle - slot.startAngle)
            let angularSpan = angularSpanDegrees * Double.pi / 180
            let annularCentroidRadius: CGFloat = {
                guard labelUsesSectorCentroid else {
                    return (innerRadius + outerRadius) / 2
                }

                // Area centroid of an annular sector measured along its
                // angular bisector. This tracks the visible tile area rather
                // than the midpoint between the two radii.
                let outer2 = outerRadius * outerRadius
                let inner2 = innerRadius * innerRadius
                let radialMoment =
                    (outer2 * outerRadius - inner2 * innerRadius)
                    / max(0.001, outer2 - inner2)
                let angularMoment =
                    4 * sin(angularSpan / 2)
                    / max(0.001, 3 * angularSpan)
                return CGFloat(angularMoment) * radialMoment
            }()

            let labelRadius = annularCentroidRadius + labelRadialOffset * scale

            let labelX =
                size / 2
                + cos(angle)
                * labelRadius
                + labelCartesianOffset.width * scale

            let labelY =
                size / 2
                + sin(angle)
                * labelRadius
                + labelCartesianOffset.height * scale


            ZStack {

                if usesLiveGlass {

                    shape
                        .fill(
                            accentHighlightColor.opacity(
                                installed
                                ? 0.050
                                : 0.040
                            )
                        )
                        .frame(
                            width: size,
                            height: size
                        )
                        .offset(
                            y:
                                max(
                                    0.5,
                                    1.1 * scale
                                )
                        )


                    Color.clear
                        .frame(
                            width: size,
                            height: size
                        )
                        .glassEffect(
                            .regular.tint(
                                accentColor
                                    .opacity(
                                        installed
                                        ? 0.34
                                        : 0.27
                                    )
                            ),
                            in: shape
                        )

                } else {

                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    accentHighlightColor.opacity(0.30),
                                    accentColor.opacity(0.27),
                                    accentDeepColor.opacity(0.22)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(
                            width: size,
                            height: size
                        )
                }


                shape
                    .fill(
                        RadialGradient(
                            stops: [

                                .init(
                                    color:
                                        Color.white
                                            .opacity(0.11),
                                    location:
                                        0
                                ),

                                .init(
                                    color:
                                        accentHighlightColor
                                            .opacity(0.08),
                                    location:
                                        0.28
                                ),

                                .init(
                                    color:
                                        Color.clear,
                                    location:
                                        0.78
                                )
                            ],
                            center:
                                UnitPoint(
                                    x: 0.28,
                                    y: 0.16
                                ),
                            startRadius:
                                0,
                            endRadius:
                                80 * scale
                        )
                    )
                    .frame(
                        width: size,
                        height: size
                    )


                shape
                    .stroke(
                        LinearGradient(
                            stops: [

                                .init(
                                    color:
                                        Color.clear,
                                    location:
                                        0.40
                                ),

                                .init(
                                    color:
                                        accentColor
                                            .opacity(0.11),
                                    location:
                                        0.66
                                ),

                                .init(
                                    color:
                                        accentColor
                                            .opacity(0.24),
                                    location:
                                        1
                                )
                            ],
                            startPoint:
                                .top,
                            endPoint:
                                .bottom
                        ),
                        lineWidth:
                            max(
                                0.55,
                                2 * scale
                            )
                    )
                    .frame(
                        width: size,
                        height: size
                    )


                shape
                    .stroke(
                        LinearGradient(
                            stops: [

                                .init(
                                    color:
                                        Color.white
                                            .opacity(0.82),
                                    location:
                                        0
                                ),

                                .init(
                                    color:
                                        Color.white
                                            .opacity(0.38),
                                    location:
                                        0.22
                                ),

                                .init(
                                    color:
                                        accentColor
                                            .opacity(0.16),
                                    location:
                                        0.62
                                ),

                                .init(
                                    color:
                                        accentColor
                                            .opacity(0.08),
                                    location:
                                        1
                                )
                            ],
                            startPoint:
                                .topLeading,
                            endPoint:
                                .bottomTrailing
                        ),
                        lineWidth:
                            max(
                                0.45,
                                0.85 * scale
                            )
                    )
                    .frame(
                        width: size,
                        height: size
                    )


                if title == "Today" {
                    ZestNokiaTodayWedgeFace(
                        startAngle: slot.startAngle,
                        endAngle: slot.endAngle,
                        innerRadius: innerRadius,
                        outerRadius: outerRadius,
                        gapInset: gap,
                        startGapInset: slot.id == 0 ? endGap : nil,
                        endGapInset: slot.id == 5 ? endGap : nil,
                        canvasSize: size,
                        accentColor: accentColor,
                        accentHighlightColor: accentHighlightColor,
                        accentDeepColor: accentDeepColor,
                        counterRotationDegrees: labelCounterRotationDegrees
                    )
                    .frame(width: size, height: size)
                    .opacity(labelOpacity)
                    .scaleEffect(labelScale * labelRevealScale)
                } else {
                    VStack(
                        spacing:
                            max(
                                1,
                                1.5 * scale
                            )
                    ) {

                        Image(
                            systemName:
                                symbol
                        )
                        .font(
                            .system(
                                size:
                                    max(
                                        10,
                                        17 * scale
                                    ),
                                weight:
                                    .semibold,
                                design:
                                    .rounded
                            )
                        )
                        .frame(height: max(12, 19 * scale), alignment: .center)


                        Text(
                            title
                        )
                        .font(
                            .system(
                                size:
                                    max(
                                        7,
                                        8 * scale
                                    ),
                                weight:
                                    .medium
                            )
                        )
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.76)
                        .frame(
                            width: max(42, 72 * scale),
                            height: max(15, 22 * scale),
                            alignment: .top
                        )
                    }
                    .foregroundStyle(
                        Color.primary.opacity(
                            0.82
                        )
                    )
                    .opacity(labelOpacity)
                    .scaleEffect(labelScale * labelRevealScale)
                    .rotationEffect(
                        .degrees(
                            labelCounterRotationDegrees
                        )
                    )
                    .position(
                        x: labelX,
                        y: labelY
                    )
                }
            }
            .frame(
                width: size,
                height: size
            )
            .shadow(
                color:
                    Color.black.opacity(0.11),
                radius:
                    max(
                        1,
                        2.5 * scale
                    ),
                x: 0,
                y:
                    max(
                        1,
                        2 * scale
                    )
            )
            .shadow(
                color:
                    accentColor.opacity(0.07),
                radius:
                    max(
                        1,
                        3 * scale
                    ),
                x: 0,
                y:
                    max(
                        1,
                        2 * scale
                    )
            )
            .position(
                x: proxy.size.width / 2,
                y: proxy.size.height / 2
            )
        }
        .aspectRatio(
            1,
            contentMode: .fit
        )
    }
}


// MARK: - Legacy Rectangle Piece

struct ZestV34LiquidGlassPiece: View {

    let accentColor: Color
    let symbol: String
    let title: String

    var installed:
        Bool = false


    var body: some View {

        let shape =
            RoundedRectangle(
                cornerRadius: 13,
                style: .continuous
            )


        ZStack {

            Color.clear
                .glassEffect(
                    .regular.tint(
                        accentColor.opacity(
                            installed
                            ? 0.30
                            : 0.22
                        )
                    ),
                    in: shape
                )
                .offset(y: 1.6)


            Color.clear
                .glassEffect(
                    .regular.tint(
                        accentColor.opacity(
                            installed
                            ? 0.35
                            : 0.28
                        )
                    ),
                    in: shape
                )


            shape
                .fill(
                    RadialGradient(
                        stops: [

                            .init(
                                color:
                                    Color.white
                                        .opacity(0.11),
                                location:
                                    0
                            ),

                            .init(
                                color:
                                    accentColor
                                        .opacity(0.08),
                                location:
                                    0.30
                            ),

                            .init(
                                color:
                                    Color.clear,
                                location:
                                    0.78
                            )
                        ],
                        center:
                            UnitPoint(
                                x: 0.28,
                                y: 0.16
                            ),
                        startRadius:
                            0,
                        endRadius:
                            70
                    )
                )


            shape
                .stroke(
                    LinearGradient(
                        colors: [

                            Color.white
                                .opacity(0.82),

                            Color.white
                                .opacity(0.32),

                            accentColor
                                .opacity(0.16),

                            accentColor
                                .opacity(0.08)
                        ],
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    ),
                    lineWidth:
                        0.85
                )


            VStack(
                spacing: 3
            ) {

                Image(
                    systemName:
                        symbol
                )
                .font(
                    .system(
                        size: 17,
                        weight: .semibold
                    )
                )


                Text(
                    title
                )
                .font(
                    .system(
                        size: 9,
                        weight: .semibold
                    )
                )
            }
            .foregroundStyle(
                Color.primary.opacity(0.82)
            )
        }
        .shadow(
            color:
                Color.black.opacity(0.11),
            radius: 2.5,
            x: 0,
            y: 2
        )
        .shadow(
            color:
                accentColor.opacity(0.07),
            radius: 3,
            x: 0,
            y: 2
        )
    }
}
