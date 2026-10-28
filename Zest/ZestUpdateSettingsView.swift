//
//  ZestUpdateSettingsView.swift
//  Zest
//
//  0.1.1 — custom Software Update page
//

import SwiftUI
import AppKit
import UserNotifications

struct ZestUpdateSettingsView: View {
    @ObservedObject private var updateManager =
        ZestUpdateManager.shared

    let accentColor: Color

    @State private var automaticChecks = false
    @State private var automaticDownloads = false
    @State private var didLoadUpdaterPreferences = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Software Update")
                    .font(
                        .system(
                            size: 26,
                            weight: .bold,
                            design: .rounded
                        )
                    )

                Text("Keep Zest current without leaving the app.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            updateCard

            settingsCard

            Spacer()
        }
        .padding(28)
        .onAppear {
            if !updateManager.isStarted {
                updateManager.start()
            }
            loadUpdaterPreferences()
        }
    }

    private var updateCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 54, height: 54)

                    Image(systemName: statusSymbol)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(
                            .system(
                                size: 16,
                                weight: .bold,
                                design: .rounded
                            )
                        )

                    Text(statusSubtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                primaryAction
            }

            if updateManager.phase == .downloading {
                downloadProgress
            }

            if updateManager.phase == .extracting {
                extractionProgress
            }

            if let notes = updateManager.releaseNotesText,
               !notes.trimmingCharacters(
                    in: .whitespacesAndNewlines
               ).isEmpty,
               updateManager.phase == .available ||
               updateManager.phase == .readyToInstall {

                Divider().opacity(0.45)

                VStack(alignment: .leading, spacing: 6) {
                    Text("What’s New")
                        .font(.system(size: 11, weight: .semibold))

                    Text(stripSimpleHTML(notes))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                        .textSelection(.enabled)
                }
            }

            if let url = updateManager.releaseNotesURL,
               updateManager.phase == .available ||
               updateManager.phase == .readyToInstall {

                Button("View Full Release Notes") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.link)
                .font(.system(size: 10.5, weight: .medium))
            }

            if updateManager.phase == .available ||
               updateManager.phase == .readyToInstall {

                HStack(spacing: 8) {
                    Button("Later") {
                        updateManager.remindMeLater()
                    }

                    Button("Skip This Version") {
                        updateManager.skipCurrentVersion()
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .fill(Color.primary.opacity(0.035))
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Automatic Updates")
                .font(.system(size: 12, weight: .semibold))

            Toggle(
                "Automatically check for Zest updates",
                isOn: $automaticChecks
            )
            .onChange(of: automaticChecks) { _, newValue in
                guard didLoadUpdaterPreferences else { return }
                updateManager.automaticallyChecksForUpdates = newValue

                if !newValue {
                    automaticDownloads = false
                    updateManager.automaticallyDownloadsUpdates = false
                }
            }

            Toggle(
                "Automatically download updates",
                isOn: $automaticDownloads
            )
            .disabled(
                !automaticChecks ||
                !updateManager.allowsAutomaticUpdates
            )
            .onChange(of: automaticDownloads) { _, newValue in
                guard didLoadUpdaterPreferences else { return }
                updateManager.automaticallyDownloadsUpdates = newValue
            }

            Divider().opacity(0.45)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update notifications")
                        .font(.system(size: 11, weight: .medium))
                    Text("Allow Zest to notify you when a new version is available.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Allow") {
                    UNUserNotificationCenter.current()
                        .requestAuthorization(
                            options: [.alert, .sound, .badge]
                        ) { _, _ in }
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .fill(Color.primary.opacity(0.025))
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch updateManager.phase {
        case .idle, .upToDate, .failed:
            Button("Check for Updates") {
                updateManager.checkForUpdates()
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .disabled(!updateManager.canCheckForUpdates)

        case .checking:
            ProgressView()
                .controlSize(.small)

        case .available:
            Button("Download & Install") {
                updateManager.downloadAndPrepareUpdate()
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)

        case .downloading:
            Button("Cancel") {
                updateManager.cancelCurrentOperation()
            }
            .buttonStyle(.bordered)

        case .extracting:
            ProgressView()
                .controlSize(.small)

        case .readyToInstall:
            Button("Install & Relaunch") {
                updateManager.installAndRelaunch()
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)

        case .installing:
            ProgressView()
                .controlSize(.small)
        }
    }

    private var downloadProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: updateManager.progress ?? 0)

            HStack {
                Text(byteProgressText)
                Spacer()

                if let progress = updateManager.progress {
                    Text("\(Int(progress * 100))%")
                }
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private var extractionProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: updateManager.extractionProgress)

            Text(
                "Preparing update… \(Int(updateManager.extractionProgress * 100))%"
            )
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private var statusSymbol: String {
        switch updateManager.phase {
        case .idle: return "arrow.triangle.2.circlepath"
        case .checking: return "magnifyingglass"
        case .upToDate: return "checkmark.circle.fill"
        case .available: return "arrow.down.circle.fill"
        case .downloading: return "arrow.down.circle"
        case .extracting: return "shippingbox"
        case .readyToInstall: return "restart.circle.fill"
        case .installing: return "gearshape.2.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var statusTitle: String {
        switch updateManager.phase {
        case .idle:
            return "Zest \(updateManager.installedVersion)"
        case .checking:
            return "Checking for updates…"
        case .upToDate:
            return "Zest is up to date"
        case .available:
            return "Zest \(updateManager.availableVersion ?? "") is available"
        case .downloading:
            return "Downloading Zest \(updateManager.availableVersion ?? "")"
        case .extracting:
            return "Preparing Zest \(updateManager.availableVersion ?? "")"
        case .readyToInstall:
            return "Ready to install"
        case .installing:
            return "Installing Zest…"
        case .failed:
            return "Software Update failed"
        }
    }

    private var statusSubtitle: String {
        switch updateManager.phase {
        case .idle:
            return "Installed build \(updateManager.installedBuild)."
        case .checking:
            return "Zest is contacting the update feed."
        case .upToDate:
            return "You’re running Zest \(updateManager.installedVersion) (\(updateManager.installedBuild))."
        case .available:
            if let build = updateManager.availableBuild {
                return "Build \(build) is ready to download."
            }
            return "A newer version is ready to download."
        case .downloading:
            return byteProgressText
        case .extracting:
            return "The downloaded update is being verified and prepared."
        case .readyToInstall:
            return "Zest will close briefly, replace the application bundle, and reopen."
        case .installing:
            return "Your settings backup has already been created."
        case .failed:
            return updateManager.lastError ?? "An unknown updater error occurred."
        }
    }

    private var byteProgressText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        let received = formatter.string(
            fromByteCount: Int64(updateManager.receivedDownloadBytes)
        )

        guard updateManager.expectedDownloadBytes > 0 else {
            return received
        }

        let expected = formatter.string(
            fromByteCount: Int64(updateManager.expectedDownloadBytes)
        )

        return "\(received) of \(expected)"
    }

    private func loadUpdaterPreferences() {
        automaticChecks =
            updateManager.automaticallyChecksForUpdates

        automaticDownloads =
            updateManager.automaticallyDownloadsUpdates

        didLoadUpdaterPreferences = true
    }

    private func stripSimpleHTML(_ source: String) -> String {
        source
            .replacingOccurrences(
                of: "<[^>]+>",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
