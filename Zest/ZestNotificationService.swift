//
//  ZestNotificationService.swift
//  Zest
//
//  0.1.2 — centralized notification permission + delivery
//

import Foundation
import AppKit
import UserNotifications
import Combine

@MainActor
final class ZestNotificationService: ObservableObject {
    static let shared = ZestNotificationService()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()
    private let explanationShownKey = "zest.notifications.explanationShown"

    private init() {}

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            await refreshAuthorizationStatus()
            print("🍊 NOTIFICATION PERMISSION ERROR →", error.localizedDescription)
            return false
        }
    }

    /// Zest explains the permission before macOS presents its own authorization sheet.
    /// The explanation itself is shown at most once automatically; Settings can still
    /// request permission explicitly at any time.
    func presentLaunchPermissionExplanationIfNeeded() async {
        await refreshAuthorizationStatus()
        guard authorizationStatus == .notDetermined,
              !UserDefaults.standard.bool(forKey: explanationShownKey) else { return }

        UserDefaults.standard.set(true, forKey: explanationShownKey)

        let alert = NSAlert()
        alert.messageText = "Allow Zest Notifications?"
        alert.informativeText = "Zest can confirm when it starts successfully and let you know when software updates are available or installed."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Allow Notifications")
        alert.addButton(withTitle: "Not Now")
        alert.icon = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: "Notifications")

        if alert.runModal() == .alertFirstButtonReturn {
            _ = await requestAuthorization()
        }
    }

    func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func deliver(
        identifier: String = UUID().uuidString,
        title: String,
        body: String,
        sound: UNNotificationSound? = .default
    ) async {
        await refreshAuthorizationStatus()
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound

        do {
            try await center.add(
                UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            )
        } catch {
            print("🍊 NOTIFICATION DELIVERY ERROR →", error.localizedDescription)
        }
    }

    func deliverLaunchNotification() async {
        await deliver(
            identifier: "zest.launch.running",
            title: "Zest is running",
            body: "Your keyboard assistant is ready."
        )
    }

    func deliverUpdateAvailable(version: String, build: String?) async {
        let buildText = build.map { " (Build \($0))" } ?? ""
        await deliver(
            identifier: "zest.update.available.\(version).\(build ?? "")",
            title: "Zest \(version) is available",
            body: "A new Zest update\(buildText) is ready to download."
        )
    }

    func deliverUpdateInstalled(version: String, build: String) async {
        await deliver(
            identifier: "zest.update.installed.\(version).\(build)",
            title: "Zest was updated",
            body: "Zest \(version) (Build \(build)) was installed successfully."
        )
    }
}
