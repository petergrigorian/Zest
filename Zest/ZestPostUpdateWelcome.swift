//
//  ZestPostUpdateWelcome.swift
//  Zest
//
//  0.1.2 — micro-onboarding after a newly installed build
//

import SwiftUI
import AppKit

@MainActor
final class ZestPostUpdateTracker {
    static let shared = ZestPostUpdateTracker()
    private let key = "zest.update.lastAcknowledgedBuild"
    private init() {}

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var internalBuildID: String? {
        Bundle.main.object(forInfoDictionaryKey: "ZestInternalBuildID") as? String
    }

    func seedCurrentBuildIfNeeded() {
        guard UserDefaults.standard.string(forKey: key) == nil else { return }
        UserDefaults.standard.set(currentBuild, forKey: key)
    }

    func shouldShowAfterUpdate(hasCompletedOnboarding: Bool) -> Bool {
        guard hasCompletedOnboarding else {
            seedCurrentBuildIfNeeded()
            return false
        }
        return UserDefaults.standard.string(forKey: key) != currentBuild
    }

    func acknowledgeCurrentBuild() {
        UserDefaults.standard.set(currentBuild, forKey: key)
    }
}

@MainActor
final class ZestPostUpdateWelcomeController: NSWindowController {
    private let settingsManager: ZestSettingsManager
    private var onDismiss: (() -> Void)?

    init(settingsManager: ZestSettingsManager, onDismiss: (() -> Void)? = nil) {
        self.settingsManager = settingsManager
        self.onDismiss = onDismiss
        super.init(window: nil)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        let content = ZestPostUpdateWelcomeView(
            settingsManager: settingsManager,
            openSettings: { [weak self] in self?.finish(openSettings: true) },
            startUsingZest: { [weak self] in self?.finish(openSettings: false) }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 590),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome back to Zest"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: content)
        window.collectionBehavior.insert(.moveToActiveSpace)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func finish(openSettings: Bool) {
        ZestPostUpdateTracker.shared.acknowledgeCurrentBuild()
        window?.orderOut(nil)

        if openSettings {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                focusSettingsWindow()
            }
        }

        onDismiss?()
    }
}

private struct ZestPostUpdateWelcomeView: View {
    @ObservedObject var settingsManager: ZestSettingsManager
    let openSettings: () -> Void
    let startUsingZest: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var assembled = false
    @State private var centerPowered = false
    @State private var shine: CGFloat = 0

    private var tracker: ZestPostUpdateTracker { .shared }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.05),
                    settingsManager.accentColor.opacity(0.08),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 20) {
                Spacer(minLength: 24)

                ZestWelcomeHeroAnimation(
                    accent: settingsManager.accent,
                    assembled: assembled,
                    centerPowered: centerPowered,
                    centerShineProgress: shine,
                    reduceMotion: reduceMotion,
                    scale: 1.20
                )

                VStack(spacing: 7) {
                    Text("Welcome back to Zest")
                        .font(.system(size: 31, weight: .bold, design: .rounded))

                    Text(updateLine)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text("installed successfully")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .opacity(assembled ? 1 : 0)
                .offset(y: assembled ? 0 : 10)

                HStack(spacing: 10) {
                    Button {
                        openSettings()
                    } label: {
                        Label("Open Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(ZestOnboardingSecondaryButton())

                    Button {
                        startUsingZest()
                    } label: {
                        Label("Start Using Zest", systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(ZestOnboardingPrimaryButton(accent: settingsManager.accentColor))
                }
                .opacity(assembled ? 1 : 0)

                Spacer(minLength: 24)
            }
            .padding(34)
        }
        .onAppear { runIntro() }
    }

    private var updateLine: String {
        var line = "Update \(tracker.currentVersion) · Build \(tracker.currentBuild)"
        if let internalID = tracker.internalBuildID, !internalID.isEmpty {
            line += " · \(internalID)"
        }
        return line
    }

    private func runIntro() {
        guard !reduceMotion else {
            assembled = true
            centerPowered = true
            shine = 1
            return
        }

        withAnimation(.spring(response: 0.55, dampingFraction: 0.76)) {
            assembled = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeOut(duration: 0.24)) {
                centerPowered = true
                shine = 1
            }
        }
    }
}
