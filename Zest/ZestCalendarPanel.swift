//
//  ZestCalendarPanel.swift
//  Zest
//

import SwiftUI
import EventKit

struct ZestCalendarPanel: View {
    @ObservedObject private var calendar =
        ZestCalendarService.shared

    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(accentColor)

                Text("Calendar")
                    .font(
                        .system(
                            size: 14,
                            weight: .bold,
                            design: .rounded
                        )
                    )

                Spacer()

                if calendar.hasFullAccess {
                    Button {
                        calendar.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                }
            }

            if calendar.hasFullAccess {
                if calendar.upcomingEvents.isEmpty {
                    ContentUnavailableView(
                        "No Upcoming Events",
                        systemImage: "calendar.badge.checkmark",
                        description: Text(
                            "Nothing is scheduled in the next seven days."
                        )
                    )
                    .frame(height: 190)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(calendar.upcomingEvents) { event in
                                eventRow(event)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 28))
                        .foregroundStyle(accentColor)

                    Text("Calendar access is required")
                        .font(.system(size: 12, weight: .semibold))

                    Button("Allow Calendar Access") {
                        Task { await calendar.requestAccess() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(.regularMaterial)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .onAppear {
            calendar.refresh()
        }
    }

    private func eventRow(
        _ event: ZestCalendarEvent
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(
                cornerRadius: 2,
                style: .continuous
            )
            .fill(accentColor.opacity(0.8))
            .frame(width: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)

                Text(eventTime(event))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(event.calendarTitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(9)
        .background {
            RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
            .fill(Color.primary.opacity(0.035))
        }
    }

    private func eventTime(
        _ event: ZestCalendarEvent
    ) -> String {
        if event.isAllDay {
            return event.startDate.formatted(
                date: .abbreviated,
                time: .omitted
            ) + " · All day"
        }

        return event.startDate.formatted(
            date: .abbreviated,
            time: .shortened
        )
    }
}
