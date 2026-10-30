//
//  ZestCalendarService.swift
//  Zest
//
//  0.1.2 — EventKit calendar configuration + shared event data
//

import Foundation
import EventKit
import Combine
import AppKit

struct ZestCalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarTitle: String
}

struct ZestCalendarDescriptor: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let sourceTitle: String
}

@MainActor
final class ZestCalendarService: ObservableObject {
    static let shared = ZestCalendarService()

    @Published private(set) var authorizationStatus: EKAuthorizationStatus =
        EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var availableCalendars: [ZestCalendarDescriptor] = []
    @Published private(set) var upcomingEvents: [ZestCalendarEvent] = []
    @Published private(set) var todayEvents: [ZestCalendarEvent] = []
    @Published private(set) var monthEvents: [ZestCalendarEvent] = []
    @Published private(set) var visibleMonth: Date = Date()
    @Published private(set) var lastError: String?

    @Published var setupCompleted: Bool {
        didSet { defaults.set(setupCompleted, forKey: Key.setupCompleted) }
    }

    @Published var usesSystemCalendars: Bool {
        didSet { defaults.set(usesSystemCalendars, forKey: Key.usesSystemCalendars) }
    }

    @Published var selectedCalendarIDs: Set<String> {
        didSet {
            defaults.set(Array(selectedCalendarIDs), forKey: Key.selectedCalendarIDs)
            refresh()
            refreshMonth(containing: visibleMonth)
        }
    }

    private enum Key {
        static let setupCompleted = "zest.calendar.setupCompleted"
        static let usesSystemCalendars = "zest.calendar.usesSystemCalendars"
        static let selectedCalendarIDs = "zest.calendar.selectedCalendarIDs"
    }

    private let store = EKEventStore()
    private let defaults = UserDefaults.standard
    private var storeObserver: NSObjectProtocol?

