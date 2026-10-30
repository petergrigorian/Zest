//
//  ZestTodayPanel.swift
//  Zest
//
//  0.1.2 — shared Calendar-backed day agenda
//

import SwiftUI

struct ZestTodayPanel: View {
    @ObservedObject private var calendar = ZestCalendarService.shared
    let accentColor: Color

    @State private var selectedDate = Date()
    @State private var showingDateJump = false
    @State private var jumpDate = Date()
    @State private var datePlateFlutter = false
    @State private var datePlateFlutterAngle: Double = 0
    @AppStorage("zest.today.completedEventIDs")
    private var completedEventStorage = ""

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 13) {
                dayHeader

                Divider().opacity(0.28)

                dayEvents

                dayNavigation
            }
            .padding(16)

            if showingDateJump {
                ZestDateJumpOverlay(
                    initialDate: selectedDate,
                    accentColor: accentColor,
                    onCancel: {
                        withAnimation(.spring(response: 0.20, dampingFraction: 0.88)) {
                            showingDateJump = false
                        }
                    },
                    onJump: { date in
                        jump(to: date)
                        withAnimation(.spring(response: 0.20, dampingFraction: 0.88)) {
                            showingDateJump = false
                        }
                    }
                )
            }
        }
        .frame(width: 390, alignment: .top)
        .frame(minHeight: 350, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .zestPopupSurface(accentColor: accentColor, cornerRadius: 22)
        .onAppear {
            calendar.refreshAuthorizationStatus()
            calendar.refresh()
            calendar.refreshMonth(containing: selectedDate)
        }
    }

    private var dayHeader: some View {
        HStack(spacing: 12) {
            Button {
                flutterDatePlate()
            } label: {
                ZStack(alignment: .top) {
                    // A paper stack, not a sliced curtain. Every sheet is one
                    // continuous opaque-white shape whose free edge flexes while
                    // the red binding and metal rings stay fixed.
                    paperCalendarPage(
                        curl: CGFloat(datePlateFlutterAngle * 0.42),
                        xOffset: -1.4,
                        yOffset: 3.6,
                        showsDate: false
                    )

                    paperCalendarPage(
                        curl: CGFloat(datePlateFlutterAngle * 0.68),
                        xOffset: 1.0,
                        yOffset: 2.0,
                        showsDate: false
                    )

                    paperCalendarPage(
                        curl: CGFloat(datePlateFlutterAngle),
                        xOffset: 0,
                        yOffset: 0,
                        showsDate: true
                    )

                    VStack(spacing: -2) {
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.red.opacity(1.0),
                                        Color.red.opacity(0.91),
                                        Color.red.opacity(0.80)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 47, height: 9)
                            .overlay(alignment: .top) {
                                Capsule()
                                    .fill(Color.white.opacity(0.34))
                                    .frame(width: 40, height: 1)
                                    .offset(y: 1)
                            }
                            .shadow(color: Color.black.opacity(0.22), radius: 1.4, y: 1)

                        HStack(spacing: 11) {
                            metallicCalendarRing
                            metallicCalendarRing
                        }
                    }
                    .offset(y: -8.2)
                }
                .frame(width: 60, height: 60)
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Flutter calendar")

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(selectedDate.formatted(.dateTime.year().month(.wide).day()))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(context.date.formatted(.dateTime.hour().minute().second()))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func paperCalendarPage(
        curl: CGFloat,
        xOffset: CGFloat,
        yOffset: CGFloat,
        showsDate: Bool
    ) -> some View {
        let shape = ZestFlutterPaperShape(curl: curl)

        return ZStack {
            shape
                .fill(Color.white)

            if showsDate {
                VStack(spacing: -1) {
                    Text(selectedDate.formatted(.dateTime.day()))
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.90))
                        .shadow(color: Color.white.opacity(0.95), radius: 0.5, y: -0.6)
                        .shadow(color: Color.black.opacity(0.14), radius: 0.7, y: 0.7)

                    Text(selectedDate.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .font(.system(size: 8.5, weight: .black, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.78))
                        .shadow(color: Color.white.opacity(0.94), radius: 0.45, y: -0.5)
                        .shadow(color: Color.black.opacity(0.12), radius: 0.6, y: 0.6)
                }
                .offset(y: -abs(curl) * 0.28)
            }

            shape
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color.gray.opacity(0.24),
                            Color.white.opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .frame(width: 51, height: 51)
        .rotation3DEffect(
            .degrees(Double(curl) * 2.15),
            axis: (x: 1, y: 0, z: 0),
            anchor: .top,
            perspective: 0.46
        )
        .offset(
            x: xOffset,
            y: yOffset - abs(curl) * 0.85
        )
        .shadow(
            color: Color.black.opacity(showsDate ? 0.17 : 0.08),
            radius: showsDate ? 5 : 3,
            y: showsDate ? 3 : 2
        )
    }

    private var metallicCalendarRing: some View {
        ZStack {
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(1.0),
                            Color.gray.opacity(0.92),
                            Color.white.opacity(0.76),
                            Color.black.opacity(0.52)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.8
                )
                .frame(width: 6.4, height: 12.5)

            Capsule()
                .stroke(Color.black.opacity(0.20), lineWidth: 0.55)
                .frame(width: 3.25, height: 8.8)
        }
        .shadow(color: Color.white.opacity(0.52), radius: 0.8, x: -0.4, y: -0.6)
        .shadow(color: Color.black.opacity(0.34), radius: 1.0, x: 0.5, y: 0.9)
    }

    @ViewBuilder
    private var dayEvents: some View {
        if !calendar.isConnected {
            VStack(spacing: 9) {
                Image(systemName: "calendar")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(accentColor)
                Text("No connected calendars")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text("Today automatically uses the Calendar tile setup. Connect Apple Calendar from Settings to show events here.")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 185)
        } else if eventsForSelectedDate.isEmpty {
            VStack(spacing: 9) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(accentColor)
                Text("Nothing scheduled")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text("There are no events in your selected calendars for this date.")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 185)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(eventsForSelectedDate) { event in
                        eventCard(event)
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 285)
        }
    }

    private func eventCard(_ event: ZestCalendarEvent) -> some View {
        let completed = completedEventIDs.contains(event.id)

        return HStack(alignment: .center, spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                if event.isAllDay {
                    Text("ALL")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                } else {
                    Text(event.startDate.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                    Text(event.endDate.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(accentColor)
            .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .strikethrough(completed, color: .secondary)
                    .lineLimit(2)
                Text(event.calendarTitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            Button {
                setCompleted(!completed, for: event.id)
            } label: {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(completed ? accentColor : Color.secondary.opacity(0.72))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(completed ? "Mark event incomplete" : "Mark event complete")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(completed ? 0.025 : 0.05))
        }
        .opacity(completed ? 0.62 : 1)
        .animation(.easeInOut(duration: 0.16), value: completed)
    }

    private var dayNavigation: some View {
        HStack(spacing: 8) {
            navigationCircle(systemImage: "chevron.backward", help: "Yesterday") {
                moveDay(by: -1)
            }

            Button {
                jumpToActualToday()
            } label: {
                ZStack {
                    Capsule()
                        .fill(Color.primary.opacity(0.045))
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.75)

                    Text("Today")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 29)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Jump to today")

            navigationCircle(systemImage: "chevron.right", help: "Tomorrow") {
                moveDay(by: 1)
            }

            navigationCircle(systemImage: "pointer.arrow.motionlines", help: "Jump to date") {
                jumpDate = selectedDate
                withAnimation(.spring(response: 0.20, dampingFraction: 0.88)) {
                    showingDateJump = true
                }
            }
        }
    }

    private func navigationCircle(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 29, height: 29)
                .background {
                    Circle().fill(Color.primary.opacity(0.045))
                }
                .overlay {
                    Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.75)
                }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }

    private var eventsForSelectedDate: [ZestCalendarEvent] {
        calendar.events(on: selectedDate)
    }

    private var completedEventIDs: Set<String> {
        Set(completedEventStorage.split(separator: "\n").map(String.init))
    }

    private func setCompleted(_ completed: Bool, for id: String) {
        var values = completedEventIDs
        if completed { values.insert(id) } else { values.remove(id) }
        completedEventStorage = values.sorted().joined(separator: "\n")
    }

    private func flutterDatePlate() {
        guard !datePlateFlutter else { return }
        datePlateFlutter = true

        // Smooth damped paper flutter: enough movement to read as flexible paper,
        // without swinging the whole square like a rigid card.
        withAnimation(.easeOut(duration: 0.10)) {
            datePlateFlutterAngle = -0.86
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.easeInOut(duration: 0.12)) {
                datePlateFlutterAngle = 0.58
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.easeInOut(duration: 0.11)) {
                datePlateFlutterAngle = -0.34
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.33) {
            withAnimation(.easeInOut(duration: 0.10)) {
                datePlateFlutterAngle = 0.18
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.43) {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                datePlateFlutterAngle = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) {
            datePlateFlutter = false
        }
    }

    private func jumpToActualToday() {
        let today = Calendar.current.startOfDay(for: Date())
        jump(to: today)
    }

    private func moveDay(by value: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: value, to: selectedDate) else { return }
        jump(to: next)
    }

    private func jump(to date: Date) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            selectedDate = date
            jumpDate = date
        }
        calendar.refreshMonth(containing: date)
    }
}

