//
//  ZestUpdateSettingsView.swift
//  Zest
//
//  0.1.2 — Software Update page + GitHub release notes preview
//

import SwiftUI
import AppKit
import UserNotifications

struct ZestUpdateSettingsView: View {
    @ObservedObject private var updateManager = ZestUpdateManager.shared
    @ObservedObject private var notificationService = ZestNotificationService.shared
    @ObservedObject private var releaseNotes = ZestReleaseNotesService.shared

    let accentColor: Color

    @State private var automaticChecks = false
    @State private var automaticDownloads = false
    @State private var didLoadUpdaterPreferences = false
    @State private var releaseNotesExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Software Update")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Keep Zest current without leaving the app.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                updateCard
                releaseNotesCard
                settingsCard
            }
            .padding(28)
        }
        .onAppear {
            if !updateManager.isStarted { updateManager.start() }
            loadUpdaterPreferences()
            Task { await notificationService.refreshAuthorizationStatus() }
        }
    }

    private var updateCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 54, height: 54)

                    Image(systemName: statusSymbol)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(statusSubtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
                primaryAction
            }

            if updateManager.phase == .downloading { downloadProgress }
            if updateManager.phase == .extracting { extractionProgress }

            if updateManager.phase == .available || updateManager.phase == .readyToInstall {
                HStack(spacing: 10) {
                    Button("Later") { updateManager.remindMeLater() }
                    Button("Skip This Version") { updateManager.skipCurrentVersion() }
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        }
    }

    private var releaseNotesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentColor.opacity(0.10))
                        .frame(width: 38, height: 38)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Release Notes")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Preview the GitHub release notes for this version without leaving Zest.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                        releaseNotesExpanded.toggle()
                    }
                    if releaseNotesExpanded { loadReleaseNotes() }
                } label: {
                    Label(
                        releaseNotesExpanded ? "Hide Release Notes" : "View Release Notes",
                        systemImage: releaseNotesExpanded ? "chevron.up.circle" : "doc.text"
                    )
                }
                .buttonStyle(ZestSecondaryActionButtonStyle())
            }

            if releaseNotesExpanded {
                Divider().opacity(0.45)

                Group {
                    if releaseNotes.isLoading {
                        HStack(spacing: 9) {
                            ProgressView().controlSize(.small)
                            Text("Loading release notes from GitHub…")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                    } else if !releaseNotes.text.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ScrollView {
                                Text(releaseNotes.text)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(Color.primary.opacity(0.88))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 240)

                            if let url = releaseNotes.sourceURL {
                                Button {
                                    NSWorkspace.shared.open(url)
                                } label: {
                                    Label("Open on GitHub", systemImage: "arrow.up.right.square")
                                }
                                .buttonStyle(.link)
                                .font(.system(size: 10.5, weight: .semibold))
                            }
                        }
                    } else {
                        ContentUnavailableView(
                            "No Release Notes",
                            systemImage: "doc.text",
                            description: Text(releaseNotes.lastError ?? "No notes were published for this build.")
                        )
                        .frame(minHeight: 120)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.025))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Automatic Updates")
                .font(.system(size: 12, weight: .semibold))

            Toggle("Automatically check for Zest updates", isOn: $automaticChecks)
                .onChange(of: automaticChecks) { _, value in
                    guard didLoadUpdaterPreferences else { return }
                    updateManager.automaticallyChecksForUpdates = value
                    if !value {
                        automaticDownloads = false
                        updateManager.automaticallyDownloadsUpdates = false
                    }
                }

            Toggle("Automatically download updates", isOn: $automaticDownloads)
                .disabled(!automaticChecks || !updateManager.allowsAutomaticUpdates)
                .onChange(of: automaticDownloads) { _, value in
                    guard didLoadUpdaterPreferences else { return }
                    updateManager.automaticallyDownloadsUpdates = value
                }

            Divider().opacity(0.45)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update notifications")
                        .font(.system(size: 11, weight: .medium))
                    Text(notificationDescription)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                notificationButton
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.025))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch updateManager.phase {
        case .idle, .upToDate, .failed:
            Button { updateManager.checkForUpdates() } label: {
                Label("Check for Updates", systemImage: "arrow.clockwise")
            }
            .buttonStyle(ZestPrimaryActionButtonStyle(accent: accentColor))
            .disabled(!updateManager.canCheckForUpdates)

        case .checking:
            ProgressView().controlSize(.small)

        case .available:
            Button { updateManager.downloadAndPrepareUpdate() } label: {
                Label("Download & Install", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(ZestPrimaryActionButtonStyle(accent: accentColor))

        case .downloading:
            Button { updateManager.cancelCurrentOperation() } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }
            .buttonStyle(ZestSecondaryActionButtonStyle())

        case .extracting:
            ProgressView().controlSize(.small)

        case .readyToInstall:
            Button { updateManager.installAndRelaunch() } label: {
                Label("Install & Relaunch", systemImage: "arrow.clockwise.circle.fill")
            }
            .buttonStyle(ZestPrimaryActionButtonStyle(accent: accentColor))

        case .installing:
            ProgressView().controlSize(.small)
        }
    }

    private var notificationButton: some View {
        Group {
            switch notificationService.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            case .denied:
                Button("Open Settings") { notificationService.openSystemNotificationSettings() }
            case .notDetermined:
                Button("Allow") {
                    Task { _ = await notificationService.requestAuthorization() }
                }
            @unknown default:
                Button("Allow") {
                    Task { _ = await notificationService.requestAuthorization() }
                }
            }
        }
    }

    private var notificationDescription: String {
        switch notificationService.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Zest can notify you about software updates."
        case .denied:
            return "Notifications are disabled for Zest in System Settings."
        case .notDetermined:
            return "Allow Zest to notify you when a new version is available."
        @unknown default:
            return "Manage notification permission for Zest."
        }
    }

    private var downloadProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: updateManager.progress ?? 0)
            HStack {
                Text(byteProgressText)
                Spacer()
                if let progress = updateManager.progress { Text("\(Int(progress * 100))%") }
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private var extractionProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: updateManager.extractionProgress)
            Text("Preparing update… \(Int(updateManager.extractionProgress * 100))%")
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
        case .idle: return "Zest \(updateManager.installedVersion)"
        case .checking: return "Checking for updates…"
        case .upToDate: return "Zest is up to date"
        case .available: return "Zest \(updateManager.availableVersion ?? "") is available"
        case .downloading: return "Downloading Zest \(updateManager.availableVersion ?? "")"
        case .extracting: return "Preparing Zest \(updateManager.availableVersion ?? "")"
        case .readyToInstall: return "Ready to install"
        case .installing: return "Installing Zest…"
        case .failed: return "Software Update failed"
        }
    }

    private var statusSubtitle: String {
        switch updateManager.phase {
        case .idle: return "Installed build \(updateManager.installedBuild)."
        case .checking: return "Zest is contacting the update feed."
        case .upToDate: return "You’re running Zest \(updateManager.installedVersion) (\(updateManager.installedBuild))."
        case .available:
            return updateManager.availableBuild.map { "Build \($0) is ready to download." } ?? "A newer version is ready to download."
        case .downloading: return byteProgressText
        case .extracting: return "The downloaded update is being verified and prepared."
        case .readyToInstall: return "Zest will close briefly, replace the application bundle, and reopen."
        case .installing: return "Your settings backup has already been created."
        case .failed: return updateManager.lastError ?? "An unknown updater error occurred."
        }
    }

    private var byteProgressText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let received = formatter.string(fromByteCount: Int64(updateManager.receivedDownloadBytes))
        guard updateManager.expectedDownloadBytes > 0 else { return received }
        let expected = formatter.string(fromByteCount: Int64(updateManager.expectedDownloadBytes))
        return "\(received) of \(expected)"
    }

    private func loadUpdaterPreferences() {
        automaticChecks = updateManager.automaticallyChecksForUpdates
        automaticDownloads = updateManager.automaticallyDownloadsUpdates
        didLoadUpdaterPreferences = true
    }

    private func loadReleaseNotes() {
        let version = updateManager.availableVersion ?? updateManager.installedVersion
        Task {
            await releaseNotes.load(
                releaseURL: updateManager.releaseNotesURL,
                installedOrAvailableVersion: version,
                fallbackText: updateManager.releaseNotesText
            )
        }
    }
}
