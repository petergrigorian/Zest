//
//  ZestAccessibilityService.swift
//  Zest
//
//  0.1.2 — explicit Accessibility permission orchestration
//

import AppKit
import ApplicationServices
import Combine
import CoreGraphics

extension Notification.Name {
    static let zestAccessibilityStatusDidChange =
        Notification.Name("zest.accessibility.statusDidChange")
}

@MainActor
final class ZestAccessibilityService: ObservableObject {
    static let shared = ZestAccessibilityService()

    @Published private(set) var isTrusted: Bool
    @Published private(set) var canPostEvents: Bool

    var canUseLayoutFix: Bool {
        isTrusted || canPostEvents
    }

    private var activationObserver: NSObjectProtocol?

    private init() {
        isTrusted = Self.detectAXAccess()
        canPostEvents = CGPreflightPostEventAccess()

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
    }


    /// Silent status refresh. This never asks macOS to display its permission prompt.
    func refreshStatus() {
        let trusted = Self.detectAXAccess()
        let postEvents = CGPreflightPostEventAccess()
        guard trusted != isTrusted || postEvents != canPostEvents else { return }

        isTrusted = trusted
        canPostEvents = postEvents
        NotificationCenter.default.post(
            name: .zestAccessibilityStatusDidChange,
            object: nil,
            userInfo: [
                "trusted": trusted,
                "postEvents": postEvents,
                "layoutFix": trusted || postEvents
            ]
        )
    }

    /// Call only after an explicit user action such as "Allow Accessibility Access".
    func requestAccess() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]

        let trusted = AXIsProcessTrustedWithOptions(options) || Self.detectAXAccess()
        let postEvents = CGRequestPostEventAccess() || CGPreflightPostEventAccess()
        isTrusted = trusted
        canPostEvents = postEvents

        NotificationCenter.default.post(
            name: .zestAccessibilityStatusDidChange,
            object: nil,
            userInfo: [
                "trusted": trusted,
                "postEvents": postEvents,
                "layoutFix": trusted || postEvents
            ]
        )

        // TCC updates asynchronously. Re-check a few times so the UI can recover
        // immediately after the user grants access without relaunching Zest.
        for delay in [0.5, 1.5, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshStatus()
            }
        }
    }

    private static func detectAXAccess() -> Bool {
        if AXIsProcessTrusted() { return true }

        // macOS 27 can update privacy state asynchronously. Probe a harmless AX read
        // as a second source of truth so a stale AXIsProcessTrusted() result does not
        // leave Zest stuck in a false "permission required" state.
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &value
        ) == .success
    }

    func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]

        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                break
            }
        }

        for delay in [0.8, 2.0, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshStatus()
            }
        }
    }
}