/// Today has no independent account configuration. It always inherits Calendar.
/// If Calendar is already set up, Today is instantly configured. If it is not,
/// this view offers the shared Calendar setup without creating a second preference set.
struct ZestTodaySetupView: View {
    @ObservedObject private var calendar = ZestCalendarService.shared
    let accentColor: Color
    @Binding var calendarSetupStep: Int
    let onFinished: () -> Void

    var body: some View {
        Group {
            if calendar.isConnected {
                ZestCalendarSetupView(
                    accentColor: accentColor,
                    setupStep: $calendarSetupStep,
                    showsResetAction: false,
                    spacious: true,
                    onFinished: onFinished
                )
                .onAppear {
                    if calendarSetupStep != 2 { calendarSetupStep = 2 }
                }
            } else if calendar.setupCompleted {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Today follows Calendar", systemImage: "calendar.day.timeline.left")
                        .font(.system(size: 17, weight: .bold, design: .rounded))

                    Text("Calendar is currently using local mode. Today is configured automatically and will follow the selected date, but it will not import events until Apple Calendar is connected.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Spacer()
                        Button("Done") { onFinished() }
                            .buttonStyle(ZestPrimaryActionButtonStyle(accent: accentColor))
                    }
                }
                .frame(maxWidth: 760, alignment: .topLeading)
            } else {
                ZestCalendarSetupView(
                    accentColor: accentColor,
                    setupStep: $calendarSetupStep,
                    showsResetAction: false,
                    spacious: true,
                    onFinished: onFinished
                )
            }
        }
    }
}

private struct ZestFlutterPaperShape: Shape {
    var curl: CGFloat

    var animatableData: CGFloat {
        get { curl }
        set { curl = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let c = max(-1.0, min(1.0, curl))
        let radius: CGFloat = 8
        let lowerLift = rect.height * 0.055 * abs(c)
        let wave = rect.height * 0.045 * c

        var path = Path()

        // Keep the silhouette square/rounded like the original date plate.
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius - lowerLift))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY - lowerLift),
            control: CGPoint(x: rect.maxX, y: rect.maxY - lowerLift)
        )

        // Only the free lower edge flexes. The side walls stay almost straight,
        // which preserves the familiar square paper shape at every frame.
        path.addCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.maxY + lowerLift * 0.10),
            control1: CGPoint(
                x: rect.maxX - rect.width * 0.30,
                y: rect.maxY - lowerLift + wave
            ),
            control2: CGPoint(
                x: rect.minX + rect.width * 0.30,
                y: rect.maxY + lowerLift * 0.10 - wave
            )
        )

        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}

