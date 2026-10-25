//
//  ClipboardHistoryManager.swift
//  Zest
//
//  Created for Zest Clipboard
//
//  Watches the macOS general pasteboard and maintains a lightweight,
//  in-memory history of copied text.
//
//  The history intentionally lives only for the current Zest session.
//  Persistence can be added later.
//
//  IMPORTANT:
//  Clearing Zest history does NOT clear the macOS system clipboard.
//

import Foundation
import AppKit
import Combine


@MainActor
final class ClipboardHistoryManager: ObservableObject {

    // MARK: - Clipboard Entry

    struct Entry: Identifiable, Equatable {

        let id: UUID
        let text: String
        let createdAt: Date

        init(
            id: UUID = UUID(),
            text: String,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.text = text
            self.createdAt = createdAt
        }
    }


    // MARK: - Published State

    @Published private(set) var entries: [Entry] = []


    // MARK: - Configuration

    private let maximumEntries = 20

    private let pollingInterval: TimeInterval = 0.75


    // MARK: - Pasteboard

    private let pasteboard = NSPasteboard.general

    private var lastObservedChangeCount: Int


    // MARK: - Monitoring

    private var timer: Timer?

    private var isRunning = false


    // MARK: - Internal Change Protection

    /// Number of the pasteboard change that Zest itself created.
    ///
    /// When Zest places a history entry back onto the pasteboard,
    /// we don't want the monitor to immediately treat that as a
    /// brand-new clipboard event.
    private var ignoredChangeCount: Int?


    // MARK: - Init

    init() {

        lastObservedChangeCount =
            NSPasteboard.general.changeCount

        startMonitoring()
    }


    deinit {

        timer?.invalidate()
    }


    // MARK: - Monitoring

    func startMonitoring() {

        guard !isRunning else {
            return
        }

        isRunning = true

        lastObservedChangeCount =
            pasteboard.changeCount


        let timer =
            Timer(
                timeInterval:
                    pollingInterval,
                repeats:
                    true
            ) { [weak self] _ in
                // The timer is installed on RunLoop.main below. Avoid creating
                // a new MainActor Task for every idle clipboard poll.
                MainActor.assumeIsolated {
                    self?.pollPasteboard()
                }
            }


        // Clipboard history is background convenience work, not animation work.
        // A tolerance lets macOS coalesce wakeups with other run-loop activity,
        // which noticeably reduces needless main-thread churn while Zest is idle.
        timer.tolerance = 0.15

        RunLoop.main.add(
            timer,
            forMode: .common
        )


        self.timer = timer
    }


    func stopMonitoring() {

        timer?.invalidate()

        timer = nil

        isRunning = false
    }


    // MARK: - Poll

    private func pollPasteboard() {

        let currentChangeCount =
            pasteboard.changeCount


        guard currentChangeCount
                != lastObservedChangeCount
        else {
            return
        }


        lastObservedChangeCount =
            currentChangeCount


        // -----------------------------------------
        // Ignore a pasteboard write created by Zest.
        // -----------------------------------------

        if ignoredChangeCount
            == currentChangeCount
        {

            ignoredChangeCount = nil

            return
        }


        // -----------------------------------------
        // Read plain text.
        // -----------------------------------------

        guard let text =
            pasteboard.string(
                forType: .string
            )
        else {
            return
        }


        addClipboardText(
            text
        )
    }


    // MARK: - Add Entry

    private func addClipboardText(
        _ rawText: String
    ) {

        let text =
            normalizedClipboardText(
                rawText
            )


        guard !text.isEmpty else {
            return
        }


        // -----------------------------------------
        // Exact duplicate already at the top.
        //
        // Nothing to do.
        // -----------------------------------------

        if entries.first?.text
            == text
        {
            return
        }


        // -----------------------------------------
        // If the same clipboard content exists
        // farther down the history, remove it.
        //
        // The new copy becomes the newest entry.
        // -----------------------------------------

        entries.removeAll {
            $0.text == text
        }


        let entry =
            Entry(
                text: text
            )


        entries.insert(
            entry,
            at: 0
        )


        // -----------------------------------------
        // History limit
        // -----------------------------------------

        if entries.count
            > maximumEntries
        {

            entries.removeLast(
                entries.count
                - maximumEntries
            )
        }


        print(
            "🍊 CLIPBOARD → \(previewText(text))"
        )
    }

    // MARK: - Internal Pasteboard Transaction

    func performInternalPasteboardWrite(
        _ operation: () -> Void
    ) {

        operation()

        let changeCount =
            pasteboard.changeCount

        ignoredChangeCount =
            changeCount

        lastObservedChangeCount =
            changeCount
    }

    // MARK: - Put Entry Back On Clipboard

    func copyEntry(
        _ entry: Entry
    ) {

        copyTextToSystemClipboard(
            entry.text
        )
    }


    func copyTextToSystemClipboard(
        _ text: String
    ) {

        pasteboard.clearContents()

        pasteboard.setString(
            text,
            forType: .string
        )


        let newChangeCount =
            pasteboard.changeCount


        ignoredChangeCount =
            newChangeCount

        lastObservedChangeCount =
            newChangeCount


        print(
            "🍊 CLIPBOARD RESTORED → \(previewText(text))"
        )
    }


    // MARK: - Clean Clipboard History

    func clearHistory() {

        entries.removeAll()

        print(
            "🍊 CLIPBOARD HISTORY CLEARED"
        )
    }


    // MARK: - Helpers

    private func normalizedClipboardText(
        _ text: String
    ) -> String {

        // Do NOT trim meaningful whitespace from the actual
        // clipboard content.
        //
        // We only reject content that consists entirely of
        // whitespace/newlines.

        let meaningful =
            text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )


        guard !meaningful.isEmpty else {
            return ""
        }


        return text
    }


    private func previewText(
        _ text: String
    ) -> String {

        let oneLine =
            text
                .replacingOccurrences(
                    of: "\n",
                    with: " "
                )
                .replacingOccurrences(
                    of: "\r",
                    with: " "
                )
                .replacingOccurrences(
                    of: "\t",
                    with: " "
                )


        guard oneLine.count > 70 else {
            return oneLine
        }


        let end =
            oneLine.index(
                oneLine.startIndex,
                offsetBy: 70
            )


        return
            String(
                oneLine[..<end]
            )
            + "…"
    }
}
