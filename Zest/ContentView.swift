//
//  ContentView.swift
//  Zest
//
//  Created by Peter Grigorian on 19.10.26.
//

import SwiftUI
import AppKit

// MARK: - Triple Center Tile Shape

/// Rounded triple-mode tile with a shallow semicircular relief in its lower edge.
/// The relief gives the permanent Settings extrusion its own physical breathing room.
struct ZestTripleCenterTileShape: Shape {
    var cornerRadius: CGFloat = 13

    // The Settings support is 46 pt wide.  This relief is deliberately a
    // little larger so a thin air-gap remains between the tile and extrusion.
    var cutoutRadius: CGFloat = 27
    var cutoutCenterDrop: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        let radius = min(cutoutRadius, rect.width / 2 - 1)
        let center = CGPoint(x: rect.midX, y: rect.maxY + cutoutCenterDrop)

        // Where the circular relief intersects the normal bottom edge.
        let dy = rect.maxY - center.y
        let halfChord = sqrt(max(0, radius * radius - dy * dy))
        let rightJoin = CGPoint(x: center.x + halfChord, y: rect.maxY)
        let leftJoin  = CGPoint(x: center.x - halfChord, y: rect.maxY)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + r),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: rightJoin)

        // True circular bite: this follows the same center as the Settings
        // extrusion, producing the two little lower "legs" from the sketch
        // rather than a shallow U-shaped dent.
        let rightAngle = atan2(rightJoin.y - center.y, rightJoin.x - center.x)
        let leftAngle = atan2(leftJoin.y - center.y, leftJoin.x - center.x)
        let steps = 28
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let angle = rightAngle + (leftAngle - rightAngle) * t
            path.addLine(to: CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            ))
        }

        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
// MARK: - Control Model

struct ZestControl: Identifiable {
    let number: Int
    let feature: ZestFeature
    let symbol: String
    let title: String
    let startAngle: Double
    let endAngle: Double

    var id: Int { number }

    var centerAngle: Double {
        let correctedEnd = endAngle < startAngle ? endAngle + 360 : endAngle
        return (startAngle + correctedEnd) / 2
    }
}

// MARK: - Rounded Segment Shape

struct ZestTileShape: Shape {
    let startAngle: Double
    let endAngle: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let gapInset: CGFloat
    let startGapInset: CGFloat?
    let endGapInset: CGFloat?

    private let cornerRadius: CGFloat = 3.2

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let actualStartInset = startGapInset ?? gapInset
        let actualEndInset = endGapInset ?? gapInset

        func intersectionAngle(originalAngle: Double, radius: CGFloat, direction: Double, inset: CGFloat) -> Double {
            let ratio = min(inset / radius, 0.999)
            let offset = asin(ratio) * 180 / .pi
            return originalAngle + offset * direction
        }

        func point(radius: CGFloat, angle: Double) -> CGPoint {
            let radians = angle * .pi / 180
            return CGPoint(
                x: center.x + cos(radians) * radius,
                y: center.y + sin(radians) * radius
            )
        }

        func angleOffset(distance: CGFloat, radius: CGFloat) -> Double {
            asin(min(distance / radius, 0.999)) * 180 / .pi
        }

        let outerStartAngle = intersectionAngle(originalAngle: startAngle, radius: outerRadius, direction: 1, inset: actualStartInset)
        let innerStartAngle = intersectionAngle(originalAngle: startAngle, radius: innerRadius, direction: 1, inset: actualStartInset)
        let outerEndAngle = intersectionAngle(originalAngle: endAngle, radius: outerRadius, direction: -1, inset: actualEndInset)
        let innerEndAngle = intersectionAngle(originalAngle: endAngle, radius: innerRadius, direction: -1, inset: actualEndInset)

        let outerCornerAngle = angleOffset(distance: cornerRadius, radius: outerRadius)
        let innerCornerAngle = angleOffset(distance: cornerRadius, radius: innerRadius)

        let outerStartArc = point(radius: outerRadius, angle: outerStartAngle + outerCornerAngle)
        let outerStartSide = point(radius: outerRadius - cornerRadius, angle: outerStartAngle)
        let outerEndSide = point(radius: outerRadius - cornerRadius, angle: outerEndAngle)
        let innerEndSide = point(radius: innerRadius + cornerRadius, angle: innerEndAngle)
        let innerEndArc = point(radius: innerRadius, angle: innerEndAngle - innerCornerAngle)
        let innerStartSide = point(radius: innerRadius + cornerRadius, angle: innerStartAngle)

        var path = Path()
        path.move(to: outerStartArc)
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .degrees(outerStartAngle + outerCornerAngle),
            endAngle: .degrees(outerEndAngle - outerCornerAngle),
            clockwise: false
        )
        path.addQuadCurve(to: outerEndSide, control: point(radius: outerRadius, angle: outerEndAngle))
        path.addLine(to: innerEndSide)
        path.addQuadCurve(to: innerEndArc, control: point(radius: innerRadius, angle: innerEndAngle))
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .degrees(innerEndAngle - innerCornerAngle),
            endAngle: .degrees(innerStartAngle + innerCornerAngle),
            clockwise: true
        )
        path.addQuadCurve(to: innerStartSide, control: point(radius: innerRadius, angle: innerStartAngle))
        path.addLine(to: outerStartSide)
        path.addQuadCurve(to: outerStartArc, control: point(radius: outerRadius, angle: outerStartAngle))
        path.closeSubpath()
        return path
    }
}

// MARK: - Rounded Background Rind

struct ZestBodyShape: Shape {
    let innerRadius: CGFloat
    let openingTop: Double = 150
    let openingBottom: Double = 210
    private let cornerRadius: CGFloat = 5.0

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2

        func point(radius: CGFloat, angle: Double) -> CGPoint {
            let radians = angle * .pi / 180
            return CGPoint(
                x: center.x + cos(radians) * radius,
                y: center.y + sin(radians) * radius
            )
        }

        func angleOffset(distance: CGFloat, radius: CGFloat) -> Double {
            asin(min(distance / radius, 0.999)) * 180 / .pi
        }

        let outerOffset = angleOffset(distance: cornerRadius, radius: outerRadius)
        let innerOffset = angleOffset(distance: cornerRadius, radius: innerRadius)

        let outerBottomArc = point(radius: outerRadius, angle: openingBottom + outerOffset)
        let outerBottomSide = point(radius: outerRadius - cornerRadius, angle: openingBottom)
        let innerBottomSide = point(radius: innerRadius + cornerRadius, angle: openingBottom)
        let innerTopArc = point(radius: innerRadius, angle: openingTop + innerOffset)
        let innerTopSide = point(radius: innerRadius + cornerRadius, angle: openingTop)
        let outerTopSide = point(radius: outerRadius - cornerRadius, angle: openingTop)

        var path = Path()
        path.move(to: outerBottomArc)
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .degrees(openingBottom + outerOffset),
            endAngle: .degrees(openingTop - outerOffset + 360),
            clockwise: false
        )
        path.addQuadCurve(to: outerTopSide, control: point(radius: outerRadius, angle: openingTop + 360))
        path.addLine(to: innerTopSide)
        path.addQuadCurve(to: innerTopArc, control: point(radius: innerRadius, angle: openingTop))
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .degrees(openingTop + innerOffset),
            endAngle: .degrees(openingBottom - innerOffset),
            clockwise: true
        )
        path.addQuadCurve(to: innerBottomSide, control: point(radius: innerRadius, angle: openingBottom))
        path.addLine(to: outerBottomSide)
        path.addQuadCurve(to: outerBottomArc, control: point(radius: outerRadius, angle: openingBottom))
        path.closeSubpath()
        return path
    }
}

// MARK: - Button Styles

struct ZestPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .brightness(configuration.isPressed ? -0.025 : 0)
            .saturation(configuration.isPressed ? 1.08 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.68), value: configuration.isPressed)
            .focusable(false)
    }
}

struct ZestCenterHitButtonStyle: ButtonStyle {
    let direction: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                x: configuration.isPressed ? 0.96 : 1.0,
                y: configuration.isPressed ? 0.985 : 1.0,
                anchor: direction < 0 ? .leading : direction > 0 ? .trailing : .center
            )
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.spring(response: 0.14, dampingFraction: 0.62), value: configuration.isPressed)
            .focusable(false)
    }
}

struct ZestSmallCheckButtonStyle: ButtonStyle {
    let accentColor: Color
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 30, height: 28)
            .foregroundStyle(enabled ? Color.primary.opacity(0.90) : Color.secondary.opacity(0.32))
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        enabled
                        ? accentColor.opacity(configuration.isPressed ? 0.30 : 0.16)
                        : Color.clear
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.17, dampingFraction: 0.70), value: configuration.isPressed)
    }
}

struct ZestLargeApplyButtonStyle: ButtonStyle {
    let accentColor: Color
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(enabled ? 0.88 : 0.34))
            .frame(width: 62, height: 62)
            .background {
                Circle()
                    .fill(accentColor.opacity(enabled ? 0.16 : 0.06))
                    .offset(y: 1.8)
            }
            .glassEffect(
                .regular
                    .tint(accentColor.opacity(enabled ? 0.44 : 0.12))
                    .interactive(),
                in: Circle()
            )
            .overlay {
                Circle().fill(
                    RadialGradient(
                        stops: [
                            .init(color: Color.white.opacity(enabled ? 0.17 : 0.07), location: 0),
                            .init(color: accentColor.opacity(enabled ? 0.10 : 0.03), location: 0.34),
                            .init(color: Color.clear, location: 0.78)
                        ],
                        center: UnitPoint(x: 0.30, y: 0.16),
                        startRadius: 0,
                        endRadius: 52
                    )
                )
            }
            .overlay {
                Circle().stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.88),
                            Color.white.opacity(0.30),
                            accentColor.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
            }
            .shadow(color: Color.black.opacity(enabled ? 0.18 : 0.08), radius: enabled ? 8 : 4, x: 0, y: 5)
            .shadow(color: accentColor.opacity(enabled ? 0.16 : 0.04), radius: 7, x: 0, y: 3)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.20, dampingFraction: 0.66), value: configuration.isPressed)
    }
}

// MARK: - Size Control Panel

struct ZestSizePanel: View {
    @ObservedObject var textContextManager: TextContextManager
    let accentColor: Color
    @Binding var isPresented: Bool

    @State private var draftText = ""
    @State private var sliderValue: Double = 12
    @State private var isEditingText = false
    @State private var isScrubbing = false
    @State private var scrubStartSize: Int?
    @FocusState private var fieldFocused: Bool

    private let minimumSize = 1
    private let maximumSize = 1000
    private let minimumScrubSize = 6.0
    private let maximumScrubSize = 96.0

