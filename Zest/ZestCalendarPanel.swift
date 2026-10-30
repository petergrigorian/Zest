//
//  ZestCalendarPanel.swift
//  Zest
//

import SwiftUI
import EventKit

struct ZestCalendarPanel: View {
    @ObservedObject private var calendar = ZestCalendarService.shared
    let accentColor: Color
    var onOpenSettings: (() -> Void)? = nil

    @State private var showingSetup = false
    @State private var setupStep = 1
    @State private var displayedMonth = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    @State private var selectedDate = Date()
    @State private var searchQuery = ""
    @FocusState private var searchFocused: Bool
    @State private var showingDateJump = false
    @State private var jumpDate = Date()

    var body: some View {
        ZStack {
            if !calendar.setupCompleted || showingSetup {
                ZestCalendarSetupView(
                    accentColor: accentColor,
                    setupStep: $setupStep,
                    onRequestConnectedSetup: { openCalendarSetupInSettings() },
                    onFinished: {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                            showingSetup = false
                            setupStep = 1
                        }
                        calendar.refreshMonth(containing: displayedMonth)
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                calendarContent
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

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
        .frame(width: 350, height: 500, alignment: .top)
        .zestPopupSurface(accentColor: accentColor, cornerRadius: 22)
        .onAppear {
            calendar.refreshAuthorizationStatus()
            calendar.refresh()
            calendar.refreshMonth(containing: displayedMonth)
        }
    }

    private var calendarContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Calendar")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(calendar.isConnected ? "Apple Calendar connected" : "Local calendar")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    calendar.refresh()
                    calendar.refreshMonth(containing: displayedMonth)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh events")

                Button {
                    openCalendarSetupInSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Calendar setup")
            }

            monthNavigationHeader

            if calendar.isConnected {
                eventSearchField
            }

            if hasSearchText {
                searchResultsView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                weekdayHeader
                monthGrid
                selectedDayPreview
                    .transition(.opacity)
            }

            if !calendar.isConnected {
                Button {
                    openCalendarSetupInSettings()
                } label: {
                    Label("Connect Calendar", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(ZestPrimaryActionButtonStyle(accent: accentColor))
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(12)
        .animation(.spring(response: 0.22, dampingFraction: 0.88), value: hasSearchText)
    }

    private func openCalendarSetupInSettings() {
        // Account selection and Calendar permission belong in the full Settings
        // workspace. Persist a one-shot request so it survives the assistant being
        // dismissed before the Settings scene has finished opening.
        UserDefaults.standard.set(
            ZestFeature.calendar.rawValue,
            forKey: "zest.settings.pendingBuiltInSetup"
        )
        onOpenSettings?()
    }

    private var monthNavigationHeader: some View {
        HStack(spacing: 8) {
            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .lineLimit(1)

            Spacer()

            monthControlButton(
                systemImage: "chevron.backward",
                help: "Previous month"
            ) {
                changeMonth(by: -1)
            }

            monthControlButton(
                systemImage: "circle.circle.fill",
                help: "Current month"
            ) {
                goToToday()
            }

            monthControlButton(
                systemImage: "chevron.right",
                help: "Next month"
            ) {
                changeMonth(by: 1)
            }

            monthControlButton(
                systemImage: "pointer.arrow.motionlines",
                help: "Jump to date"
            ) {
                jumpDate = selectedDate
                withAnimation(.spring(response: 0.20, dampingFraction: 0.88)) {
                    showingDateJump = true
                }
            }
        }
    }

    private func monthControlButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 27, height: 27)
                .background {
                    Circle()
                        .fill(Color.primary.opacity(0.045))
                }
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.75)
                }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }

    private var eventSearchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.72))

            TextField("Events", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .focused($searchFocused)
                .simultaneousGesture(TapGesture().onEnded {
                    NotificationCenter.default.post(
                        name: .zestRuntimeKeyboardFocusRequested,
                        object: nil
                    )
                    DispatchQueue.main.async { searchFocused = true }
                })

            Spacer(minLength: 2)

            if hasSearchText {
                Button {
                    searchQuery = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.secondary.opacity(0.68))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Clear event search")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 29)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    searchFocused
                        ? accentColor.opacity(0.55)
                        : Color.white.opacity(0.22),
                    lineWidth: searchFocused ? 1.0 : 0.75
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture {
            NotificationCenter.default.post(
                name: .zestRuntimeKeyboardFocusRequested,
                object: nil
            )
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private var hasSearchText: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var matchingEvents: [ZestCalendarEvent] {
        calendar.searchEvents(
            matching: searchQuery,
            around: displayedMonth
        )
    }

    private var searchResultsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Event Search")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                Spacer()
                Text("\(matchingEvents.count) result\(matchingEvents.count == 1 ? "" : "s")")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if matchingEvents.isEmpty {
                ContentUnavailableView(
                    "No Events Found",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Try another event name or calendar.")
                )
                .frame(height: 190)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(matchingEvents) { event in
                            Button {
                                searchQuery = ""
                                searchFocused = false
                                jump(to: event.startDate)
                            } label: {
                                searchEventRow(event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 285)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.040))
        }
    }

    private func searchEventRow(_ event: ZestCalendarEvent) -> some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.startDate.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)
                Text(event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(event.calendarTitle)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 9)
        .frame(height: 44)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(
                Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()),
                id: \.offset
            ) { item in
                Text(item.element)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let days = gridDates(for: displayedMonth)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7),
            spacing: 2
        ) {
            ForEach(days, id: \.self) { date in
                dayCell(date)
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let system = Calendar.current
        let inMonth = system.isDate(date, equalTo: displayedMonth, toGranularity: .month)
        let isToday = system.isDateInToday(date)
        let isSelected = system.isDate(date, inSameDayAs: selectedDate)
        let events = calendar.events(on: date)

        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedDate = date
            }
        } label: {
            VStack(spacing: 1.5) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(accentColor.opacity(isToday ? 0.88 : 0.20))
                            .frame(width: 24, height: 24)
                    }

                    if isToday && !isSelected {
                        Circle()
                            .stroke(accentColor, lineWidth: 1.6)
                            .frame(width: 24, height: 24)
                    }

                    Text("\(system.component(.day, from: date))")
                        .font(.system(size: 12, weight: isToday ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(
                            isSelected && isToday
                                ? Color.white
                                : (inMonth ? Color.primary : Color.secondary.opacity(0.42))
                        )
                }
                .frame(height: 27)

                HStack(spacing: 2) {
                    ForEach(0..<min(events.count, 3), id: \.self) { _ in
                        Circle()
                            .fill(accentColor)
                            .frame(width: 3, height: 3)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var selectedDayPreview: some View {
        let events = calendar.events(on: selectedDate)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                Spacer()
                if calendar.isConnected {
                    Text(events.isEmpty ? "No events" : "\(events.count) event\(events.count == 1 ? "" : "s")")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if calendar.isConnected && !events.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(events.prefix(5)) { event in
                            eventRow(event)
                        }
                    }
                }
                .frame(maxHeight: 88)
            } else if calendar.isConnected {
                Text("Nothing scheduled for this date.")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text("Connect Apple Calendar to add event dots and previews. The month calendar works without an account.")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        }
    }

    private func eventRow(_ event: ZestCalendarEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(accentColor)
                .frame(width: 5, height: 5)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                Text(event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(event.calendarTitle)
                .font(.system(size: 8.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private func changeMonth(by value: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        jump(to: next)
    }

    private func goToToday() {
        jump(to: Date())
    }

    private func jump(to date: Date) {
        let month = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: date)
        ) ?? date

        withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
            displayedMonth = month
            selectedDate = date
            jumpDate = date
        }
        calendar.refreshMonth(containing: month)
    }

    private func gridDates(for month: Date) -> [Date] {
        let system = Calendar.current
        let monthStart = system.date(from: system.dateComponents([.year, .month], from: month)) ?? month
        let weekday = system.component(.weekday, from: monthStart)
        let mondayOffset = (weekday + 5) % 7
        let gridStart = system.date(byAdding: .day, value: -mondayOffset, to: monthStart) ?? monthStart
        return (0..<42).compactMap {
            system.date(byAdding: .day, value: $0, to: gridStart)
        }
    }
}

struct ZestCalendarSetupView: View {
    @ObservedObject private var calendar = ZestCalendarService.shared
    let accentColor: Color
    @Binding var setupStep: Int
    var showsResetAction: Bool = false
    var spacious: Bool = false
    var onRequestConnectedSetup: (() -> Void)? = nil
    let onFinished: () -> Void

    @State private var showingResetConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("Calendar Setup", systemImage: "calendar.badge.plus")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Text(stepText)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Divider().opacity(0.35)

            ZStack {
                if setupStep == 1 {
                    connectStep
                        .transition(.move(edge: .leading).combined(with: .opacity))
                } else if setupStep == 2 {
                    calendarSelectionStep
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    completionStep
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.30, dampingFraction: 0.86), value: setupStep)

            if showsResetAction && calendar.setupCompleted {
                Divider().opacity(0.35)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset Calendar Setup")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("Clears Zest's Calendar selection and setup only. Your Apple Calendar data is never changed.")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(18)
        .frame(minHeight: 265, alignment: .top)
        .onAppear {
            calendar.refreshAuthorizationStatus()
            calendar.reloadCalendars()
            if calendar.isConnected && setupStep == 1 {
                setupStep = 2
            }
        }
        .confirmationDialog(
            "Reset Calendar Setup?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Calendar Setup", role: .destructive) {
                calendar.resetConfiguration()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    setupStep = 1
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This only resets Zest's Calendar configuration. It will not remove events, accounts, or macOS Calendar permission.")
        }
    }

    private var stepText: String {
        if setupStep == 1 { return "Step 1 of 2" }
        if setupStep == 2 { return "Step 2 of 3" }
        return "Setup complete"
    }

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect your existing Calendar setup?")
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text("Zest can use calendars already configured in Apple Calendar on this Mac. Choosing No keeps the month calendar fully usable without importing events.")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 9) {
                Button("No") {
                    calendar.beginDisconnectedSetup()
                    withAnimation { setupStep = 3 }
                }
                .buttonStyle(ZestSecondaryActionButtonStyle())

                if calendar.authorizationStatus == .denied || calendar.authorizationStatus == .restricted {
                    Button {
                        calendar.openCalendarPrivacySettings()
                    } label: {
                        Label("Open Calendar Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(ZestPrimaryActionButtonStyle(accent: accentColor))
                } else {
                    Button {
                        if let onRequestConnectedSetup {
                            onRequestConnectedSetup()
                        } else {
                            Task {
                                let granted: Bool
                                if calendar.hasFullAccess {
                                    granted = true
                                } else {
                                    granted = await calendar.requestAccess()
                                }

                                if granted {
                                    calendar.reloadCalendars()
                                    withAnimation { setupStep = 2 }
                                }
                            }
                        }
                    } label: {
                        Label("Yes, Connect", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(ZestPrimaryActionButtonStyle(accent: accentColor))
                }
            }

            if let error = calendar.lastError {
                Text(error)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
    }

    private var calendarSelectionStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose calendars")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Select the accounts and calendars Zest should show in Calendar and Today.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Select All") {
                    calendar.selectAllCalendars()
                }
                .buttonStyle(.plain)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(accentColor)
            }

            if calendar.groupedCalendars.isEmpty {
                ContentUnavailableView(
                    "No Calendars Found",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Open Apple Calendar and make sure at least one calendar account is configured.")
                )
                .frame(height: 150)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(calendar.groupedCalendars.enumerated()), id: \.offset) { entry in
                            calendarAccountCard(
                                source: entry.element.source,
                                calendars: entry.element.calendars
                            )
                        }
                    }
                }
                .frame(minHeight: spacious ? 360 : 0, maxHeight: spacious ? 520 : 245)
            }

            HStack {
                Button("Back") {
                    withAnimation { setupStep = 1 }
                }
                .buttonStyle(ZestSecondaryActionButtonStyle())

                Spacer()

                Button("Continue") {
                    calendar.completeConnectedSetup()
                    withAnimation { setupStep = 3 }
                }
                .buttonStyle(ZestPrimaryActionButtonStyle(accent: accentColor))
                .disabled(calendar.selectedCalendarIDs.isEmpty)
            }
        }
    }


    private func calendarAccountCard(
        source: String,
        calendars: [ZestCalendarDescriptor]
    ) -> some View {
        let accountVisible = calendar.sourceHasVisibleCalendars(source)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(source)
                    .font(.system(size: spacious ? 12 : 10, weight: .bold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    calendar.setSource(source, enabled: !accountVisible)
                } label: {
                    Image(systemName: accountVisible ? "eye.slash" : "eye")
                        .font(.system(size: spacious ? 12 : 10.5, weight: .semibold))
                        .foregroundStyle(accountVisible ? .secondary : accentColor)
                        .frame(
                            width: spacious ? 30 : 24,
                            height: spacious ? 26 : 22
                        )
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.045))
                        }
                }
                .buttonStyle(.plain)
                .help(
                    accountVisible
                    ? "Hide all calendars from \(source)"
                    : "Show all calendars from \(source)"
                )
            }

            ForEach(calendars) { descriptor in
                Toggle(
                    isOn: calendarSelectionBinding(for: descriptor.id)
                ) {
                    Text(descriptor.title)
                        .font(
                            .system(
                                size: spacious ? 12 : 11,
                                weight: .medium
                            )
                        )
                }
                .toggleStyle(.checkbox)
                .tint(accentColor)
                .disabled(!accountVisible)
                .opacity(accountVisible ? 1 : 0.48)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    accountVisible
                    ? Color.primary.opacity(0.045)
                    : Color.black.opacity(0.18)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    accountVisible
                    ? Color.clear
                    : Color.black.opacity(0.22),
                    lineWidth: 0.8
                )
        }
        .opacity(accountVisible ? 1 : 0.72)
        .animation(.easeInOut(duration: 0.18), value: accountVisible)
    }

    private func calendarSelectionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: {
                calendar.selectedCalendarIDs.contains(id)
            },
            set: { enabled in
                calendar.setCalendar(id, enabled: enabled)
            }
        )
    }

    private var completionStep: some View {
        VStack(spacing: 13) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(accentColor)
            Text("Setup complete")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text(
                calendar.isConnected
                ? "Calendar and Today now use your selected Apple calendars."
                : "Zest Calendar is ready as a local month view. You can connect Apple Calendar later."
            )
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Button("Done") {
                onFinished()
            }
            .buttonStyle(ZestPrimaryActionButtonStyle(accent: accentColor))
        }
        .frame(maxWidth: .infinity, minHeight: 190)
    }
}
