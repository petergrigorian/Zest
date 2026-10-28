//
//  ZestCalendarService.swift
//  Zest
//
//  0.1.1 — EventKit-backed calendar layer
//

import Foundation
import EventKit
import Combine

struct ZestCalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarTitle: String
}

@MainActor
final class ZestCalendarService: ObservableObject {
    static let shared = ZestCalendarService()

    @Published private(set) var authorizationStatus:
        EKAuthorizationStatus =
        EKEventStore.authorizationStatus(for: .event)

    @Published private(set) var upcomingEvents:
        [ZestCalendarEvent] = []

    @Published private(set) var lastError: String?

    private let store = EKEventStore()
    private var storeObserver: NSObjectProtocol?

    private init() {
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
        }
    }

    var hasFullAccess: Bool {
        authorizationStatus == .fullAccess
    }

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            authorizationStatus =
                EKEventStore.authorizationStatus(for: .event)

            if granted {
                refresh()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refresh(daysAhead: Int = 7) {
        authorizationStatus =
            EKEventStore.authorizationStatus(for: .event)

        guard hasFullAccess else {
            upcomingEvents = []
            return
        }

        let start = Date()
        let end = Calendar.current.date(
            byAdding: .day,
            value: max(daysAhead, 1),
            to: start
        ) ?? start.addingTimeInterval(7 * 86_400)

        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
            calendars: nil
        )

        upcomingEvents = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(30)
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