    private let scrubberMarkers: [Double] = [6, 12, 18, 24, 36, 48, 60, 72, 84, 96]
    private let majorScrubberMarkers: Set<Int> = [12, 24, 48, 96]

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 10) {
                numberEntry
                scrubber
            }

            Button {
                applyDraftAndClose()
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(
                ZestLargeApplyButtonStyle(
                    accentColor: accentColor,
                    enabled: parsedDraft != nil
                )
            )
            .disabled(parsedDraft == nil)
            .focusable(false)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 13)
        .frame(width: 300, height: 104)
        .background { glassBody }
        .shadow(color: Color.black.opacity(0.20), radius: 15, x: 0, y: 8)
        .shadow(color: accentColor.opacity(0.07), radius: 10, x: 0, y: 4)
        .onAppear { synchronizeFromContext() }
        .onChange(of: textContextManager.fontSize) { _, _ in
            guard !isEditingText, !isScrubbing else { return }
            synchronizeFromContext()
        }
        .onChange(of: fieldFocused) { _, focused in
            isEditingText = focused
            if !focused, !isScrubbing {
                synchronizeFromContext()
            }
        }
        .onExitCommand { cancelDraft() }
    }

    private var glassBody: some View {
        ZStack {
            Color.clear
                .glassEffect(
                    .regular.tint(accentColor.opacity(0.035)),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )

            RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [accentColor.opacity(0.075), Color.clear],
                        center: UnitPoint(x: 0.86, y: 0.18),
                        startRadius: 0,
                        endRadius: 170
                    )
                )
                .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                .allowsHitTesting(false)
        }
    }

    private var numberEntry: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                TextField("", text: $draftText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.trailing)
                    .focused($fieldFocused)
                    .onSubmit { applyDraft() }
                    .onChange(of: draftText) { _, newValue in
                        sanitizeDraft(newValue)
                    }

                Text("pt")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(
                        fieldFocused ? accentColor.opacity(0.55) : Color.white.opacity(0.24),
                        lineWidth: fieldFocused ? 1.15 : 0.75
                    )
            }

            Button {
                applyDraft()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(
                ZestSmallCheckButtonStyle(
                    accentColor: accentColor,
                    enabled: canApplyDraft
                )
            )
            .disabled(!canApplyDraft)
            .focusable(false)
        }
    }

    private var scrubber: some View {
        HStack(spacing: 7) {
            Text("A")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.secondary)

            VStack(spacing: 1) {
                Slider(
                    value: $sliderValue,
                    in: minimumScrubSize...maximumScrubSize,
                    step: 1
                ) { editing in
                    editing ? beginScrubbing() : finishScrubbing()
                }
                .tint(accentColor)
                .onChange(of: sliderValue) { oldValue, newValue in
                    guard isScrubbing else { return }
                    let oldSize = Int(oldValue.rounded())
                    let newSize = Int(newValue.rounded())
                    guard oldSize != newSize else { return }
                    draftText = String(newSize)
                }

                GeometryReader { geometry in
                    ZStack {
                        ForEach(scrubberMarkers, id: \.self) { marker in
                            let progress = (marker - minimumScrubSize) / (maximumScrubSize - minimumScrubSize)
                            let x = progress * geometry.size.width
                            let isMajor = majorScrubberMarkers.contains(Int(marker))

                            Circle()
                                .fill(Color.secondary.opacity(isMajor ? 0.48 : 0.30))
                                .frame(width: isMajor ? 3.2 : 2.4, height: isMajor ? 3.2 : 2.4)
                                .position(
                                    x: max(2, min(geometry.size.width - 2, x)),
                                    y: 2
                                )
                        }
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 4)
                .allowsHitTesting(false)
            }

            Text("A")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.secondary)
        }
    }

    private func beginScrubbing() {
        guard !isScrubbing else { return }
        isScrubbing = true
        scrubStartSize = currentSize
        fieldFocused = false
        isEditingText = false
    }

    private func finishScrubbing() {
        guard isScrubbing else { return }

        let target = Int(sliderValue.rounded())
        sliderValue = Double(target)
        draftText = String(target)

        let startSize = scrubStartSize
        scrubStartSize = nil

        if target != startSize {
            _ = textContextManager.setFontSize(target)
        }

        isScrubbing = false
    }

    private var currentSize: Int? {
        guard let fontSize = textContextManager.fontSize else { return nil }
        return Int(fontSize.rounded())
    }

    private var parsedDraft: Int? {
        guard
            let value = Int(draftText.trimmingCharacters(in: .whitespacesAndNewlines)),
            (minimumSize...maximumSize).contains(value)
        else {
            return nil
        }

        return value
    }

    private var canApplyDraft: Bool {
        guard let draft = parsedDraft else { return false }
        return draft != currentSize
    }

    private func sanitizeDraft(_ value: String) {
        let digits = value.filter { $0.isNumber }
        let limited = String(digits.prefix(4))
        if limited != value {
            draftText = limited
        }
    }

    private func applyDraft() {
        guard let target = parsedDraft, canApplyDraft else { return }

        let success = textContextManager.setFontSize(target)

        if success {
            sliderValue = scrubberPosition(for: target)
            draftText = String(target)
            fieldFocused = false
            isEditingText = false
        }
    }

    private func applyDraftAndClose() {
        guard let target = parsedDraft else { return }

        isScrubbing = false
        scrubStartSize = nil

        if target != currentSize {
            let success = textContextManager.setFontSize(target)
            guard success else { return }
        }

        fieldFocused = false
        isEditingText = false

        withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
            isPresented = false
        }
    }

    private func cancelDraft() {
        fieldFocused = false
        isEditingText = false
        isScrubbing = false
        scrubStartSize = nil
        synchronizeFromContext()
    }

    private func synchronizeFromContext() {
        guard let size = currentSize else {
            draftText = ""
            return
        }

        draftText = String(size)
        sliderValue = scrubberPosition(for: size)
    }

    private func scrubberPosition(for size: Int) -> Double {
        min(maximumScrubSize, max(minimumScrubSize, Double(size)))
    }
}


// MARK: - Runtime popup placement support

private struct ZestRuntimeHostFrameReader: NSViewRepresentable {
    let onChange: (CGRect) -> Void

    final class Coordinator {
        var lastPublishedFrame: CGRect = .null
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { publish(view, coordinator: context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // SwiftUI can call updateNSView many times during hover/glass animation.
        // Publish only when the actual screen-space host frame changed.
        DispatchQueue.main.async { publish(nsView, coordinator: context.coordinator) }
    }

    private func publish(_ view: NSView, coordinator: Coordinator) {
        guard let window = view.window else { return }
        let rectInWindow = view.convert(view.bounds, to: nil)
        let frame = window.convertToScreen(rectInWindow)
        guard frame != coordinator.lastPublishedFrame else { return }
        coordinator.lastPublishedFrame = frame
        onChange(frame)
    }
}

private struct ZestRuntimePopupSizeKey: PreferenceKey {
    static var defaultValue: [String: CGSize] = [:]
    static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    func zestRuntimePopupMeasured(_ key: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: ZestRuntimePopupSizeKey.self, value: [key: proxy.size])
            }
        }
    }
}

// MARK: - Main Zest View

private struct ZestCenterRuntimeSectorShape: Shape {
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


// Transparent hit-test ring used as the physical drag bezel in Center Only
// 2/4 Split View. Even-odd fill leaves the feature buttons in the middle free.
struct ZestRuntimeBezelDragShape: Shape {
    var innerRatio: CGFloat = 0.78

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        path.addArc(center: c, radius: outer, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        path.addArc(center: c, radius: inner, startAngle: .degrees(360), endAngle: .degrees(0), clockwise: true)
        path.closeSubpath()
        return path
    }
}

struct ContentView: View {

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    // MARK: Managers

    @ObservedObject var textContextManager: TextContextManager
    @ObservedObject var fontLibraryManager: FontLibraryManager

    @StateObject private var inputSourceManager = InputSourceManager()
    @StateObject private var clipboardManager = ClipboardHistoryManager()
    @ObservedObject var settingsManager: ZestSettingsManager
    var onOpenSettings: (() -> Void)? = nil
    // Keyboard-assistant hosts use these hooks to keep the non-activating panel
    // visually vivid and to report the real runtime canvas position on screen.
    var forceVibrantRendering: Bool = false
    var onRuntimeHostFrameChange: ((CGRect) -> Void)? = nil
    // Exact screen-space bounds of the visible keyboard-assistant control.
    // Unlike the 620×360 runtime canvas this is the thing we actually anchor.
    var onRuntimeControlFrameChange: ((CGRect) -> Void)? = nil
    // Exact screen-space bounds of the currently visible feature popup. The
    // keyboard host uses this together with the control frame to distinguish
    // real Zest interaction from clicks in the large transparent presentation stage.
    var onRuntimePopupFrameChange: ((CGRect?) -> Void)? = nil
    // Keyboard-assistant hosts can move the native panel directly while the
    // user drags one of Zest's physical grab handles. `translation` is the
    // gesture translation from its starting point; `ended` commits the move.
    var onRuntimeDrag: ((_ translation: CGSize, _ ended: Bool) -> Void)? = nil
    // Keyboard host can temporarily enlarge its transparent presentation field
    // while a feature panel is open, preventing the beautiful glass UI from
    // being clipped by the compact assistant window.
    var onRuntimePopupPresentationChange: ((_ presented: Bool) -> Void)? = nil

    // MARK: State

    @State private var hoveredControl: Int? = nil
    // Hover state is intentionally index-only: animations stay GPU-friendly and
    // do not trigger any accessibility/context refresh work.
    @State private var hoveredTripleFeatureIndex: Int? = nil
    @State private var hoveredCenterFeatureIndex: Int? = nil
    @State private var sizePanelPresented = false
    @State private var fontPanelPresented = false
    @State private var clipboardPanelPresented = false
    @State private var calendarPanelPresented = false
    @State private var todayPanelPresented = false
    @State private var batteryPanelPresented = false
    @State private var layoutFixPanelPresented = false
    @State private var centerPush: CGFloat = 0

    // Main Orange Slice center turntable.
    @State private var mainSliceLanguageRotation: Double = 0
    @State private var mainSliceLanguageOpacity: Double = 1
    @State private var mainSliceCommittedOffset: CGSize = .zero
    @State private var mainSliceDragTranslation: CGSize = .zero

    @State private var centerOnlySelectionIndex: Int = 0
    @State private var centerOnlySlideDirection: CGFloat = 1
    @State private var centerOnlyLanguageRotation: Double = 0
    @State private var centerOnlyLanguageOpacity: Double = 1
    @State private var centerOnlyClockCalendarShowsCalendar = false
    @State private var centerOnlyClockCalendarRotation: Double = 0
    @State private var centerOnlyClockCalendarOpacity: Double = 1
    @StateObject
    private var emojiLibraryManager =
        EmojiLibraryManager()

    @State
    private var emojiPanelPresented =
        false
    
    @StateObject
    private var symbolLibraryManager =
        SymbolLibraryManager()

    @State
    private var symbolPanelPresented =
        false

    private func openSettingsWindow() {
        // Settings is explicit-only: the inspector dismisses first, then the
        // dedicated Settings scene is asked to appear. Ordinary Zest activation
        // can therefore never surface Settings by accident.
        onOpenSettings?()
        openSettings()
    }

    // MARK: Runtime popup placement

    @State private var runtimeHostScreenFrame: CGRect = .zero
    @State private var runtimeControlScreenFrame: CGRect = .zero
    @State private var menuBarPopupAnchorScreen: CGPoint? = nil
    @State private var menuBarPopupSide: CGFloat = 1
    @State private var runtimePopupSizes: [String: CGSize] = [:]
    @State private var activeTripleFeatureIndex: Int = 1
    @State private var activeCenterFeatureCount: Int = 2
    @State private var activeCenterFeatureIndex: Int = 0
    @State private var activeSliceControlNumber: Int = 2

    // MARK: Geometry

    private let size: CGFloat = 210
    private let centerRadius: CGFloat = 39
    private let innerTileRadius: CGFloat = 43
    private let outerTileRadius: CGFloat = 98
    private let tileGapInset: CGFloat = 2
    private let endGapInset: CGFloat = 4

    // MARK: Palette

    private var zestAccent: Color {
        settingsManager.accentColor
    }

    private var zestOrange: Color {
        settingsManager.accentColor
    }

    private var zestAmber: Color {
        settingsManager.accentBrightColor
    }

    private var zestGold: Color {
        settingsManager.accentHighlightColor
    }

    private var deepAmber: Color {
        settingsManager.accentDeepColor
    }

    // Rear structural glass can intentionally differ from foreground controls.
    // Aqua uses classic silver/chrome supports while its buttons stay blue.
    private var rearGlassPrimary: Color {
        settingsManager.rearGlassPrimaryColor
    }

    private var rearGlassBright: Color {
        settingsManager.rearGlassBrightColor
    }

    private var rearGlassHighlight: Color {
        settingsManager.rearGlassHighlightColor
    }

    private var rearGlassDeep: Color {
        settingsManager.rearGlassDeepColor
    }

    // MARK: Controls

    private var controls: [ZestControl] {
        let geometry: [(ZestSliceSlot, Int, Double, Double)] = [
            (.slot2, 2, 210, 260),
            (.slot3, 3, 260, 310),
            (.slot4, 4, 310, 360),
            (.slot5, 5, 0, 50),
            (.slot6, 6, 50, 100),
            (.slot7, 7, 100, 150)
        ]

        return geometry.compactMap { slot, number, startAngle, endAngle in
            guard let feature = settingsManager.runtimeSliceAssignments[slot] else { return nil }
            return ZestControl(
                number: number,
                feature: feature,
                symbol: feature.systemImage,
                title: feature.title,
                startAngle: startAngle,
                endAngle: endAngle
            )
        }
    }