    private init() {
        setupCompleted = defaults.bool(forKey: Key.setupCompleted)
        usesSystemCalendars = defaults.object(forKey: Key.usesSystemCalendars) == nil
            ? false
            : defaults.bool(forKey: Key.usesSystemCalendars)
        selectedCalendarIDs = Set(defaults.stringArray(forKey: Key.selectedCalendarIDs) ?? [])
        visibleMonth = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: Date())
        ) ?? Date()

        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadCalendars()
                self?.refresh()
                if let month = self?.visibleMonth {
                    self?.refreshMonth(containing: month)
                }
            }
        }

        reloadCalendars()
        refresh()
        refreshMonth(containing: visibleMonth)
    }

    deinit {
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
        }
    }

    var hasFullAccess: Bool {
        authorizationStatus == .fullAccess
    }

    var isConnected: Bool {
        setupCompleted && usesSystemCalendars && hasFullAccess
    }

    var groupedCalendars: [(source: String, calendars: [ZestCalendarDescriptor])] {
        Dictionary(grouping: availableCalendars, by: \.sourceTitle)
            .map { key, value in
                (
                    source: key,
                    calendars: value.sorted {
                        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    }
                )
            }
            .sorted {
                $0.source.localizedCaseInsensitiveCompare($1.source) == .orderedAscending
            }
    }

    func beginDisconnectedSetup() {
        usesSystemCalendars = false
        setupCompleted = true
        selectedCalendarIDs = []
        upcomingEvents = []
        todayEvents = []
        monthEvents = []
    }

    func completeConnectedSetup() {
        usesSystemCalendars = true
        setupCompleted = true
        refresh()
        refreshMonth(containing: visibleMonth)
    }

    func requestAccess() async -> Bool {
        lastError = nil
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)

        if authorizationStatus == .denied || authorizationStatus == .restricted {
            lastError = "Calendar access is disabled in System Settings."
            return false
        }

        do {
            let granted = try await store.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)

            if granted {
                usesSystemCalendars = true
                reloadCalendars()
                if selectedCalendarIDs.isEmpty {
                    selectedCalendarIDs = Set(availableCalendars.map(\.id))
                }
                refresh()
                refreshMonth(containing: visibleMonth)
            } else {
                lastError = "Calendar access was not granted."
            }
            return granted
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func openCalendarPrivacySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars"
        ]

        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        reloadCalendars()
    }

    func setCalendar(_ id: String, enabled: Bool) {
        var next = selectedCalendarIDs
        if enabled {
            next.insert(id)
        } else {
            next.remove(id)
        }
        selectedCalendarIDs = next
    }

    func selectAllCalendars() {
        selectedCalendarIDs = Set(availableCalendars.map(\.id))
    }

    /// Whether at least one calendar from this account/source is currently visible.
    /// The account eye button uses this as an action-state: if any are visible,
    /// pressing it hides the whole account; if none are visible, pressing it shows all.
    func sourceHasVisibleCalendars(_ source: String) -> Bool {
        availableCalendars
            .filter { $0.sourceTitle == source }
            .contains { selectedCalendarIDs.contains($0.id) }
    }

    func setSource(_ source: String, enabled: Bool) {
        let ids = Set(
            availableCalendars
                .filter { $0.sourceTitle == source }
                .map(\.id)
        )

        var next = selectedCalendarIDs
        if enabled {
            next.formUnion(ids)
        } else {
            next.subtract(ids)
        }
        selectedCalendarIDs = next
    }

    /// Clears only Zest's Calendar configuration. This never deletes events,
    /// calendars, accounts, or macOS Calendar permission.
    func resetConfiguration() {
        setupCompleted = false
        usesSystemCalendars = false
        selectedCalendarIDs = []
        upcomingEvents = []
        todayEvents = []
        monthEvents = []
        lastError = nil
    }

    func searchEvents(
        matching query: String,
        around referenceDate: Date = Date(),
        monthSpan: Int = 18,
        limit: Int = 80
    ) -> [ZestCalendarEvent] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isConnected, !trimmed.isEmpty else { return [] }

        let selected = selectedEventCalendars()
        guard !selected.isEmpty else { return [] }

        let calendar = Calendar.current
        let start = calendar.date(byAdding: .month, value: -monthSpan, to: referenceDate)
            ?? referenceDate.addingTimeInterval(-365 * 86_400)
        let end = calendar.date(byAdding: .month, value: monthSpan, to: referenceDate)
            ?? referenceDate.addingTimeInterval(365 * 86_400)

        let needle = trimmed.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )

        return events(
            from: start,
            to: end,
            calendars: selected,
            limit: max(limit * 5, 200)
        )
        .filter { event in
            event.title.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ).contains(needle)
            || event.calendarTitle.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ).contains(needle)
        }
        .prefix(limit)
        .map { $0 }
    }

    func reloadCalendars() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        guard hasFullAccess else {
            availableCalendars = []
            return
        }

        availableCalendars = store.calendars(for: .event).map {
            ZestCalendarDescriptor(
                id: $0.calendarIdentifier,
                title: $0.title,
                sourceTitle: $0.source.title
            )
        }

        if usesSystemCalendars && selectedCalendarIDs.isEmpty && !availableCalendars.isEmpty {
            selectedCalendarIDs = Set(availableCalendars.map(\.id))
        }
    }

    func refresh(daysAhead: Int = 7) {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        reloadCalendars()

        guard isConnected else {
            upcomingEvents = []
            todayEvents = []
            return
        }

        let selected = selectedEventCalendars()
        guard !selected.isEmpty else {
            upcomingEvents = []
            todayEvents = []
            return
        }

        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        let startOfTomorrow = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday)
            ?? startOfToday.addingTimeInterval(86_400)
        let upcomingEnd = Calendar.current.date(byAdding: .day, value: max(daysAhead, 1), to: now)
            ?? now.addingTimeInterval(7 * 86_400)

        upcomingEvents = events(
            from: now,
            to: upcomingEnd,
            calendars: selected,
            limit: 40
        )
        todayEvents = events(
            from: startOfToday,
            to: startOfTomorrow,
            calendars: selected,
            limit: 40
        )
    }

    func refreshMonth(containing date: Date) {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        guard let monthStart = Calendar.current.date(from: components) else { return }
        visibleMonth = monthStart

        guard isConnected else {
            monthEvents = []
            return
        }

        let selected = selectedEventCalendars()
        guard !selected.isEmpty else {
            monthEvents = []
            return
        }

        let gridStart = Calendar.current.date(byAdding: .day, value: -7, to: monthStart)
            ?? monthStart
        let monthEnd = Calendar.current.date(byAdding: .month, value: 1, to: monthStart)
            ?? monthStart.addingTimeInterval(31 * 86_400)
        let gridEnd = Calendar.current.date(byAdding: .day, value: 7, to: monthEnd)
            ?? monthEnd

        monthEvents = events(
            from: gridStart,
            to: gridEnd,
            calendars: selected,
            limit: 300
        )
    }

    func events(on date: Date) -> [ZestCalendarEvent] {
        let calendar = Calendar.current
        return monthEvents.filter { event in
            if event.isAllDay {
                return calendar.isDate(event.startDate, inSameDayAs: date)
                    || (event.startDate <= date && event.endDate >= date)
            }
            return calendar.isDate(event.startDate, inSameDayAs: date)
        }
    }

    private func selectedEventCalendars() -> [EKCalendar] {
        store.calendars(for: .event).filter {
            selectedCalendarIDs.contains($0.calendarIdentifier)
        }
    }

    private func events(
        from start: Date,
        to end: Date,
        calendars: [EKCalendar],
        limit: Int
    ) -> [ZestCalendarEvent] {
        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
            calendars: calendars
        )
        return mapEvents(store.events(matching: predicate), limit: limit)
    }

    private func mapEvents(_ events: [EKEvent], limit: Int) -> [ZestCalendarEvent] {
        events
            .sorted { $0.startDate < $1.startDate }
            .prefix(limit)
            .map {
                ZestCalendarEvent(
                    id: $0.eventIdentifier ?? UUID().uuidString,
                    title: $0.title ?? "Untitled Event",
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    isAllDay: $0.isAllDay,
                    calendarTitle: $0.calendar.title
                )
            }
    }
}
