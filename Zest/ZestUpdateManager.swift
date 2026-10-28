//
//  ZestUpdateManager.swift
//  Zest
//
//  0.1.1 — Sparkle-backed updater with Zest-owned UI
//

import Foundation
import AppKit
import Combine
import Sparkle
import UserNotifications

enum ZestUpdatePhase: Equatable {
    case idle
    case checking
    case upToDate
    case available
    case downloading
    case extracting
    case readyToInstall
    case installing
    case failed
}

@MainActor
final class ZestUpdateManager:
    NSObject,
    ObservableObject,
    SPUUserDriver {

    static let shared = ZestUpdateManager()

    @Published private(set) var phase: ZestUpdatePhase = .idle
    @Published private(set) var availableVersion: String?
    @Published private(set) var availableBuild: String?
    @Published private(set) var updateTitle: String?
    @Published private(set) var releaseNotesText: String?
    @Published private(set) var releaseNotesURL: URL?
    @Published private(set) var expectedDownloadBytes: UInt64 = 0
    @Published private(set) var receivedDownloadBytes: UInt64 = 0
    @Published private(set) var extractionProgress: Double = 0
    @Published private(set) var lastError: String?
    @Published private(set) var lastCheckDate: Date?
    @Published private(set) var isStarted = false

    private var updater: SPUUpdater!
    private var updateChoiceContinuation:
        CheckedContinuation<SPUUserUpdateChoice, Never>?
    private var readyChoiceContinuation:
        CheckedContinuation<SPUUserUpdateChoice, Never>?
    private var cancellationHandler: (() -> Void)?

    private override init() {
        super.init()

        updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: self,
            delegate: nil
        )
    }

    var installedVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
    }

    var installedBuild: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"
    }

    var canCheckForUpdates: Bool {
        isStarted && updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set { updater.automaticallyDownloadsUpdates = newValue }
    }

    var allowsAutomaticUpdates: Bool {
        updater.allowsAutomaticUpdates
    }

    var progress: Double? {
        guard expectedDownloadBytes > 0 else { return nil }
        return min(
            max(
                Double(receivedDownloadBytes) /
                Double(expectedDownloadBytes),
                0
            ),
            1
        )
    }

    func start() {
        guard !isStarted else { return }

        ZestSettingsBackupService.shared.ensureSchemaVersion()

        do {
            try updater.start()
            isStarted = true
            lastCheckDate = updater.lastUpdateCheckDate
        } catch {
            phase = .failed
            lastError = error.localizedDescription
            print("🍊 SPARKLE START ERROR →", error.localizedDescription)
        }
    }

    func checkForUpdates() {
        if !isStarted {
            start()

            guard isStarted else {
                return
            }
        }

        lastError = nil
        phase = .checking
        updater.checkForUpdates()
    }

    func cancelCurrentOperation() {
        cancellationHandler?()
        cancellationHandler = nil
    }

    /// Starts/resumes the Sparkle pipeline for the update that is currently shown.
    func downloadAndPrepareUpdate() {
        ZestSettingsBackupService.shared.createBackup(
            reason: "before-update-download"
        )

        updateChoiceContinuation?.resume(returning: .install)
        updateChoiceContinuation = nil
    }

    func remindMeLater() {
        if let continuation = updateChoiceContinuation {
            continuation.resume(returning: .dismiss)
            updateChoiceContinuation = nil
        } else if let continuation = readyChoiceContinuation {
            continuation.resume(returning: .dismiss)
            readyChoiceContinuation = nil
        }

        if phase != .downloading &&
            phase != .extracting &&
            phase != .installing {
            phase = .idle
        }
    }

    func skipCurrentVersion() {
        if let continuation = updateChoiceContinuation {
            continuation.resume(returning: .skip)
            updateChoiceContinuation = nil
        } else if let continuation = readyChoiceContinuation {
            continuation.resume(returning: .skip)
            readyChoiceContinuation = nil
        }

        phase = .idle
    }

    func installAndRelaunch() {
        ZestSettingsBackupService.shared.createBackup(
            reason: "before-update-install"
        )

        if let continuation = readyChoiceContinuation {
            continuation.resume(returning: .install)
            readyChoiceContinuation = nil
        } else if let continuation = updateChoiceContinuation {
            // Sparkle can re-enter showUpdateFound in the `.installing` stage.
            // In that state this choice performs the fast Install & Relaunch path.
            continuation.resume(returning: .install)
            updateChoiceContinuation = nil
        }
    }

    // MARK: SPUUserDriver

    func show(
        _ request: SPUUpdatePermissionRequest
    ) async -> SUUpdatePermissionResponse {
        // Zest exposes these controls in Settings instead of putting a
        // separate Sparkle permission dialog in front of the user.
        SUUpdatePermissionResponse(
            automaticUpdateChecks: false,
            automaticUpdateDownloading: NSNumber(value: false),
            sendSystemProfile: false
        )
    }

    func showUserInitiatedUpdateCheck(
        cancellation: @escaping () -> Void
    ) {
        cancellationHandler = cancellation
        phase = .checking
        lastError = nil
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) async -> SPUUserUpdateChoice {

        cancellationHandler = nil
        availableVersion = appcastItem.displayVersionString
        availableBuild = appcastItem.versionString
        updateTitle = appcastItem.title
        releaseNotesText = appcastItem.itemDescription
        releaseNotesURL = appcastItem.releaseNotesURL ?? appcastItem.infoURL
        expectedDownloadBytes = appcastItem.contentLength
        receivedDownloadBytes = 0
        extractionProgress = 0
        lastError = nil
        lastCheckDate = Date()

        sendUpdateAvailableNotification(
            version: appcastItem.displayVersionString
        )

        switch state.stage {
        case .notDownloaded:
            phase = .available
        case .downloaded:
            phase = .available
        case .installing:
            phase = .readyToInstall
        @unknown default:
            phase = .available
        }

        if appcastItem.isInformationOnlyUpdate {
            if let url = appcastItem.infoURL {
                NSWorkspace.shared.open(url)
            }
            return .dismiss
        }

        return await withCheckedContinuation { continuation in
            updateChoiceContinuation = continuation
        }
    }

    func showUpdateReleaseNotes(
        with downloadData: SPUDownloadData
    ) {
        // Zest uses embedded appcast text and/or a release-notes URL.
        // Keep this hook because Sparkle requires a complete user driver.
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(
        _ error: any Error
    ) {
        // A release-notes failure must not abort the actual application update.
        print(
            "🍊 RELEASE NOTES ERROR →",
            error.localizedDescription
        )
    }

    func showUpdateNotFoundWithError(
        _ error: any Error
    ) async {
        cancellationHandler = nil
        phase = .upToDate
        lastError = nil
        lastCheckDate = Date()
    }

    func showUpdaterError(
        _ error: any Error
    ) async {
        cancellationHandler = nil
        phase = .failed
        lastError = error.localizedDescription
    }

    func showDownloadInitiated(
        cancellation: @escaping () -> Void
    ) {
        cancellationHandler = cancellation
        phase = .downloading
        receivedDownloadBytes = 0
    }

    func showDownloadDidReceiveExpectedContentLength(
        _ expectedContentLength: UInt64
    ) {
        expectedDownloadBytes = expectedContentLength
    }

    func showDownloadDidReceiveData(
        ofLength length: UInt64
    ) {
        receivedDownloadBytes += length
    }

    func showDownloadDidStartExtractingUpdate() {
        cancellationHandler = nil
        phase = .extracting
        extractionProgress = 0
    }

    func showExtractionReceivedProgress(
        _ progress: Double
    ) {
        extractionProgress = min(max(progress, 0), 1)
    }

    func showReadyToInstallAndRelaunch()
        async -> SPUUserUpdateChoice {

        phase = .readyToInstall

        return await withCheckedContinuation { continuation in
            readyChoiceContinuation = continuation
        }
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        phase = .installing
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool
    ) async {
        phase = .idle
    }

    func dismissUpdateInstallation() {
        cancellationHandler = nil

        if phase == .checking ||
            phase == .failed ||
            phase == .upToDate {
            return
        }

        if phase != .installing {
            phase = .idle
        }
    }

    func showUpdateInFocus() {
        NotificationCenter.default.post(
            name: .zestShowSoftwareUpdateSettings,
            object: nil
        )
    }

    private func sendUpdateAvailableNotification(
        version: String
    ) {
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                    settings.authorizationStatus == .provisional else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "Zest \(version) is available"
            content.body = "Open Zest Settings to download and install the update."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "zest.update.\(version)",
                content: content,
                trigger: nil
            )

            center.add(request)
        }
    }
}

extension Notification.Name {
    static let zestShowSoftwareUpdateSettings =
        Notification.Name("zest.settings.showSoftwareUpdate")
}