    var body: some View {
        ZStack {
            Group {
                if settingsManager.runtimeFormFactor == .centerOnly || settingsManager.runtimeFormFactor == .turntable {
                    centerOnlyRuntimeControl
                } else if settingsManager.runtimeFormFactor == .tripleSquare {
                    tripleRuntimeControl
                } else {
                    ZStack {
                        outerRind
                        ForEach(controls) { control in segment(control) }
                        centerRing
                        centerControl
                    }
                    .frame(width: size, height: size)
                    // Track the pointer once at the slice level. The six wedge
                    // buttons overlap in rectangular SwiftUI layout space, so
                    // per-Button onHover can report the topmost wedge for the
                    // whole control. Geometry tracking keeps hover visual-only
                    // and resolves the actual wedge under the pointer.
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoveredControl = orangeSliceControl(at: location)
                        case .ended:
                            hoveredControl = nil
                        }
                    }
                    .offset(
                        x: mainSliceCommittedOffset.width + mainSliceDragTranslation.width,
                        y: mainSliceCommittedOffset.height + mainSliceDragTranslation.height
                    )
                }
            }
            .fixedSize()
            // Restore the brighter live/non-key appearance from the stable runtime.
            // Settings previews remain untouched; this compensates only the in-field
            // keyboard-assistant host where macOS compositing otherwise deepens accents.
            .brightness(forceVibrantRendering ? 0.075 : 0)
            .saturation(forceVibrantRendering ? 1.05 : 1.0)
            // Apply the runtime placement BEFORE measuring its global frame.
            // The native click-through monitor consumes this frame, so measuring
            // before the +120 placement offset could make the exposed right-hand
            // turntable badge look "outside" Zest and dismiss the panel on click.
            .offset(x: 120)
            .background {
                ZestRuntimeHostFrameReader { frame in
                    // Center Ring modes can render attached wings/badges outside the
                    // nominal circular face. Report a slightly expanded interactive
                    // region so the native transparent-host click monitor does not
                    // dismiss Zest before those SwiftUI buttons receive the click.
                    let interactiveFrame = (settingsManager.runtimeFormFactor == .centerOnly || settingsManager.runtimeFormFactor == .turntable)
                        ? frame.insetBy(dx: -48, dy: -30)
                        : frame
                    if runtimeControlScreenFrame != interactiveFrame {
                        runtimeControlScreenFrame = interactiveFrame
                    }
                    onRuntimeControlFrameChange?(interactiveFrame)
                }
            }
            .zIndex(10)
            .onReceive(NotificationCenter.default.publisher(for: .zestSaturnPrevious)) { _ in
                if (settingsManager.runtimeFormFactor == .centerOnly || settingsManager.runtimeFormFactor == .turntable) && ["language", "languageClock"].contains(settingsManager.runtimeCenterOnlyPage) {
                    animateCenterOnlyLanguageChange(direction: -1) { inputSourceManager.refresh() }
                } else if settingsManager.runtimeFormFactor == .orangeSlice {
                    animateMainSliceLanguageChange(direction: -1) { inputSourceManager.refresh() }
                } else {
                    inputSourceManager.refresh()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .zestSaturnNext)) { _ in
                if (settingsManager.runtimeFormFactor == .centerOnly || settingsManager.runtimeFormFactor == .turntable) && ["language", "languageClock"].contains(settingsManager.runtimeCenterOnlyPage) {
                    animateCenterOnlyLanguageChange(direction: 1) { inputSourceManager.refresh() }
                } else if settingsManager.runtimeFormFactor == .orangeSlice {
                    animateMainSliceLanguageChange(direction: 1) { inputSourceManager.refresh() }
                } else {
                    inputSourceManager.refresh()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .zestMenuFeatureAnchoredRequested)) { notification in
                guard let raw = notification.object as? String,
                      let feature = ZestFeature(rawValue: raw) else { return }
                if let x = notification.userInfo?["anchorX"] as? CGFloat,
                   let y = notification.userInfo?["anchorY"] as? CGFloat {
                    menuBarPopupAnchorScreen = CGPoint(x: x, y: y)
                }
                menuBarPopupSide = notification.userInfo?["side"] as? CGFloat ?? 1
                performMenuBarFeature(feature)
            }

            if sizePanelPresented {
                ZestSizePanel(
                    textContextManager: textContextManager,
                    accentColor: zestAccent,
                    isPresented: $sizePanelPresented
                )
                .zestVisibilityBackdrop()
                .zestRuntimePopupMeasured("size")
                .background {
                    ZestRuntimeHostFrameReader { frame in
                        onRuntimePopupFrameChange?(frame)
                    }
                }
                .offset(runtimePopupOffset(for: .size, measuredKey: "size"))
                .transition(runtimePopupTransition(for: .size))
                .zIndex(20)
            }

            if fontPanelPresented {
                ZestFontPanel(
                    textContextManager: textContextManager,
                    fontLibraryManager: fontLibraryManager,
                    accentColor: zestAccent,
                    isPresented: $fontPanelPresented
                )
                .zestVisibilityBackdrop()
                .zestRuntimePopupMeasured("font")
                .background {
                    ZestRuntimeHostFrameReader { frame in
                        onRuntimePopupFrameChange?(frame)
                    }
                }
                .offset(runtimePopupOffset(for: .font, measuredKey: "font"))
                .transition(runtimePopupTransition(for: .font))
                .zIndex(21)
            }
            if clipboardPanelPresented {
                ZestClipboardPanel(
                    clipboardManager: clipboardManager,
                    accentColor: zestAccent
                )
                .zestVisibilityBackdrop()
                .zestRuntimePopupMeasured("clipboard")
                .background {
                    ZestRuntimeHostFrameReader { frame in
                        onRuntimePopupFrameChange?(frame)
                    }
                }
                .offset(runtimePopupOffset(for: .clipboard, measuredKey: "clipboard"))
                .transition(runtimePopupTransition(for: .clipboard))
                .zIndex(22)
            }
            if emojiPanelPresented {

                ZestEmojiPanel(
                    emojiLibraryManager:
                        emojiLibraryManager,
                    clipboardManager:
                        clipboardManager,
                    accentColor:
                        zestAccent
                )
                .zestVisibilityBackdrop()
                .zestRuntimePopupMeasured("emoji")
                .background {
                    ZestRuntimeHostFrameReader { frame in
                        onRuntimePopupFrameChange?(frame)
                    }
                }
                .offset(runtimePopupOffset(for: .emoji, measuredKey: "emoji"))
                .transition(runtimePopupTransition(for: .emoji))
                .zIndex(23)
            }
            
            if symbolPanelPresented {

                ZestSymbolPanel(
                    symbolLibraryManager:
                        symbolLibraryManager,
                    clipboardManager:
                        clipboardManager,
                    accentColor:
                        zestAccent
                )
                .zestVisibilityBackdrop()
                .zestRuntimePopupMeasured("symbols")
                .background {
                    ZestRuntimeHostFrameReader { frame in
                        onRuntimePopupFrameChange?(frame)
                    }
                }
                .offset(runtimePopupOffset(for: .symbols, measuredKey: "symbols"))
                .transition(runtimePopupTransition(for: .symbols))
                .zIndex(24)
            }

            if calendarPanelPresented {
                ZestCalendarPanel(
                    accentColor: zestAccent,
                    onOpenSettings: { openSettingsWindow() }
                )
                    .zestRuntimePopupMeasured("calendar")
                    .background { ZestRuntimeHostFrameReader { frame in onRuntimePopupFrameChange?(frame) } }
                    .offset(runtimePopupOffset(for: .calendar, measuredKey: "calendar"))
                    .transition(runtimePopupTransition(for: .calendar))
                    .zIndex(25)
            }

            if todayPanelPresented {
                ZestTodayPanel(accentColor: zestAccent)
                    .zestRuntimePopupMeasured("today")
                    .background { ZestRuntimeHostFrameReader { frame in onRuntimePopupFrameChange?(frame) } }
                    .offset(runtimePopupOffset(for: .today, measuredKey: "today"))
                    .transition(runtimePopupTransition(for: .today))
                    .zIndex(25.5)
            }

            if batteryPanelPresented {
                ZestBatteryPanel(accentColor: zestAccent)
                    .zestRuntimePopupMeasured("battery")
                    .background { ZestRuntimeHostFrameReader { frame in onRuntimePopupFrameChange?(frame) } }
                    .offset(runtimePopupOffset(for: .battery, measuredKey: "battery"))
                    .transition(runtimePopupTransition(for: .battery))
                    .zIndex(26)
            }

            if layoutFixPanelPresented {
                ZestLayoutFixPanel(accentColor: zestAccent)
                    .zestRuntimePopupMeasured("layoutFix")
                    .background { ZestRuntimeHostFrameReader { frame in onRuntimePopupFrameChange?(frame) } }
                    .offset(runtimePopupOffset(for: .layoutFix, measuredKey: "layoutFix"))
                    .transition(runtimePopupTransition(for: .layoutFix))
                    .zIndex(27)
            }
            
        }
        .frame(width: 1400, height: 1000)
        // The visible Zest control remains centered at exactly the same point, but
        // the SwiftUI runtime stage now matches the complete native transparent host,
        // so Calendar/search popups cannot hit a smaller internal clipping canvas.
        // NSPanel intentionally remains non-key so the editor keeps the caret.
        // Compensate only visually: explicit saturation/contrast prevents macOS
        // inactive-window compositing from washing the Zest palette toward gray.
        .saturation(1.0)
        .contrast(1.0)
        .background {
            ZestRuntimeHostFrameReader { frame in
                if runtimeHostScreenFrame != frame { runtimeHostScreenFrame = frame }
                onRuntimeHostFrameChange?(frame)
            }
        }
        .onPreferenceChange(ZestRuntimePopupSizeKey.self) { sizes in
            // Measuring glass popups can emit the same preference repeatedly.
            // Avoid invalidating the entire ContentView for a no-op update.
            if runtimePopupSizes != sizes {
                runtimePopupSizes = sizes
            }
        }
        .onAppear {
            inputSourceManager.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .zestRuntimeCanvasScreenFrameDidChange)) { note in
            guard let info = note.userInfo,
                  let x = info["x"] as? CGFloat,
                  let y = info["y"] as? CGFloat,
                  let w = info["w"] as? CGFloat,
                  let h = info["h"] as? CGFloat else { return }
            runtimeHostScreenFrame = CGRect(x: x, y: y, width: w, height: h)
        }
        // A popup belongs to the runtime layout that launched it. If Settings
        // commits another form factor, dismiss any surviving panel immediately
        // through the normal departure animation. This is especially important
        // for Center Only / Language Switcher, which intentionally has no
        // feature buttons that could otherwise toggle an orphaned popup off.
        .onChange(of: settingsManager.runtimeFormFactor) { _, _ in
            closeAllFeaturePanels()
        }
        .onChange(of: anyRuntimePopupPresented) { _, presented in
            onRuntimePopupPresentationChange?(presented)
            if !presented { onRuntimePopupFrameChange?(nil) }
        }
        .onChange(of: settingsManager.runtimeCenterOnlyPage) { _, newPage in
            if settingsManager.runtimeFormFactor == .turntable
                || (settingsManager.runtimeFormFactor == .centerOnly && ["language", "languageClock", "clockCalendar"].contains(newPage)) {
                closeAllFeaturePanels()
            }
        }
    }

    // MARK: - Heavy Molded Glass Rind

    private var outerRind: some View {
        let shape = ZestBodyShape(innerRadius: innerTileRadius)

        return ZStack {
            shape
                .fill(rearGlassBright.opacity(0.030))
                .frame(width: size, height: size)
                .offset(y: 1.2)

            Color.clear
                .frame(width: size, height: size)
                .glassEffect(.regular.tint(rearGlassPrimary.opacity(0.11)), in: shape)

            shape
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color.clear, location: 0.35),
                            .init(color: rearGlassBright.opacity(0.18), location: 0.68),
                            .init(color: rearGlassDeep.opacity(0.24), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 2.2
                )
                .frame(width: size, height: size)

            shape
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.82), location: 0),
                            .init(color: Color.white.opacity(0.32), location: 0.28),
                            .init(color: rearGlassHighlight.opacity(0.18), location: 0.65),
                            .init(color: Color.clear, location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.85
                )
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 6)
        .shadow(color: rearGlassPrimary.opacity(0.08), radius: 6, x: 0, y: 3)
    }

    private func orangeSliceControl(at location: CGPoint) -> Int? {
        let dx = location.x - size / 2
        let dy = location.y - size / 2
        let radius = hypot(dx, dy)

        // Only the clickable outer wedges participate. The center/gear keeps
        // its own established hover behavior.
        guard radius >= innerTileRadius - 2, radius <= outerTileRadius + 4 else { return nil }

        var degrees = atan2(dy, dx) * 180 / .pi
        if degrees < 0 { degrees += 360 }

        return controls.first(where: { control in
            if control.startAngle <= control.endAngle {
                return degrees >= control.startAngle && degrees < control.endAngle
            }
            return degrees >= control.startAngle || degrees < control.endAngle
        })?.number
    }

    // MARK: - Juicy Molded Segment

    private func segment(_ control: ZestControl) -> some View {
        let shape = ZestTileShape(
            startAngle: control.startAngle,
            endAngle: control.endAngle,
            innerRadius: innerTileRadius,
            outerRadius: outerTileRadius,
            gapInset: tileGapInset,
            startGapInset: control.number == 2 ? endGapInset : nil,
            endGapInset: control.number == 7 ? endGapInset : nil
        )

        let isHovered = hoveredControl == control.number
        let tileAccent = settingsManager.accentColor(at: control.number - 2)

        return Button {
            menuBarPopupAnchorScreen = nil
            activeSliceControlNumber = control.number
            switch control.feature {
            case .size:
                let wasOpen = sizePanelPresented
                closeAllFeaturePanels()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { sizePanelPresented = !wasOpen }

            case .font:
                let wasOpen = fontPanelPresented
                closeAllFeaturePanels()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { fontPanelPresented = !wasOpen }

            case .clipboard:
                let wasOpen = clipboardPanelPresented
                closeAllFeaturePanels()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { clipboardPanelPresented = !wasOpen }

            case .emoji:
                let wasOpen = emojiPanelPresented
                closeAllFeaturePanels()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { emojiPanelPresented = !wasOpen }

            case .symbols:
                let wasOpen = symbolPanelPresented
                closeAllFeaturePanels()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { symbolPanelPresented = !wasOpen }

            case .calendar:
                let wasOpen = calendarPanelPresented
                closeAllFeaturePanels()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { calendarPanelPresented = !wasOpen }

            case .today:
                let wasOpen = todayPanelPresented
                closeAllFeaturePanels()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { todayPanelPresented = !wasOpen }

            case .battery:
                let wasOpen = batteryPanelPresented
                closeAllFeaturePanels()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { batteryPanelPresented = !wasOpen }

            case .layoutFix:
                let wasOpen = layoutFixPanelPresented
                closeAllFeaturePanels()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { layoutFixPanelPresented = !wasOpen }

            case .rapidSymbols:
                closeAllFeaturePanels()
                ZestRapidSymbolEngine.shared.arm()

            case .settings:
                openSettingsWindow()

            case .empty:
                break

            case .openShortcut, .runShortcut, .url:
                if let slot = ZestSliceSlot(rawValue: control.number),
                   settingsManager.isConfigured(control.feature, in: slot) {
                    _ = settingsManager.performConfiguredAction(for: control.feature, in: slot)
                } else {
                    // An unconfigured action opens Settings, where the tile
                    // carries an exclamation badge and can be configured.
                    openSettingsWindow()
                }
            }
        } label: {
            ZStack {
                shape
                    .fill((forceVibrantRendering ? tileAccent : zestAmber).opacity(forceVibrantRendering ? (isHovered ? 0.78 : 0.68) : (isHovered ? 0.055 : 0.040)))
                    .frame(width: size, height: size)
                    .offset(y: 1.2)

                Color.clear
                    .frame(width: size, height: size)
                    .glassEffect(
                        .regular
                            .tint(tileAccent.opacity(forceVibrantRendering ? (isHovered ? 0.72 : 0.64) : (isHovered ? 0.36 : 0.31))),
                        in: shape
                    )

                shape
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: Color.white.opacity(isHovered ? 0.14 : 0.10), location: 0),
                                .init(color: tileAccent.opacity(isHovered ? 0.16 : 0.10), location: 0.28),
                                .init(color: zestAmber.opacity(0.025), location: 0.62),
                                .init(color: Color.clear, location: 1)
                            ],
                            center: UnitPoint(x: 0.28, y: 0.16),
                            startRadius: 0,
                            endRadius: 110
                        )
                    )
                    .frame(width: size, height: size)

                shape
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: Color.clear, location: 0.40),
                                .init(color: zestAmber.opacity(0.11), location: 0.66),
                                .init(color: deepAmber.opacity(isHovered ? 0.25 : 0.20), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 2.0
                    )
                    .frame(width: size, height: size)

                shape
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(isHovered ? 0.94 : 0.82), location: 0),
                                .init(color: Color.white.opacity(0.38), location: 0.22),
                                .init(color: zestGold.opacity(0.16), location: 0.62),
                                .init(color: tileAccent.opacity(0.08), location: 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isHovered ? 1.0 : 0.85
                    )
                    .frame(width: size, height: size)

                tileLabel(control)
            }
            .frame(width: size, height: size)
            .contentShape(shape)
            .shadow(
                color: Color.black.opacity(isHovered ? 0.15 : 0.11),
                radius: isHovered ? 4 : 2.5,
                x: 0,
                y: isHovered ? 3 : 2
            )
            .shadow(
                color: tileAccent.opacity(isHovered ? 0.13 : 0.07),
                radius: isHovered ? 5 : 3,
                x: 0,
                y: 2
            )
            .scaleEffect(isHovered ? 1.018 : 1)
            .offset(y: isHovered ? -1.2 : 0)
            .animation(.spring(response: 0.20, dampingFraction: 0.78), value: isHovered)
        }
        .buttonStyle(ZestPressButtonStyle())
        .focusable(false)
    }

    private func performMenuBarFeature(_ feature: ZestFeature) {
        switch feature {
        case .size:
            let wasOpen = sizePanelPresented; closeAllFeaturePanels(); withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { sizePanelPresented = !wasOpen }
        case .font:
            let wasOpen = fontPanelPresented; closeAllFeaturePanels(); withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { fontPanelPresented = !wasOpen }
        case .clipboard:
            let wasOpen = clipboardPanelPresented; closeAllFeaturePanels(); withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { clipboardPanelPresented = !wasOpen }
        case .emoji:
            let wasOpen = emojiPanelPresented; closeAllFeaturePanels(); withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { emojiPanelPresented = !wasOpen }
        case .symbols:
            let wasOpen = symbolPanelPresented; closeAllFeaturePanels(); withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { symbolPanelPresented = !wasOpen }
        case .calendar:
            let wasOpen = calendarPanelPresented; closeAllFeaturePanels(); withAnimation { calendarPanelPresented = !wasOpen }
        case .today:
            let wasOpen = todayPanelPresented; closeAllFeaturePanels(); withAnimation { todayPanelPresented = !wasOpen }
        case .battery:
            let wasOpen = batteryPanelPresented; closeAllFeaturePanels(); withAnimation { batteryPanelPresented = !wasOpen }
        case .layoutFix:
            let wasOpen = layoutFixPanelPresented; closeAllFeaturePanels(); withAnimation { layoutFixPanelPresented = !wasOpen }
        case .rapidSymbols:
            closeAllFeaturePanels(); ZestRapidSymbolEngine.shared.arm()
        case .settings:
            openSettingsWindow()
        case .openShortcut, .runShortcut, .url, .empty:
            break
        }
    }

    private var anyRuntimePopupPresented: Bool {
        sizePanelPresented || fontPanelPresented || clipboardPanelPresented || emojiPanelPresented || symbolPanelPresented || calendarPanelPresented || todayPanelPresented || batteryPanelPresented || layoutFixPanelPresented
    }

    private func closeAllFeaturePanels() {
        guard anyRuntimePopupPresented else { return }

        // Keep removal inside an explicit transaction. SwiftUI transitions only
        // animate when the state mutation itself is animated; previously several
        // call sites cleared the old panel outside the opening spring, so it
        // vanished instead of dissolving/departing.
        withAnimation(.easeOut(duration: 0.18)) {
            sizePanelPresented = false
            fontPanelPresented = false
            clipboardPanelPresented = false
            emojiPanelPresented = false
            symbolPanelPresented = false
            calendarPanelPresented = false
            todayPanelPresented = false
            batteryPanelPresented = false
            layoutFixPanelPresented = false
        }
    }


    // MARK: - Center Ring

    private var centerRing: some View {
        let diameter = innerTileRadius * 2

        return ZStack {
            // Saturn-style structural bezel: a quiet rear-glass lip around the
            // glossy language face, matching the compact turntable language.
            Circle()
                .fill(rearGlassBright.opacity(0.075))
                .frame(width: diameter, height: diameter)
                .offset(y: 1.2)

            Color.clear
                .frame(width: diameter, height: diameter)
                .glassEffect(
                    .regular.tint(rearGlassPrimary.opacity(0.105)),
                    in: Circle()
                )

            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.18), location: 0),
                            .init(color: rearGlassHighlight.opacity(0.08), location: 0.34),
                            .init(color: Color.clear, location: 0.78)
                        ],
                        center: UnitPoint(x: 0.27, y: 0.16),
                        startRadius: 0,
                        endRadius: diameter * 0.72
                    )
                )
                .frame(width: diameter - 1.5, height: diameter - 1.5)
                .allowsHitTesting(false)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.88),
                            Color.white.opacity(0.31),
                            rearGlassHighlight.opacity(0.16),
                            rearGlassDeep.opacity(0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
                .frame(width: diameter, height: diameter)
                .allowsHitTesting(false)

            // Fine inner rim gives the same nested / machined Saturn feeling
            // without adding another live glass pass.
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            zestGold.opacity(0.10),
                            deepAmber.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.65
                )
                .frame(width: diameter - 5.5, height: diameter - 5.5)
                .allowsHitTesting(false)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: Color.black.opacity(0.13), radius: 3.5, x: 0, y: 2.4)
        .shadow(color: rearGlassPrimary.opacity(0.055), radius: 4, x: 0, y: 1)
    }

    // MARK: - Triple Runtime

    @State private var runtimeSettingsGearHover = false

    private var tripleRuntimeControl: some View {
        ZestV34TripleTileControl(
            features: settingsManager.runtimeTripleFeatures,
            featureColors: (0..<3).map { settingsManager.accentColor(at: $0) },
            accentColor: zestOrange,
            accentBrightColor: zestAmber,
            accentHighlightColor: zestGold,
            accentDeepColor: deepAmber,
            rearGlassPrimaryColor: rearGlassPrimary,
            rearGlassBrightColor: rearGlassBright,
            forceVibrantRendering: forceVibrantRendering,
            featureIcon: { feature, index in
                AnyView(
                    configuredCenterRuntimeIcon(
                        feature,
                        count: 3,
                        index: index,
                        size: 20
                    )
                )
            },
            onFeature: { feature, index in
                performTripleFeature(feature, index: index)
            },
            onSettings: {
                openSettingsWindow()
            },
            onDrag: { translation, ended in
                onRuntimeDrag?(translation, ended)
            }
        )
    }

    // MARK: - Runtime repositioning

    private var runtimePanelDragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in onRuntimeDrag?(value.translation, false) }
            .onEnded { value in onRuntimeDrag?(value.translation, true) }
    }

    private func runtimeDragHandle(diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(rearGlassBright.opacity(0.16))
                .glassEffect(.regular.tint(zestOrange.opacity(forceVibrantRendering ? 0.60 : 0.18)), in: Circle())
                .overlay { Circle().stroke(Color.white.opacity(0.70), lineWidth: 0.7) }
                .shadow(color: .black.opacity(0.14), radius: 2.2, y: 1.3)

            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: diameter * 0.40, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.78))
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(runtimePanelDragGesture)
    }

    // MARK: - Adaptive feature popup placement

    /// Keeps each panel physically related to the tile/sector that launched it.
    /// The returned vector points from the Zest control toward that feature.
    private func runtimePopupDirection(for feature: ZestFeature) -> CGVector {
        switch settingsManager.runtimeFormFactor {
        case .tripleSquare:
            // Triple Square always prefers a vertical launch. Screen-edge logic
            // can flip this below the complete control.
            return CGVector(dx: 0, dy: -1)

        case .centerOnly, .turntable:
            let count = max(activeCenterFeatureCount, 2)
            let index = min(max(activeCenterFeatureIndex, 0), count - 1)
            let degrees: Double
            if count == 2 {
                degrees = index == 0 ? -90 : 90
            } else if count == 3 {
                degrees = [145, 90, 35][index]
            } else {
                degrees = [-90, 0, 90, 180][index]
            }
            let r = degrees * .pi / 180
            return CGVector(dx: cos(r), dy: sin(r))

        case .orangeSlice:
            // Midpoints of the six physical Orange Slice sectors, clockwise.
            let degreesByControl: [Int: Double] = [
                2: 235, 3: 285, 4: 335, 5: 25, 6: 75, 7: 125
            ]
            let degrees = degreesByControl[activeSliceControlNumber] ?? 285
            let r = degrees * .pi / 180
            return CGVector(dx: cos(r), dy: sin(r))
        }
    }

    private func runtimePopupOffset(for feature: ZestFeature, measuredKey: String) -> CGSize {
        let measured = runtimePopupSizes[measuredKey] ?? defaultPopupSize(for: feature)
        let reserved = reservedPopupPlacementSize(for: feature)
        // Calendar and Today change height as their event content changes. Never let a
        // transient smaller GeometryReader measurement shrink their safety envelope;
        // that was the recurring cause of the top of Calendar being placed off-screen.
        let popup: CGSize
        if feature == .calendar || feature == .today {
            popup = CGSize(
                width: max(measured.width, reserved.width),
                height: max(measured.height, reserved.height)
            )
        } else {
            popup = measured
        }
        let compactGap: CGFloat = 14

        // Triple Square has one spatial rule only: feature panels live above the
        // complete tower, or below it when the top bezel leaves insufficient room.
        // The individual left/middle/right socket may influence horizontal alignment,
        // but it must NEVER turn into a left/right launch.
        if settingsManager.runtimeFormFactor == .tripleSquare {
            let index = min(max(activeTripleFeatureIndex, 0), 2)
            let socketX: [CGFloat] = [54, 120, 186]
            let x = socketX[index]
            let mainPlateTopEdge: CGFloat = -53.5
            let expandedBottomEdge: CGFloat = 58
            let belowGap: CGFloat = 8

            var candidate = CGPoint(
                x: x,
                y: mainPlateTopEdge - compactGap - popup.height / 2
            )

            // Test vertical feasibility only. Horizontal bezel pressure is solved by
            // sliding the panel along the top/bottom edge, never by changing sides.
            let aboveRect = popupScreenRect(centerOffset: candidate, size: popup)
            if let visible = runtimeVisibleScreenFrame, aboveRect.minY < visible.minY + 8 || aboveRect.maxY > visible.maxY - 8 {
                candidate.y = expandedBottomEdge + belowGap + popup.height / 2
            }

            let finalClamped = clampPopupToVisibleHost(
                centerOffset: candidate,
                size: popup,
                margin: 8
            )
            return CGSize(width: finalClamped.x, height: finalClamped.y)
        }

        let direction = runtimePopupDirection(for: feature)
        let length = max(hypot(direction.dx, direction.dy), 0.001)
        let ux = direction.dx / length
        let uy = direction.dy / length

        let controlRadius: CGFloat
        switch settingsManager.runtimeFormFactor {
        case .centerOnly, .turntable:
            let compactCenterFace = ["language", "clockCalendar", "languageClock"].contains(centerOnlyRuntimeMode)
            controlRadius = centerRadius * (compactCenterFace ? 1.0 : 1.20) * 1.30
        case .orangeSlice:
            controlRadius = outerTileRadius
        case .tripleSquare:
            controlRadius = 0
        }

        var candidate: CGPoint

        if settingsManager.runtimeFormFactor == .orangeSlice,
           [2, 4, 5, 7].contains(activeSliceControlNumber) {
            let tileAnchor = CGPoint(
                x: 120 + ux * controlRadius,
                y: uy * controlRadius
            )
            let sx: CGFloat = ux < 0 ? -1 : 1
            let sy: CGFloat = uy < 0 ? -1 : 1
            let diagonalGap = compactGap / sqrt(2)
            candidate = CGPoint(
                x: tileAnchor.x + sx * (popup.width / 2 + diagonalGap),
                y: tileAnchor.y + sy * (popup.height / 2 + diagonalGap)
            )
        } else {
            let popupSupport = abs(ux) * popup.width / 2 + abs(uy) * popup.height / 2
            let distance = controlRadius + compactGap + popupSupport
            candidate = CGPoint(
                x: 120 + ux * distance,
                y: uy * distance
            )
        }

        // Calendar is substantially taller than Zest's legacy feature popups.
        // Keep it horizontally attached to the launching sector but vertically
        // centered inside the runtime stage. This prevents diagonal launch geometry
        // from pushing the top half outside the transparent host.
        if feature == .calendar {
            candidate.y = 0
        }

        if settingsManager.runtimeFormFactor == .orangeSlice {
            candidate.x += mainSliceCommittedOffset.width + mainSliceDragTranslation.width
            candidate.y += mainSliceCommittedOffset.height + mainSliceDragTranslation.height
        }

        // IMPORTANT: bezel pressure is not allowed to change the launch side.
        // A right-hand sector stays a right-hand popup; a left-hand sector stays
        // left. Near an edge we slide the popup up/down (and minimally clamp it into
        // the visible frame) instead of mirroring it across Zest. This preserves the
        // user's spatial map for tiles 4/5/6 even when Zest hugs a display bezel.
        let bounded = clampPopupToVisibleHost(
            centerOffset: candidate,
            size: popup,
            margin: 8
        )
        let separated = resolvePopupCollision(
            centerOffset: bounded,
            size: popup,
            preferredDirection: direction,
            gap: compactGap
        )
        let finalClamped = clampPopupToVisibleHost(
            centerOffset: separated,
            size: popup,
            margin: 8
        )
        return CGSize(width: finalClamped.x, height: finalClamped.y)
    }

    /// Keeps the popup and the visible Zest control as two distinct objects.
    /// First we preserve the tile's preferred side; if the bezel makes that
    /// physically impossible (notably 2/4 Split and corner cases), we choose the
    /// nearest free side instead of allowing the panel to cover Zest.
    private func resolvePopupCollision(
        centerOffset: CGPoint,
        size popup: CGSize,
        preferredDirection: CGVector,
        gap: CGFloat
    ) -> CGPoint {
        guard runtimeControlScreenFrame.width > 0,
              let visible = runtimeVisibleScreenFrame else { return centerOffset }

        let safeControl = runtimeControlScreenFrame.insetBy(dx: -gap, dy: -gap)
        let currentRect = popupScreenRect(centerOffset: centerOffset, size: popup)
        if !currentRect.intersects(safeControl) { return centerOffset }

        enum Side: Equatable { case right, left, above, below }
        let preferred: Side
        if settingsManager.runtimeFormFactor == .orangeSlice {
            // Orange Slice is hemisphere-stable, not dominant-axis-stable.
            // Every sector physically living on the left half of Zest must keep
            // its popup on the left; every right-half sector must keep it on the
            // right. In particular the steep lower sectors (6/7) must NOT be
            // reclassified as "below" merely because |dy| > |dx| -- doing that
            // let the collision fallback choose the opposite horizontal side.
            preferred = preferredDirection.dx >= 0 ? .right : .left
        } else if abs(preferredDirection.dx) >= abs(preferredDirection.dy) {
            preferred = preferredDirection.dx >= 0 ? .right : .left
        } else {
            // SwiftUI offset Y grows downward while AppKit screen Y grows upward.
            preferred = preferredDirection.dy >= 0 ? .below : .above
        }

        var order: [Side] = [preferred]
        for side in [Side.right, .left, .above, .below] where !order.contains(side) {
            order.append(side)
        }

        func screenCenter(for side: Side) -> CGPoint {
            let original = popupScreenCenter(for: centerOffset)
            switch side {
            case .right:
                return CGPoint(x: safeControl.maxX + popup.width / 2, y: original.y)
            case .left:
                return CGPoint(x: safeControl.minX - popup.width / 2, y: original.y)
            case .above:
                return CGPoint(x: original.x, y: safeControl.maxY + popup.height / 2)
            case .below:
                return CGPoint(x: original.x, y: safeControl.minY - popup.height / 2)
            }
        }

        func clampScreenCenter(_ c: CGPoint) -> CGPoint {
            var c = c
            let margin: CGFloat = 8
            let minX = visible.minX + popup.width / 2 + margin
            let maxX = visible.maxX - popup.width / 2 - margin
            let minY = visible.minY + popup.height / 2 + margin
            let maxY = visible.maxY - popup.height / 2 - margin
            if minX <= maxX { c.x = min(max(c.x, minX), maxX) }
            if minY <= maxY { c.y = min(max(c.y, minY), maxY) }
            return c
        }

        var best: (CGPoint, CGFloat)?
        for (rank, side) in order.enumerated() {
            let screenCenter = clampScreenCenter(screenCenter(for: side))
            let rect = CGRect(
                x: screenCenter.x - popup.width / 2,
                y: screenCenter.y - popup.height / 2,
                width: popup.width,
                height: popup.height
            )
            guard !rect.intersects(safeControl) else { continue }
            let delta = hypot(screenCenter.x - currentRect.midX, screenCenter.y - currentRect.midY)
            let score = CGFloat(rank) * 10_000 + delta
            if best == nil || score < best!.1 { best = (screenCenter, score) }
        }

        guard let screenCenter = best?.0 else { return centerOffset }
        return CGPoint(
            x: screenCenter.x - runtimeHostScreenFrame.midX,
            y: runtimeHostScreenFrame.midY - screenCenter.y
        )
    }

    /// A short radial ride-out: the panel begins slightly behind the sector
    /// that launched it, then resolves into its final adaptive position.
    private func runtimePopupTransition(for feature: ZestFeature) -> AnyTransition {
        let d = runtimePopupDirection(for: feature)
        let length = max(hypot(d.dx, d.dy), 0.001)
        let ux = d.dx / length
        let uy = d.dy / length
        return .offset(x: -ux * 18, y: -uy * 18)
            .combined(with: .scale(scale: 0.975))
            .combined(with: .opacity)
    }

    private func reservedPopupPlacementSize(for feature: ZestFeature) -> CGSize {
        switch feature {
        case .emoji, .symbols:
            // Includes the complete search-results grid. This prevents a pinned
            // right-side popup from growing through the display bezel mid-search.
            return CGSize(width: 360, height: 520)
        case .font:
            return CGSize(width: 360, height: 430)
        case .clipboard:
            return CGSize(width: 320, height: 390)
        case .size:
            return CGSize(width: 300, height: 110)
        case .calendar:
            return CGSize(width: 400, height: 650)
        case .today:
            return CGSize(width: 410, height: 520)
        case .battery:
            return CGSize(width: 300, height: 220)
        case .layoutFix:
            return CGSize(width: 360, height: 300)
        default:
            return CGSize(width: 320, height: 220)
        }
    }

    private func defaultPopupSize(for feature: ZestFeature) -> CGSize {
        switch feature {
        case .size: return CGSize(width: 300, height: 104)
        case .clipboard: return CGSize(width: 320, height: 370)
        case .font, .emoji, .symbols: return CGSize(width: 360, height: 330)
        case .calendar: return CGSize(width: 360, height: 520)
        case .today: return CGSize(width: 410, height: 520)
        case .battery: return CGSize(width: 300, height: 210)
        case .layoutFix: return CGSize(width: 360, height: 260)
        default: return CGSize(width: 320, height: 220)
        }
    }

    private func popupFitsVisibleScreen(centerOffset: CGPoint, size popup: CGSize) -> Bool {
        guard runtimeHostScreenFrame.width > 0, let visible = runtimeVisibleScreenFrame else { return true }
        let rect = popupScreenRect(centerOffset: centerOffset, size: popup)
        return visible.insetBy(dx: 8, dy: 8).contains(rect)
    }

    /// Clamps a popup to the one rectangle it is actually allowed to occupy:
    /// the intersection of the visible monitor and Zest's transparent NSPanel host.
    /// This prevents a tall popup from being "on screen" but outside the invisible
    /// host window, which is what repeatedly clipped the top of Calendar.
    private func clampPopupToVisibleHost(
        centerOffset: CGPoint,
        size popup: CGSize,
        margin: CGFloat
    ) -> CGPoint {
        guard runtimeHostScreenFrame.width > 0,
              runtimeHostScreenFrame.height > 0,
              let visible = runtimeVisibleScreenFrame else { return centerOffset }

        let legalFrame = visible.intersection(runtimeHostScreenFrame)
        guard !legalFrame.isNull, !legalFrame.isEmpty else { return centerOffset }

        var center = popupScreenCenter(for: centerOffset)
        let minX = legalFrame.minX + popup.width / 2 + margin
        let maxX = legalFrame.maxX - popup.width / 2 - margin
        let minY = legalFrame.minY + popup.height / 2 + margin
        let maxY = legalFrame.maxY - popup.height / 2 - margin

        if minX <= maxX { center.x = min(max(center.x, minX), maxX) }
        if minY <= maxY { center.y = min(max(center.y, minY), maxY) }

        return CGPoint(
            x: center.x - runtimeHostScreenFrame.midX,
            y: runtimeHostScreenFrame.midY - center.y
        )
    }

    /// Keeps a runtime popup inside the invisible NSPanel/SwiftUI presentation canvas.
    /// Screen clamping alone is not enough: the 1400×1000 transparent host can be
    /// positioned partially off-screen beside the caret, and SwiftUI clips anything
    /// that crosses that host boundary even when the same rectangle is valid on the
    /// physical display. Calendar exposed this because it is much taller than Zest's
    /// older feature panels.
    private func clampPopupToRuntimeCanvas(
        centerOffset: CGPoint,
        size popup: CGSize,
        margin: CGFloat
    ) -> CGPoint {
        let hostSize = runtimeHostScreenFrame.size
        guard hostSize.width > 0, hostSize.height > 0 else { return centerOffset }

        var result = centerOffset
        let halfHostWidth = hostSize.width / 2
        let halfHostHeight = hostSize.height / 2
        let minX = -halfHostWidth + popup.width / 2 + margin
        let maxX = halfHostWidth - popup.width / 2 - margin
        let minY = -halfHostHeight + popup.height / 2 + margin
        let maxY = halfHostHeight - popup.height / 2 - margin

        if minX <= maxX { result.x = min(max(result.x, minX), maxX) }
        if minY <= maxY { result.y = min(max(result.y, minY), maxY) }
        return result
    }

    private func clampPopupToVisibleScreen(centerOffset: CGPoint, size popup: CGSize, margin: CGFloat) -> CGPoint {
        guard runtimeHostScreenFrame.width > 0, let visible = runtimeVisibleScreenFrame else { return centerOffset }
        var screenCenter = popupScreenCenter(for: centerOffset)
        let minX = visible.minX + popup.width / 2 + margin
        let maxX = visible.maxX - popup.width / 2 - margin
        let minY = visible.minY + popup.height / 2 + margin
        let maxY = visible.maxY - popup.height / 2 - margin
        if minX <= maxX { screenCenter.x = min(max(screenCenter.x, minX), maxX) }
        if minY <= maxY { screenCenter.y = min(max(screenCenter.y, minY), maxY) }
        return CGPoint(
            x: screenCenter.x - runtimeHostScreenFrame.midX,
            y: runtimeHostScreenFrame.midY - screenCenter.y
        )
    }

    private var runtimeVisibleScreenFrame: CGRect? {
        let center = CGPoint(x: runtimeHostScreenFrame.midX, y: runtimeHostScreenFrame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
    }

    private func popupScreenCenter(for centerOffset: CGPoint) -> CGPoint {
        CGPoint(
            x: runtimeHostScreenFrame.midX + centerOffset.x,
            y: runtimeHostScreenFrame.midY - centerOffset.y
        )
    }

    private func popupScreenRect(centerOffset: CGPoint, size popup: CGSize) -> CGRect {
        let c = popupScreenCenter(for: centerOffset)
        return CGRect(x: c.x - popup.width / 2, y: c.y - popup.height / 2, width: popup.width, height: popup.height)
    }

    private func performTripleFeature(_ feature: ZestFeature, index: Int) {
        menuBarPopupAnchorScreen = nil
        activeTripleFeatureIndex = index
        switch feature {
        case .size: let w = sizePanelPresented; closeAllFeaturePanels(); withAnimation { sizePanelPresented = !w }
        case .font: let w = fontPanelPresented; closeAllFeaturePanels(); withAnimation { fontPanelPresented = !w }
        case .clipboard: let w = clipboardPanelPresented; closeAllFeaturePanels(); withAnimation { clipboardPanelPresented = !w }
        case .emoji: let w = emojiPanelPresented; closeAllFeaturePanels(); withAnimation { emojiPanelPresented = !w }
        case .symbols: let w = symbolPanelPresented; closeAllFeaturePanels(); withAnimation { symbolPanelPresented = !w }
        case .calendar: let w = calendarPanelPresented; closeAllFeaturePanels(); withAnimation { calendarPanelPresented = !w }
        case .today: let w = todayPanelPresented; closeAllFeaturePanels(); withAnimation { todayPanelPresented = !w }
        case .battery: let w = batteryPanelPresented; closeAllFeaturePanels(); withAnimation { batteryPanelPresented = !w }
        case .layoutFix: let w = layoutFixPanelPresented; closeAllFeaturePanels(); withAnimation { layoutFixPanelPresented = !w }
        case .rapidSymbols: closeAllFeaturePanels(); ZestRapidSymbolEngine.shared.arm()
        case .settings: openSettingsWindow()
        case .openShortcut, .runShortcut, .url:
            if !settingsManager.performCenterConfiguredAction(feature, count: 3, index: index) { openSettingsWindow() }
        case .empty: break
        }
    }

    // MARK: - Center-Only Runtime

    private var centerOnlyRuntimeMode: String {
        ["language", "clockCalendar", "languageClock", "calendarThree", "clockThree", "twoFeature", "fourFeature"].contains(settingsManager.runtimeCenterOnlyPage)
            ? settingsManager.runtimeCenterOnlyPage
            : "language"
    }


    private var centerOnlyRuntimeControl: some View {
        // Runtime shows only the Center Only control itself. The larger
        // circular page-selector buttons belong to Settings/configuration.
        centerOnlyRuntimeRing
            .scaleEffect(1.30)
            .frame(
                width: (centerRadius * 2 + 100) * 1.30,
                height: (centerRadius * 2 + 72) * 1.30
            )
            .onAppear { syncCenterOnlyRuntimeSelection() }
            .onChange(of: settingsManager.runtimeCenterOnlyPage) { _, _ in
                syncCenterOnlyRuntimeSelection()
            }
    }


    @ViewBuilder
    private var centerOnlyRuntimeRing: some View {
        switch centerOnlyRuntimeMode {
        case "language":
            ZestV34CenterOnlyLanguageTurntable(
                accentColor: zestOrange,
                accentBrightColor: zestAmber,
                accentHighlightColor: zestGold,
                accentDeepColor: deepAmber,
                rearGlassPrimaryColor: rearGlassPrimary,
                rearGlassBrightColor: rearGlassBright,
                shortLabel: inputSourceManager.currentSource?.shortLabel ?? "EN",
                sourceName: inputSourceManager.currentSource?.name ?? "ABC",
                languageRotation: centerOnlyLanguageRotation,
                languageOpacity: centerOnlyLanguageOpacity,
                forceVibrantRendering: forceVibrantRendering,
                onPrevious: {
                    centerOnlySlideDirection = -1
                    pushCenter(direction: -1)
                    animateCenterOnlyLanguageChange(direction: -1) {
                        inputSourceManager.selectPrevious()
                    }
                },
                onNext: {
                    centerOnlySlideDirection = 1
                    pushCenter(direction: 1)
                    animateCenterOnlyLanguageChange(direction: 1) {
                        inputSourceManager.selectNext()
                    }
                },
                onSettings: {
                    openSettingsWindow()
                }
            )
            .id("language-\(inputSourceManager.currentSource?.name ?? "ABC")")

        case "clockCalendar":
            ZestV34CenterOnlyClockCalendarTurntable(
                accentColor: zestOrange,
                accentBrightColor: zestAmber,
                accentHighlightColor: zestGold,
                accentDeepColor: deepAmber,
                rearGlassPrimaryColor: rearGlassPrimary,
                rearGlassBrightColor: rearGlassBright,
                showsCalendar: centerOnlyClockCalendarShowsCalendar,
                faceRotation: centerOnlyClockCalendarRotation,
                faceOpacity: centerOnlyClockCalendarOpacity,
                forceVibrantRendering: forceVibrantRendering,
                onToggle: {
                    // Deliberately mirror the proven Language Turntable callback chain:
                    // direction state -> center push -> staged rotation -> midpoint swap.
                    let direction = centerOnlyClockCalendarShowsCalendar ? -1 : 1
                    centerOnlySlideDirection = CGFloat(direction)
                    pushCenter(direction: CGFloat(direction))
                    animateCenterOnlyClockCalendarChange(direction: direction) {
                        centerOnlyClockCalendarShowsCalendar.toggle()
                    }
                },
                onSettings: {
                    openSettingsWindow()
                },
                onDragChanged: { translation, ended in
                    onRuntimeDrag?(translation, ended)
                }
            )

        case "languageClock":
            ZestV35LanguageClockTurntable(
                accentColor: zestOrange,
                accentBrightColor: zestAmber,
                accentHighlightColor: zestGold,
                accentDeepColor: deepAmber,
                rearGlassPrimaryColor: rearGlassPrimary,
                rearGlassBrightColor: rearGlassBright,
                shortLabel: inputSourceManager.currentSource?.shortLabel ?? "EN",
                languageRotation: centerOnlyLanguageRotation,
                languageOpacity: centerOnlyLanguageOpacity,
                forceVibrantRendering: forceVibrantRendering,
                onRotateLanguage: {
                    centerOnlySlideDirection = 1
                    pushCenter(direction: 1)
                    animateCenterOnlyLanguageChange(direction: 1) {
                        inputSourceManager.selectNext()
                    }
                },
                onSettings: {
                    openSettingsWindow()
                },
                onDragChanged: { translation, ended in
                    onRuntimeDrag?(translation, ended)
                }
            )
            .id("languageClock-\(inputSourceManager.currentSource?.name ?? "ABC")")

        case "calendarThree":
            centerOnlyTopThreeRuntimeRing(kind: .calendar)

        case "clockThree":
            centerOnlyTopThreeRuntimeRing(kind: .clock)

        default:
            centerOnlySplitRuntimeRing
        }
    }

    private func centerOnlyTopThreeRuntimeRing(
        kind: ZestV34CenterTopDisplayKind
    ) -> some View {
        let diameter = centerRadius * 2 * 1.20

        return ZStack {
            ZestV34CenterOnlyTopThreeView(
                features: settingsManager.runtimeCenterOnlyThreeFeatures,
                featureColors: (0..<3).map { settingsManager.accentColor(at: $0) },
                displayKind: kind,
                accentColor: zestOrange,
                accentBrightColor: zestAmber,
                accentHighlightColor: zestGold,
                accentDeepColor: deepAmber,
                forceVibrantRendering: forceVibrantRendering,
                diameter: diameter,
                onFeature: { feature, index in
                    performCenterFeature(feature, count: 3, index: index)
                },
                onSettings: {
                    openSettingsWindow()
                }
            )

            ZestRuntimeBezelDragShape(innerRatio: 0.80)
                .fill(Color.clear)
                .contentShape(ZestRuntimeBezelDragShape(innerRatio: 0.80))
                .frame(width: diameter + 12, height: diameter + 12)
                .gesture(runtimePanelDragGesture)
                .zIndex(50)
        }
        .frame(width: diameter, height: diameter)
    }


    private var centerOnlySplitRuntimeRing: some View {
        let diameter = centerRadius * 2 * 1.20
        let isTwo = centerOnlyRuntimeMode == "twoFeature"
        let features = isTwo
            ? settingsManager.runtimeCenterOnlyTwoFeatures
            : settingsManager.runtimeCenterOnlyFourFeatures
        let count = isTwo ? 2 : 4
        let colors = (0..<count).map { settingsManager.accentColor(at: $0) }

        return ZStack {
            // Shared production 2/4 Split renderer. Onboarding uses this same
            // component so tutorial geometry and live in-field Zest cannot drift.
            ZestV34CenterOnlySplitView(
                features: features,
                count: count,
                featureColors: colors,
                accentColor: zestOrange,
                accentBrightColor: zestAmber,
                accentHighlightColor: zestGold,
                accentDeepColor: deepAmber,
                forceVibrantRendering: forceVibrantRendering,
                onFeature: { feature, index in
                    performCenterFeature(feature, count: count, index: index)
                },
                onSettings: {
                    openSettingsWindow()
                }
            )

            // In 2/4 Split the outer bezel is the physical grab surface. The
            // shared renderer owns the visuals; runtime alone owns panel drag.
            ZestRuntimeBezelDragShape(innerRatio: 0.78)
                .fill(Color.clear)
                .contentShape(ZestRuntimeBezelDragShape(innerRatio: 0.78))
                .frame(width: diameter + 12, height: diameter + 12)
                .gesture(runtimePanelDragGesture)
                .zIndex(50)
        }
        .frame(width: diameter, height: diameter)
        .animation(.spring(response: 0.30, dampingFraction: 0.78), value: centerOnlyRuntimeMode)
    }


    // MARK: - Center Only Language Dial

    private var centerOnlyLanguageDial: some View {
        let diameter = centerRadius * 2
        let source = inputSourceManager.currentSource

        return ZStack {
            // Language switch surface. The center gear sits above it, so clicking
            // anywhere else on the CRT face still performs the recent-language switch.
            Button {
                animateCenterOnlyLanguageChange(direction: 1) {
                    inputSourceManager.selectMostRecentPrevious()
                }
            } label: {
                Color.clear
                    .frame(width: diameter - 8, height: diameter - 8)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .focusable(false)

            // Bold language abbreviation above the raised center hub.
            Text(source?.shortLabel ?? "EN")
                .font(.system(size: 16.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.86))
                .offset(y: -25)
                .rotationEffect(.degrees(centerOnlyLanguageRotation))
                .opacity(centerOnlyLanguageOpacity)
                .allowsHitTesting(false)

            // Full language name follows the lower arc around the hub.
            centerOnlyArcText(source?.name ?? "ABC", radius: 27)
                .rotationEffect(.degrees(centerOnlyLanguageRotation))
                .opacity(centerOnlyLanguageOpacity)
                .allowsHitTesting(false)

            // Permanent physical settings extrusion.
            centerOnlySettingsBadge
                .zIndex(20)
        }
        .frame(width: diameter, height: diameter)
    }


    private func centerOnlyArcText(_ text: String, radius: CGFloat) -> some View {
        let characters = Array(text)
        let count = max(characters.count, 1)
        let maximumSpan = min(150.0, 58.0 + Double(max(count - 1, 0)) * 11.5)
        // Lay the word counter-clockwise across the lower arc while keeping
        // the characters in normal reading order and individually upright.
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


    private func centerOnlyRuntimeLanguageBacking(
        side: Int
    ) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: side < 0 ? 15 : 5,
            bottomLeadingRadius: side < 0 ? 15 : 5,
            bottomTrailingRadius: side > 0 ? 15 : 5,
            topTrailingRadius: side > 0 ? 15 : 5
        )
        .fill(zestAmber.opacity(0.13))
        .frame(width: 43, height: 31)
        .overlay {
            UnevenRoundedRectangle(
                topLeadingRadius: side < 0 ? 15 : 5,
                bottomLeadingRadius: side < 0 ? 15 : 5,
                bottomTrailingRadius: side > 0 ? 15 : 5,
                topTrailingRadius: side > 0 ? 15 : 5
            )
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.48),
                        zestGold.opacity(0.15),
                        deepAmber.opacity(0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
        }
        .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
    }


    // Circular settings button drawn directly on the center ring surface.
    // It intentionally uses the same glossy/rim language as the ring itself.
    private var centerOnlySettingsBadge: some View {
        let buttonSize: CGFloat = 29

        return Button {
            openSettingsWindow()
        } label: {
            ZStack {
                // Lower lip/shadow makes this read as a physical extrusion from the CRT.
                Circle()
                    .fill(deepAmber.opacity(0.18))
                    .frame(width: buttonSize + 3, height: buttonSize + 3)
                    .offset(y: 1.8)

                Circle()
                    .fill(zestAmber.opacity(0.060))
                    .frame(width: buttonSize, height: buttonSize)

                Color.clear
                    .frame(width: buttonSize, height: buttonSize)
                    .glassEffect(
                        .regular.tint(zestOrange.opacity(0.23)).interactive(),
                        in: Circle()
                    )

                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.20), location: 0),
                                .init(color: zestGold.opacity(0.10), location: 0.38),
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
                    .frame(width: 18, height: 18, alignment: .center)
                    .rotationEffect(.degrees(runtimeSettingsGearHover ? 180 : 0), anchor: .center)
            }
            .overlay {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.82), Color.white.opacity(0.28), zestGold.opacity(0.18), deepAmber.opacity(0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.85
                    )
            }
            .shadow(color: .black.opacity(0.18), radius: 3.5, y: 2.4)
            .shadow(color: zestOrange.opacity(0.09), radius: 3, y: 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 38, height: 38)
        .contentShape(Circle())
        .focusable(false)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.58)) {
                runtimeSettingsGearHover = hovering
            }
        }
    }


    private var centerOnlyLanguageControls: some View {
        let diameter = centerRadius * 2

        return Button {
            centerOnlySlideDirection = 1
            withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                inputSourceManager.selectMostRecentPrevious()
            }
        } label: {
            VStack(spacing: 1) {
                Text(
                    inputSourceManager
                        .currentSource?
                        .shortLabel ?? "EN"
                )
                .font(
                    .system(
                        size: 17,
                        weight: .bold,
                        design: .rounded
                    )
                )

                Text(
                    inputSourceManager
                        .currentSource?
                        .name ?? "ABC"
                )
                .font(.system(size: 7.2, weight: .semibold))
                .lineLimit(1)
            }
            .frame(width: diameter - 10, height: diameter - 10)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .foregroundStyle(Color.primary.opacity(0.84))
    }


    private func centerOnlyRuntimeLanguageWing(
        systemImage: String,
        direction: Int
    ) -> some View {
        Button {
            centerOnlySlideDirection = CGFloat(direction)
            pushCenter(direction: CGFloat(direction))

            animateCenterOnlyLanguageChange(direction: direction) {
                if direction < 0 {
                    inputSourceManager.selectPrevious()
                } else {
                    inputSourceManager.selectNext()
                }
            }
        } label: {
            ZStack {
                // 48 x 42 is the hit target; the physical tab is 40 x 29.
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
                                .regular
                                    .tint(zestOrange.opacity(0.24))
                                    .interactive(),
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
                                    zestGold.opacity(0.20),
                                    deepAmber.opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .zIndex(-1)
    }


    private func syncCenterOnlyRuntimeSelection() {
        // Runtime is now driven directly by the saved Center Only mode.
        centerOnlySelectionIndex = 0
    }


    private func centerOnlyRuntimeFeatureIcon(_ feature: ZestFeature) -> String {
        switch feature {
        case .size: return "textformat.size"
        case .font: return "bold.italic.underline"
        default: return feature.systemImage
        }
    }

    @ViewBuilder
    private func configuredCenterRuntimeIcon(
        _ feature: ZestFeature,
        count: Int,
        index: Int,
        size: CGFloat
    ) -> some View {
        let key = settingsManager.centerActionKey(count: count, index: index)

        if feature == .openShortcut || feature == .runShortcut || feature == .url {
            ZestConfiguredActionIcon(
                feature: feature,
                applicationTarget: settingsManager.centerApplicationTargets[key],
                urlTarget: ZestURLTargetStore.shared.target(centerKey: key),
                size: size
            )
        } else {
            Image(systemName: centerOnlyRuntimeFeatureIcon(feature))
                .font(.system(size: size * 0.82, weight: .semibold))
                .frame(width: size, height: size)
        }
    }

    private func centerOnlyRuntimeFeatureDisk(features: [ZestFeature], count: Int, diameter: CGFloat) -> some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let feature = features[index]
                let tileAccent = settingsManager.accentColor(at: index)
                let radius = diameter * 0.32
                let angle: Double = count == 2 ? (index == 0 ? -90 : 90) : [-90, 0, 90, 180][index]
                let radians = angle * Double.pi / 180

                let isHovered = hoveredCenterFeatureIndex == index
                Button { performCenterFeature(feature, count: count, index: index) } label: {
                    ZStack {
                        ZestCenterRuntimeSectorShape(index: index, count: count)
                            .fill(tileAccent.opacity(feature == .empty ? 0.018 : (forceVibrantRendering ? (isHovered ? 0.78 : 0.70) : (isHovered ? 0.145 : 0.085))))
                            .glassEffect(
                                .regular.tint(tileAccent.opacity(feature == .empty ? 0.04 : (forceVibrantRendering ? 0.60 : 0.20))).interactive(),
                                in: ZestCenterRuntimeSectorShape(index: index, count: count)
                            )
                            .overlay {
                                ZestCenterRuntimeSectorShape(index: index, count: count)
                                    .stroke(Color.white.opacity(feature == .empty ? 0.12 : (isHovered ? 0.48 : 0.24)), lineWidth: isHovered ? 0.95 : 0.65)
                            }
                        if feature != .empty {
                            configuredCenterRuntimeIcon(
                                feature,
                                count: count,
                                index: index,
                                size: count == 2 ? 20 : 17
                            )
                                .foregroundStyle(Color.primary.opacity(isHovered ? 0.98 : 0.82))
                                .scaleEffect(isHovered ? 1.10 : 1.0)
                                .offset(x: cos(radians) * radius, y: sin(radians) * radius)
                        }
                    }
                    .frame(width: diameter, height: diameter)
                    .contentShape(ZestCenterRuntimeSectorShape(index: index, count: count))
                    .shadow(color: tileAccent.opacity(isHovered ? 0.15 : 0), radius: isHovered ? 6 : 0, y: 2)
                    .scaleEffect(isHovered ? 1.012 : 1.0)
                    .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isHovered)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(feature == .empty)
            }
            centerOnlySettingsBadge
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let dx = location.x - diameter / 2
                let dy = location.y - diameter / 2
                let radius = hypot(dx, dy)
                // Keep the central Settings gear on its own rotation hover.
                guard radius > diameter * 0.22 else {
                    hoveredCenterFeatureIndex = nil
                    return
                }
                var degrees = atan2(dy, dx) * 180 / .pi
                if degrees < 0 { degrees += 360 }
                let index: Int
                if count == 2 {
                    index = (degrees >= 180 && degrees < 360) ? 0 : 1
                } else {
                    // Sector centers are top, right, bottom, left.
                    index = Int(((degrees + 45).truncatingRemainder(dividingBy: 360)) / 90)
                    // atan2 screen coordinates: right=0, bottom=90, left=180, top=270
                    let mapping = [1, 2, 3, 0]
                    let mapped = mapping[index]
                    hoveredCenterFeatureIndex = features[mapped] == .empty ? nil : mapped
                    return
                }
                hoveredCenterFeatureIndex = features[index] == .empty ? nil : index
            case .ended:
                hoveredCenterFeatureIndex = nil
            }
        }
        .clipShape(Circle())
    }

    private func performCenterFeature(_ feature: ZestFeature, count: Int, index: Int) {
        menuBarPopupAnchorScreen = nil
        activeCenterFeatureCount = count
        activeCenterFeatureIndex = index
        switch feature {
        case .size:
            let w = sizePanelPresented; closeAllFeaturePanels(); withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { sizePanelPresented = !w }
        case .font:
            let w = fontPanelPresented; closeAllFeaturePanels(); withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { fontPanelPresented = !w }
        case .clipboard:
            let w = clipboardPanelPresented; closeAllFeaturePanels(); withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { clipboardPanelPresented = !w }
        case .emoji:
            let w = emojiPanelPresented; closeAllFeaturePanels(); withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { emojiPanelPresented = !w }
        case .symbols:
            let w = symbolPanelPresented; closeAllFeaturePanels(); withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { symbolPanelPresented = !w }
        case .calendar:
            let w = calendarPanelPresented; closeAllFeaturePanels(); withAnimation { calendarPanelPresented = !w }
        case .today:
            let w = todayPanelPresented; closeAllFeaturePanels(); withAnimation { todayPanelPresented = !w }
        case .battery:
            let w = batteryPanelPresented; closeAllFeaturePanels(); withAnimation { batteryPanelPresented = !w }
        case .layoutFix:
            let w = layoutFixPanelPresented; closeAllFeaturePanels(); withAnimation { layoutFixPanelPresented = !w }
        case .rapidSymbols:
            closeAllFeaturePanels(); ZestRapidSymbolEngine.shared.arm()
        case .settings:
            openSettingsWindow()
        case .openShortcut, .runShortcut, .url:
            if settingsManager.isCenterConfigured(feature, count: count, index: index) {
                _ = settingsManager.performCenterConfiguredAction(feature, count: count, index: index)
            } else {
                openSettingsWindow()
            }
        case .empty:
            break
        }
    }

    // MARK: - Center Control

    private var centerControl: some View {
        let diameter = centerRadius * 2
        let source = inputSourceManager.currentSource

        return ZStack {
            // Main glossy turntable face. The outer centerRing remains the
            // physical rim that nests this control into the Orange Slice.
            Circle()
                .fill((forceVibrantRendering ? zestOrange : zestAmber).opacity(forceVibrantRendering ? 0.70 : 0.050))
                .frame(width: diameter, height: diameter)
                .offset(y: 1.2)

            Color.clear
                .frame(width: diameter, height: diameter)
                .glassEffect(
                    .regular.tint(zestOrange.opacity(0.24)),
                    in: Circle()
                )

            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.16), location: 0),
                            .init(color: zestGold.opacity(0.09), location: 0.30),
                            .init(color: Color.clear, location: 0.72)
                        ],
                        center: UnitPoint(x: 0.28, y: 0.16),
                        startRadius: 0,
                        endRadius: 65
                    )
                )
                .frame(width: diameter, height: diameter)
                .allowsHitTesting(false)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.92),
                            Color.white.opacity(0.34),
                            zestGold.opacity(0.16),
                            zestOrange.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
                .frame(width: diameter, height: diameter)
                .allowsHitTesting(false)

            // The language itself turns exactly like the compact Saturn dial.
            ZStack {
                Text(source?.shortLabel ?? "EN")
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.86))
                    .offset(y: -22)

                // Deliberately narrower than before so long source names can
                // never run underneath the circular chevron controls.
                Text(source?.name ?? "ABC")
                    .font(.system(size: 5.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: 31)
                    .offset(y: 23)
            }
            .rotationEffect(.degrees(mainSliceLanguageRotation))
            .opacity(mainSliceLanguageOpacity)
            .allowsHitTesting(false)

            mainSliceLanguageChevron(systemImage: "chevron.left", direction: -1)
                .offset(x: -27)

            mainSliceLanguageChevron(systemImage: "chevron.right", direction: 1)
                .offset(x: 27)

            // Raised center hub = the physical grab handle for the large slice.
            // It intentionally performs no language action and has no click
            // compression animation: drag it to reposition Zest.
            mainSliceDragHub
                .zIndex(30)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: Color.black.opacity(0.15), radius: 4, y: 3)
        .shadow(color: zestOrange.opacity(0.06), radius: 5, y: 1)
    }


    private func mainSliceLanguageChevron(
        systemImage: String,
        direction: Int
    ) -> some View {
        let backingSize: CGFloat = 26
        let buttonSize: CGFloat = 22

        return Button {
            animateMainSliceLanguageChange(direction: direction) {
                if direction < 0 {
                    inputSourceManager.selectPrevious()
                } else {
                    inputSourceManager.selectNext()
                }
            }
        } label: {
            ZStack {
                // Same little circular support-glass idea used behind the
                // Triple Square settings gear.
                Circle()
                    .fill(rearGlassBright.opacity(0.11))
                    .frame(width: backingSize, height: backingSize)
                    .glassEffect(
                        .regular.tint(rearGlassPrimary.opacity(0.12)),
                        in: Circle()
                    )
                    .overlay {
                        Circle().stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.62),
                                    rearGlassHighlight.opacity(0.18),
                                    rearGlassDeep.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.7
                        )
                    }

                Circle()
                    .fill(zestAmber.opacity(0.055))
                    .frame(width: buttonSize, height: buttonSize)

                Color.clear
                    .frame(width: buttonSize, height: buttonSize)
                    .glassEffect(
                        .regular.tint(zestOrange.opacity(0.20)).interactive(),
                        in: Circle()
                    )

                Image(systemName: systemImage)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.82))
            }
            .frame(width: backingSize, height: backingSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }


    private var mainSliceDragHub: some View {
        let backingSize: CGFloat = 31
        let hubSize: CGFloat = 27

        return ZStack {
            Circle()
                .fill(rearGlassBright.opacity(0.12))
                .frame(width: backingSize, height: backingSize)
                .glassEffect(
                    .regular.tint(rearGlassPrimary.opacity(0.13)),
                    in: Circle()
                )
                .overlay {
                    Circle().stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.72),
                                rearGlassHighlight.opacity(0.18),
                                rearGlassDeep.opacity(0.17)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
                }
                .shadow(color: .black.opacity(0.12), radius: 2.5, y: 1.5)

            Circle()
                .fill(zestAmber.opacity(0.060))
                .frame(width: hubSize, height: hubSize)

            Color.clear
                .frame(width: hubSize, height: hubSize)
                .glassEffect(
                    .regular.tint(zestOrange.opacity(0.23)).interactive(),
                    in: Circle()
                )

            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.22), location: 0),
                            .init(color: zestGold.opacity(0.09), location: 0.42),
                            .init(color: Color.clear, location: 0.84)
                        ],
                        center: UnitPoint(x: 0.30, y: 0.18),
                        startRadius: 0,
                        endRadius: hubSize
                    )
                )
                .frame(width: hubSize - 2, height: hubSize - 2)
                .allowsHitTesting(false)

            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 10.2, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.76))
                .allowsHitTesting(false)
        }
        .frame(width: backingSize, height: backingSize)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if let onRuntimeDrag {
                        onRuntimeDrag(value.translation, false)
                    } else {
                        var transaction = Transaction()
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            mainSliceDragTranslation = value.translation
                        }
                    }
                }
                .onEnded { value in
                    if let onRuntimeDrag {
                        onRuntimeDrag(value.translation, true)
                    } else {
                        var transaction = Transaction()
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            mainSliceCommittedOffset.width += value.translation.width
                            mainSliceCommittedOffset.height += value.translation.height
                            mainSliceDragTranslation = .zero
                        }
                    }
                }
        )
    }


    private func animateMainSliceLanguageChange(
        direction: Int,
        change: @escaping () -> Void
    ) {
        let clockwise = direction > 0
        let exitAngle = clockwise ? 54.0 : -54.0
        let entryAngle = -exitAngle

        withAnimation(.easeIn(duration: 0.10)) {
            mainSliceLanguageRotation = exitAngle
            mainSliceLanguageOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            change()
            mainSliceLanguageRotation = entryAngle

            withAnimation(.easeOut(duration: 0.15)) {
                mainSliceLanguageRotation = 0
                mainSliceLanguageOpacity = 1
            }
        }
    }


    // MARK: - Center Only Language Rotation

    private func animateCenterOnlyLanguageChange(
        direction: Int,
        change: @escaping () -> Void
    ) {
        let clockwise = direction > 0
        let exitAngle = clockwise ? 54.0 : -54.0
        let entryAngle = -exitAngle

        withAnimation(.easeIn(duration: 0.10)) {
            centerOnlyLanguageRotation = exitAngle
            centerOnlyLanguageOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            change()
            centerOnlyLanguageRotation = entryAngle

            withAnimation(.easeOut(duration: 0.15)) {
                centerOnlyLanguageRotation = 0
                centerOnlyLanguageOpacity = 1
            }
        }
    }


    // Clock / Calendar uses the exact same staged turntable workflow as Language:
    // old face rotates/fades out, the data source swaps only at the midpoint,
    // then the incoming face rotates/fades back to rest.
    private func animateCenterOnlyClockCalendarChange(
        direction: Int,
        change: @escaping () -> Void
    ) {
        let clockwise = direction > 0
        let exitAngle = clockwise ? 54.0 : -54.0
        let entryAngle = -exitAngle

        withAnimation(.easeIn(duration: 0.10)) {
            centerOnlyClockCalendarRotation = exitAngle
            centerOnlyClockCalendarOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            change()
            centerOnlyClockCalendarRotation = entryAngle

            withAnimation(.easeOut(duration: 0.15)) {
                centerOnlyClockCalendarRotation = 0
                centerOnlyClockCalendarOpacity = 1
            }
        }
    }


    // MARK: - Center Push Animation
    // Retained only for the compact Center Only / 2x4 turntable.
    private func pushCenter(direction: CGFloat) {
        withAnimation(.spring(response: 0.11, dampingFraction: 0.68)) {
            centerPush = direction
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.40)) {
                centerPush = 0
            }
        }
    }

    // MARK: - Tile Label

    private func tileLabel(_ control: ZestControl) -> some View {
        let labelRadius = (innerTileRadius + outerTileRadius) / 2
        let radians = control.centerAngle * .pi / 180
        let x = cos(radians) * labelRadius
        let y = sin(radians) * labelRadius

        return Group {

            // SIZE
            //
            // Main value = number only.
            // Subtitle = Size.
            // If Pages does not expose a size, show —.

            if control.feature == .size {

                VStack(spacing: 1.5) {

                    Text(sizeTileValue)
                        .font(
                            .system(
                                size: 17,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .lineLimit(1)

                    Text("Size")
                        .font(
                            .system(
                                size: 8,
                                weight: .medium
                            )
                        )
                }

            // FONT
            //
            // Main value = A rendered in the currently
            // selected Pages font family.
            // Subtitle = Font.
            // If Pages does not expose a font, show —.

            } else if control.feature == .font {

                VStack(spacing: 1.5) {

                    if let family = currentFontFamily {

                        Text("A")
                            .font(
                                .custom(
                                    family,
                                    size: 21
                                )
                            )
                            .frame(height: 22)

                    } else {

                        Text("—")
                            .font(
                                .system(
                                    size: 17,
                                    weight: .semibold,
                                    design: .rounded
                                )
                            )
                            .frame(height: 22)
                    }

                    Text("Font")
                        .font(
                            .system(
                                size: 8,
                                weight: .medium
                            )
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .frame(maxWidth: 58)
                }

            // TODAY / NOKIA CLOCK TILE

            } else if control.feature == .today {

                ZestNokiaTodayWedgeFace(
                    startAngle: control.startAngle,
                    endAngle: control.endAngle,
                    innerRadius: innerTileRadius,
                    outerRadius: outerTileRadius,
                    gapInset: tileGapInset,
                    startGapInset: control.number == 2 ? endGapInset : nil,
                    endGapInset: control.number == 7 ? endGapInset : nil,
                    canvasSize: size,
                    accentColor: settingsManager.accentColor(at: control.number - 2),
                    accentHighlightColor: zestGold,
                    accentDeepColor: deepAmber
                )
                .frame(width: size, height: size)

            // ALL OTHER TILES

            } else {

                VStack(spacing: 1.5) {

                    if let slot = ZestSliceSlot(rawValue: control.number),
                       control.feature == .openShortcut || control.feature == .runShortcut || control.feature == .url {
                        ZestConfiguredActionIcon(
                            feature: control.feature,
                            applicationTarget: settingsManager.applicationTargets[slot],
                            urlTarget: ZestURLTargetStore.shared.target(for: slot.rawValue),
                            size: 17
                        )
                    } else {
                        Image(systemName: control.symbol)
                            .font(.system(size: 13, weight: .semibold))
                    }

                    Text(control.title)
                        .font(
                            .system(
                                size: 8,
                                weight: .medium
                            )
                        )
                }
            }
        }
        .foregroundStyle(Color.primary.opacity(0.84))
        .offset(
            x: control.feature == .today ? 0 : x,
            y: control.feature == .today ? 0 : y
        )
    }

    // MARK: - Size Tile Value

    private var sizeTileValue: String {

        guard
            let fontSize = textContextManager.fontSize
        else {
            return "—"
        }

        return String(
            Int(
                fontSize.rounded()
            )
        )
    }

    // MARK: - Current Font Family

    private var currentFontFamily: String? {

        guard
            let family = textContextManager.fontFamily?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
            !family.isEmpty
        else {
            return nil
        }

        return family
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

        ContentView(
            textContextManager: TextContextManager(),
            fontLibraryManager: FontLibraryManager(),
            settingsManager: ZestSettingsManager()
        )
    }
    .frame(width: 700, height: 440)
}


extension Notification.Name {
    static let zestSaturnPrevious = Notification.Name("zest.saturn.previous")
    static let zestSaturnNext = Notification.Name("zest.saturn.next")
    static let zestRuntimeCanvasScreenFrameDidChange = Notification.Name("zest.runtime.canvas.screenFrameDidChange")
}
