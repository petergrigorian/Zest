import SwiftUI
import AppKit
import ApplicationServices

extension Notification.Name {
    static let zestOpenSettingsAndFocus = Notification.Name("zest.settings.openAndFocus")
    static let zestOnboardingCommitLayout = Notification.Name("zest.onboarding.commitLayout")
    static let zestOnboardingActionOverlayChanged = Notification.Name("zest.onboarding.actionOverlayChanged")
    static let zestOnboardingCloseRequested = Notification.Name("zest.onboarding.closeRequested")
}

@MainActor
final class ZestOnboardingWindowController {
    private var window: NSWindow?
    private var closeDelegate: ZestOnboardingCloseDelegate?
    private let settingsManager: ZestSettingsManager

    init(settingsManager: ZestSettingsManager) { self.settingsManager = settingsManager }

    func show(force: Bool = false) {
        guard force || !settingsManager.hasCompletedOnboarding else { return }
        if let window { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); return }
        let root = ZestOnboardingView(settingsManager: settingsManager) { [weak self] in self?.close() }
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        // Onboarding is a real standalone Zest window, not a translucent utility
        // overlay over the previously active application. SwiftUI can still draw
        // glass inside the window, but the window itself has an opaque foundation.
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.level = .normal
        window.collectionBehavior = [.managed, .participatesInCycle]
        let closeDelegate = ZestOnboardingCloseDelegate()
        window.delegate = closeDelegate
        self.closeDelegate = closeDelegate
        window.contentView = host
        window.center()
        window.setFrameAutosaveName("ZestOnboardingWindow")
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        closeDelegate?.allowNextClose = true
        window?.orderOut(nil)
        window = nil
        closeDelegate = nil
    }
}

private final class ZestOnboardingCloseDelegate: NSObject, NSWindowDelegate {
    var allowNextClose = false
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowNextClose { allowNextClose = false; return true }
        NotificationCenter.default.post(name: .zestOnboardingCloseRequested, object: nil)
        return false
    }
}

private struct OnboardingCenterSectorShape: Shape {
    let index: Int
    let count: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let start: Double
        let end: Double
        if count == 2 {
            start = index == 0 ? 180 : 0
            end = index == 0 ? 360 : 180
        } else {
            start = -135 + Double(index) * 90
            end = start + 90
        }
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        path.closeSubpath()
        return path
    }
}

private enum ZestOnboardingMotion {
    // Centralized onboarding motion language. These are intentionally precise,
    // lightly sprung motions rather than large playful bounces.
    static let page = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let heroFoundation = Animation.easeOut(duration: 0.30).delay(0.10)

    static func heroSegment(index: Int) -> Animation {
        .spring(response: 0.52, dampingFraction: 0.78, blendDuration: 0.08)
            .delay(0.12 + Double(index) * 0.055)
    }

    static let heroCenter = Animation.spring(response: 0.44, dampingFraction: 0.72)
        .delay(0.53)
    static let heroCenterReveal = Animation.spring(response: 0.34, dampingFraction: 0.78).delay(0.68)
    static let heroCopy = Animation.easeOut(duration: 0.38).delay(3.02)
    static let heroButton = Animation.easeOut(duration: 0.34).delay(3.18)
}

struct ZestOnboardingView: View {
    @ObservedObject var settingsManager: ZestSettingsManager
    @ObservedObject private var accessibilityService = ZestAccessibilityService.shared
    let close: () -> Void
    @State private var page = 0
    @State private var assembled = false
    @State private var heroCenterPowered = false
    @State private var heroCenterShineProgress: CGFloat = 0
    @State private var guideStep = 0
    @State private var permissionPulse = false
    @State private var featureRevealCount = 0
    @State private var permissionRevealCount = 0
    @State private var formRevealCount = 0
    @State private var guideDemoPhase = 0
    @State private var guideKeyRevealCount = 0
    @State private var guidePointerProgress: CGFloat = 0
    @State private var guidePressed = false
    @State private var guidePopupVisible = false
    @State private var guideSliderValue: Double = 0
    @State private var guideLanguageIndex = 0
    @State private var guideLanguageRotation: Double = 0
    @State private var guideLanguageOpacity: Double = 1
    @State private var guideDashboardVisible = false
    @State private var guideHUDDirection = 1
    @State private var shortcutDraft: ZestKeyboardShortcut = .defaultShowZest
    @State private var hasLoadedShortcutDraft = false
    @State private var hasPickedAccent = false
    @State private var navigationDirection: Int = 1
    @State private var showAbortConfirmation = false
    @State private var actionOverlayPresented = false
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var onboardingAccentChoice: ZestAccent {
        (!hasPickedAccent && page <= 4) ? .rainbow : settingsManager.accent
    }
    private var accent: Color { onboardingAccentChoice.palette.primary }

    // MARK: - STEP 1 HERO LABELS
    //
    // The Welcome hero intentionally keeps the six glass wedges unlabelled.
    // The production wedge geometry is strongly asymmetric, so even mathematically
    // centered glyphs read unevenly from slot to slot at hero scale. Feature icons
    // remain present everywhere else in the real Zest UI and onboarding guides.

    var body: some View {
        ZStack {
            onboardingBackground
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.65), value: settingsManager.accent)
                .animation(.easeInOut(duration: 0.65), value: page)
                .animation(.easeInOut(duration: 0.30), value: colorScheme)

            VStack(spacing: 0) {
                HStack {
                    Text("Zest").font(.system(size: 16, weight: .bold, design: .rounded))
                    Spacer()
                    Text("\(page + 1) of 9").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }.padding(.horizontal, 34).padding(.top, 26)

                Group {
                    switch page {
                    case 0: welcome
                    case 1: features
                    case 2: permissions
                    case 3: shortcut
                    case 4: colors
                    case 5: formFactor
                    case 6: tileSetup
                    case 7: guide
                    default: complete
                    }
                }
                .id(page)
                .transition(pageTransition)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if page > 0 && page < 8 {
                    HStack {
                        Button("Back") {
                            navigationDirection = -1
                            withAnimation(reduceMotion ? nil : ZestOnboardingMotion.page) { page -= 1 }
                        }.buttonStyle(.plain).foregroundStyle(.secondary)
                        Spacer()
                        Button(page == 3 ? (shortcutDraft == .defaultShowZest ? "Keep Default  →" : "Save  →") : "Continue  →") { next() }
                            .buttonStyle(ZestOnboardingPrimaryButton(accent: accent))
                    }.padding(.horizontal, 38).padding(.bottom, 30)
                }
            }

            // The Application / Shortcut chooser owns its full-window material
            // scrim while onboarding. Do not place another parent-level scrim here:
            // that would sit above the embedded chooser and hide the chooser itself.

            if showAbortConfirmation {
                onboardingAbortOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(10000)
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .onAppear {
            shortcutDraft = settingsManager.showZestShortcut
            hasLoadedShortcutDraft = true
            guard !assembled else { return }
            if reduceMotion {
                assembled = true
            } else {
                // The six production wedges assemble first. The center then powers
                // on briefly before the copy is revealed.
                assembled = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(820))
                    withAnimation(.easeOut(duration: 0.32)) { heroCenterPowered = true }

                    // As the center powers on, sweep a specular reflection across
                    // the complete center disc. The Welcome wedges intentionally stay
                    // icon-free so the assembly reads as one clean physical object.
                    heroCenterShineProgress = 0
                    withAnimation(.easeInOut(duration: 1.18)) {
                        heroCenterShineProgress = 1
                    }
                    // Preserve the original pacing that was previously occupied by
                    // the clockwise glyph reveal sequence.
                    try? await Task.sleep(for: .milliseconds(600))

                    // Let the complete center tile stay fully illuminated long enough
                    // to read as a deliberate power-on state rather than a flash.
                    try? await Task.sleep(for: .milliseconds(660))
                    withAnimation(.easeInOut(duration: 0.68)) { heroCenterPowered = false }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .zestOnboardingActionOverlayChanged)) { note in
            guard let visible = note.object as? Bool else { return }
            withAnimation(.easeInOut(duration: 0.16)) { actionOverlayPresented = visible }
        }
        .onReceive(NotificationCenter.default.publisher(for: .zestOnboardingCloseRequested)) { _ in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { showAbortConfirmation = true }
        }
    }


    private var onboardingBackground: some View {
        let themeColor = onboardingAccentChoice.displayColors.first ?? accent

        return ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color.white.opacity(0.025),
                        themeColor.opacity(page >= 4 ? 0.075 : 0.025),
                        accent.opacity(page >= 4 ? 0.055 : 0.018),
                        Color.black.opacity(0.10)
                    ]
                    : [
                        Color.white.opacity(0.72),
                        themeColor.opacity(page >= 4 ? 0.10 : 0.035),
                        accent.opacity(page >= 4 ? 0.065 : 0.020),
                        Color.black.opacity(0.018)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: colorScheme == .dark
                    ? [themeColor.opacity(0.055), .clear]
                    : [Color.white.opacity(0.24), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 620
            )
        }
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()

            onboardingWelcomeZest(scale: 1.55)

            VStack(spacing: 8) {
                Text("Welcome to Zest")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("Your tools, right where you need them.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .opacity(assembled ? 1 : 0)
            .offset(y: assembled && !reduceMotion ? 0 : (reduceMotion ? 0 : 12))
            .animation(reduceMotion ? nil : ZestOnboardingMotion.heroCopy, value: assembled)

            Button("Get Started  →") { next() }
                .buttonStyle(ZestOnboardingPrimaryButton(accent: accent))
                .opacity(assembled ? 1 : 0)
                .offset(y: assembled && !reduceMotion ? 0 : (reduceMotion ? 0 : 8))
                .animation(reduceMotion ? nil : ZestOnboardingMotion.heroButton, value: assembled)

            Spacer()
        }
    }

    private var features: some View {
        VStack(spacing: 28) {
            onboardingHeader("Everything you need, one gesture away.", "Zest keeps useful tools close without breaking your flow.")
            HStack(spacing: 18) {
                revealFeatureCard(0, "Multitasking reimagined", "Bring up Zest over the app you're already using.", "sparkles.rectangle.stack")
                revealFeatureCard(1, "Write faster", "Fonts, size, clipboard, emoji and symbols in one consistent interface.", "text.cursor")
                revealFeatureCard(2, "Make Zest yours", "Choose its shape, controls, shortcuts and appearance.", "slider.horizontal.3")
            }.frame(maxWidth: 790)
            productionMiniSlice(scale: 1.0)
                .opacity(featureRevealCount >= 4 ? 1 : 0)
                .scaleEffect(featureRevealCount >= 4 ? 1 : 0.72)
                .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.78), value: featureRevealCount)
        }
        .onAppear { runStaggeredReveal(kind: .features) }
    }

    private var permissions: some View {
        VStack(spacing: 26) {
            onboardingHeader("A couple of permissions.", "Zest uses macOS accessibility services to work with the app you're already using.")
            VStack(spacing: 12) {
                permissionRow(
                    "Accessibility",
                    "Allows Zest to read the active text context, follow the caret, and insert changes.",
                    granted: accessibilityService.isTrusted,
                    actionTitle: "Allow Access"
                ) {
                    accessibilityService.requestAccess()
                }
                .opacity(permissionRevealCount > 0 ? 1 : 0).scaleEffect(permissionRevealCount > 0 ? 1 : 0.94)
                permissionRow(
                    "Automation",
                    "Some app-specific controls may ask for Automation access when first used.",
                    granted: false,
                    actionTitle: "Open Settings"
                ) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") { NSWorkspace.shared.open(url) }
                }
                .opacity(permissionRevealCount > 1 ? 1 : 0).scaleEffect(permissionRevealCount > 1 ? 1 : 0.94)
            }.frame(maxWidth: 720)
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill").foregroundStyle(accent)
                Text("If macOS asks for Automation later, allow Zest in System Settings → Privacy & Security → Automation.")
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 13).frame(height: 34)
            .background(Capsule().fill(Color.primary.opacity(0.035)))
            .opacity(permissionRevealCount > 2 ? 1 : 0).scaleEffect(permissionRevealCount > 2 ? 1 : 0.94)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.82), value: permissionRevealCount)
        .onAppear { permissionPulse.toggle(); runStaggeredReveal(kind: .permissions) }
    }

    private var shortcut: some View {
        VStack(spacing: 28) {
            onboardingHeader("How will you summon Zest?", "Keep the default shortcut or record your own. You can change it later in Settings.")
            VStack(spacing: 14) {
                Text(shortcutDraft.displayString).font(.system(size: 48, weight: .bold, design: .rounded)).monospacedDigit()
                    .frame(width: 430, height: 125)
                    .background(RoundedRectangle(cornerRadius: 28).fill(accent.opacity(0.08)).glassEffect(.regular.tint(accent.opacity(0.10)), in: RoundedRectangle(cornerRadius: 28)))
                HStack(spacing: 10) {
                    ZestShortcutRecorderRow("Show Zest", shortcut: $shortcutDraft)
                    Button("Set Default") { shortcutDraft = .defaultShowZest }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }.frame(width: 520)
                Text("The shortcut is only activated after you continue, so recording it cannot summon Zest mid-setup.")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }

    private var colors: some View {
        VStack(spacing: 26) {
            onboardingHeader("Pick your Zest.", "Choose an accent that feels like yours.")
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(74), spacing: 12), count: 7), spacing: 14) {
                ForEach(ZestAccent.allCases) { choice in
                    Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { settingsManager.accent = choice; hasPickedAccent = true } } label: {
                        VStack(spacing: 7) {
                            Circle().fill(LinearGradient(colors: choice.displayColors, startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 44, height: 44)
                                .overlay(Circle().stroke(choice == settingsManager.accent ? Color.primary.opacity(0.75) : Color.white.opacity(0.5), lineWidth: choice == settingsManager.accent ? 2 : 1))
                            Text(choice.title).font(.system(size: 9, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                        }.frame(width: 72, height: 72)
                    }.buttonStyle(.plain)
                }
            }.frame(maxWidth: 620)
            Text("You can change the accent anytime in Zest Settings.").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }
    }

    private var formFactor: some View {
        VStack(spacing: 28) {
            onboardingHeader("Choose your Zest.", "Pick the shape that best fits the way you work.")
            HStack(spacing: 18) {
                ForEach(Array(ZestFormFactor.allCases.enumerated()), id: \.element.id) { index, factor in
                    Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { settingsManager.formFactor = factor } } label: {
                        VStack(spacing: 12) {
                            productionFormPreview(factor).frame(height: 105)
                            Text(factor.title).font(.system(size: 14, weight: .bold))
                            Text(factor.subtitle).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        }.frame(width: 178, height: 190)
                            .background(RoundedRectangle(cornerRadius: 22).fill(factor == settingsManager.formFactor ? accent.opacity(0.10) : Color.primary.opacity(0.025)).glassEffect(.regular.tint(accent.opacity(factor == settingsManager.formFactor ? 0.10 : 0.025)), in: RoundedRectangle(cornerRadius: 22)))
                            .overlay(RoundedRectangle(cornerRadius: 22).stroke(factor == settingsManager.formFactor ? accent.opacity(0.55) : Color.white.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .opacity(formRevealCount > index ? 1 : 0)
                    .scaleEffect(formRevealCount > index ? 1 : 0.90)
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.80), value: formRevealCount)
        .onAppear { runStaggeredReveal(kind: .forms) }
    }

    private var tileSetup: some View {
        VStack(spacing: 0) {
            onboardingHeader("Set up your tiles.", "Choose the tools Zest should contain at first launch. You can rearrange them anytime in Settings.")

            // Keep the production editor in the same visual band as the reference:
            // a deliberate breathing area below the heading, then the complete
            // Settings editor centered as one unit above the navigation footer.
            Spacer()
                .frame(height: 72)

            onboardingTileEditor
                .frame(height: 390)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    @ViewBuilder private var onboardingTileEditor: some View {
        // Do not duplicate the Feature Placement UI here. This is literally the
        // same production editor used by Settings > General > Feature Placement.
        // Any future tile geometry/drag-behaviour changes therefore arrive in
        // onboarding automatically.
        ZestSettingsView(settingsManager: settingsManager, layoutOnly: true, onboardingLayoutMode: true)
            .frame(maxWidth: 960, minHeight: 390, maxHeight: 390)
    }

    private func centerOnlyModeCard(_ id: String, _ title: String, _ subtitle: String, _ symbol: String) -> some View {
        let selected = settingsManager.centerOnlyPage == id
        return Button { withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) { settingsManager.centerOnlyPage = id } } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) { Text(title).font(.system(size: 10, weight: .bold)); Text(subtitle).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary) }
            }.padding(.horizontal, 12).frame(width: 180, height: 52)
                .background(RoundedRectangle(cornerRadius: 14).fill(selected ? accent.opacity(0.13) : Color.primary.opacity(0.025)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? accent.opacity(0.5) : Color.white.opacity(0.2), lineWidth: 0.8))
        }.buttonStyle(.plain)
    }

    private var guide: some View {
        VStack(spacing: 18) {
            onboardingHeader("Meet Zest.", "A quick tour using the same controls you'll use every day.")
            ZStack {
                RoundedRectangle(cornerRadius: 28).fill(Color.primary.opacity(0.025)).glassEffect(.regular.tint(accent.opacity(0.05)), in: RoundedRectangle(cornerRadius: 28))
                guideScene
            }
            .frame(width: 720, height: 330)
            .clipped()
            HStack(spacing: 8) {
                ForEach(0..<guideStepCount, id: \.self) { i in Circle().fill(i == guideStep ? accent : Color.secondary.opacity(0.25)).frame(width: 7, height: 7) }
            }
            HStack(spacing: 12) {
                Button("Replay") { guideDemoPhase += 1; runGuideAnimation() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Button(guideStep == guideStepCount - 1 ? "Again" : "Next Tip") {
                    guideDemoPhase += 1
                    withAnimation(.easeInOut(duration: 0.3)) { guideStep = (guideStep + 1) % guideStepCount }
                }.buttonStyle(ZestOnboardingPrimaryButton(accent: accent))
            }
        }
        .onAppear { runGuideAnimation(after: 0.18) }
        .onChange(of: guideStep) { _, _ in runGuideAnimation(after: 0.12) }
    }

    private var guideStepCount: Int {
        switch settingsManager.formFactor {
        case .orangeSlice:
            return 5
        case .centerOnly, .turntable:
            // Turntable / Center Only share the compact circular onboarding family. The 2/4 Split modes
            // additionally teach feature popups before Settings/menu bar/HUD.
            return settingsManager.centerOnlyPage == "language" ? 4 : 5
        case .tripleSquare:
            return 5
        }
    }

    private func later(_ delay: Double, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            action()
        }
    }

    @ViewBuilder private var guideScene: some View {
        // Center Only / Language Turntable has its own guide. It intentionally
        // does NOT inherit the Orange Slice popup lesson because this form
        // factor has no feature-popup interaction in language mode.
        if settingsManager.formFactor == .centerOnly || settingsManager.formFactor == .turntable {
            if settingsManager.centerOnlyPage == "language" {
                centerOnlyGuideScene
            } else {
                centerOnlySplitGuideScene
            }
        } else if settingsManager.formFactor == .tripleSquare {
            tripleGuideScene
        } else {
            switch guideStep {
            case 0:
                guideSummonScene
            case 1:
                guideInteractionScene
            case 2:
                guideLanguageScene
            case 3:
                guideMenuBarScene
            case 4:
                guideRapidInputScene
            default:
                guideRapidInputScene
            }
        }
    }

    @ViewBuilder private var centerOnlyGuideScene: some View {
        switch guideStep {
        case 0:
            guideCenterOnlyLanguageScene
        case 1:
            guideCenterOnlySettingsScene
        case 2:
            guideMenuBarScene
        case 3:
            guideRapidInputScene
        default:
            guideRapidInputScene
        }
    }


    @ViewBuilder private var centerOnlySplitGuideScene: some View {
        switch guideStep {
        case 0:
            guideSummonScene
        case 1:
            guideCenterOnlySplitInteractionScene
        case 2:
            guideCenterOnlySplitSettingsScene
        case 3:
            guideMenuBarScene
        case 4:
            guideRapidInputScene
        default:
            guideRapidInputScene
        }
    }

    @ViewBuilder private var tripleGuideScene: some View {
        switch guideStep {
        case 0:
            guideSummonScene
        case 1:
            guideTripleInteractionScene
        case 2:
            guideTripleSettingsScene
        case 3:
            guideMenuBarScene
        case 4:
            guideRapidInputScene
        default:
            guideRapidInputScene
        }
    }

    private var tripleGuideFeatures: [ZestFeature] {
        Array(settingsManager.tripleFeatures.prefix(3))
    }

    private var tripleGuideColors: [Color] {
        (0..<3).map { settingsManager.accentColor(at: $0) }
    }

    private func productionTripleControl(
        pressedFeatureIndex: Int? = nil,
        settingsPressed: Bool = false
    ) -> some View {
        ZestV34TripleTileControl(
            features: tripleGuideFeatures,
            featureColors: tripleGuideColors,
            accentColor: settingsManager.accentColor,
            accentBrightColor: settingsManager.accentBrightColor,
            accentHighlightColor: settingsManager.accentHighlightColor,
            accentDeepColor: settingsManager.accentDeepColor,
            rearGlassPrimaryColor: settingsManager.rearGlassPrimaryColor,
            rearGlassBrightColor: settingsManager.rearGlassBrightColor,
            pressedFeatureIndex: pressedFeatureIndex,
            settingsPressed: settingsPressed,
            showsDragHandle: true
        )
    }

    private var guideTripleInteractionScene: some View {
        VStack(spacing: 8) {
            ZStack {
                // Popup sits above Triple Square in production, so the guide
                // preserves that physical relationship instead of putting it
                // beside the control.
                VStack(spacing: -5) {
                    VStack(spacing: 8) {
                        Capsule().fill(accent.opacity(0.24)).frame(width: 122, height: 14)
                        Capsule().fill(accent.opacity(0.15)).frame(width: 90, height: 10)
                        HStack(spacing: 10) {
                            Circle().fill(accent.opacity(0.34)).frame(width: 18, height: 18)
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.10)).frame(width: 104, height: 6)
                                Capsule().fill(accent).frame(width: 104 * guideSliderValue, height: 6)
                                Circle().fill(Color.primary).frame(width: 18, height: 18)
                                    .offset(x: max(0, 95 * guideSliderValue))
                            }
                            .frame(width: 112, height: 20)
                        }
                    }
                    .padding(14)
                    .frame(width: 190)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(.regularMaterial)
                            .glassEffect(
                                .regular.tint(accent.opacity(0.08)),
                                in: RoundedRectangle(cornerRadius: 18)
                            )
                    )
                    .opacity(guidePopupVisible ? 1 : 0)
                    .scaleEffect(guidePopupVisible ? 1 : 0.86, anchor: .bottom)

                    productionTripleControl(
                        pressedFeatureIndex: guidePressed ? 1 : nil
                    )
                    .scaleEffect(1.18)
                    .frame(width: 255, height: 138)
                }

                // Land on the exact middle production tile.
                guidePointer
                    .offset(
                        x: 115 * (1 - guidePointerProgress),
                        y: -82 + 84 * guidePointerProgress
                    )
                    .scaleEffect(guidePressed ? 0.82 : 1)
            }
            .frame(width: 360, height: 245)

            Text("Click a tile to open its popup.")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
    }

    private var guideTripleSettingsScene: some View {
        VStack(spacing: 10) {
            ZStack {
                productionTripleControl(settingsPressed: guidePressed)
                    .scaleEffect(1.42)
                    .frame(width: 320, height: 180)

                // Triple Square's production Settings button is centered under
                // the three tiles. The pointer terminates on that exact center.
                guidePointer
                    .offset(
                        x: 116 * (1 - guidePointerProgress),
                        y: -82 * (1 - guidePointerProgress) + 47 * guidePointerProgress
                    )
                    .scaleEffect(guidePressed ? 0.82 : 1)
            }
            .frame(width: 360, height: 205)

            Text("Click the gear to open Settings.")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
    }

    private var guideSummonScene: some View {
        VStack(spacing: 18) {
            HStack(spacing: 7) {
                ForEach(Array(settingsManager.showZestShortcut.displayString).map(String.init).indices, id: \.self) { i in
                    let chars = Array(settingsManager.showZestShortcut.displayString).map(String.init)
                    keyCap(chars[i])
                        .opacity(guideKeyRevealCount > i ? 1 : 0)
                        .scaleEffect(guideKeyRevealCount > i ? 1 : 0.68)
                }
            }
            productionGuideZest
                .frame(width: 190, height: 130)
                .opacity(guideKeyRevealCount > settingsManager.showZestShortcut.displayString.count ? 1 : 0)
                .scaleEffect(guideKeyRevealCount > settingsManager.showZestShortcut.displayString.count ? 1 : 0.88)
            Text("Press your shortcut to summon Zest.").font(.system(size: 13, weight: .semibold))
        }
    }

    private var guideInteractionScene: some View {
        ZStack {
            HStack(spacing: -10) {
                productionGuideZest
                    .frame(width: 210, height: 170)
                    .scaleEffect(guidePressed ? 0.965 : 1)
                    .brightness(guidePressed ? 0.09 : 0)

                VStack(spacing: 8) {
                    Capsule().fill(accent.opacity(0.24)).frame(width: 122, height: 14)
                    Capsule().fill(accent.opacity(0.15)).frame(width: 90, height: 10)
                    HStack(spacing: 10) {
                        Circle().fill(accent.opacity(0.34)).frame(width: 18, height: 18)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.10)).frame(width: 104, height: 6)
                            Capsule().fill(accent).frame(width: 104 * guideSliderValue, height: 6)
                            Circle().fill(Color.primary).frame(width: 18, height: 18)
                                .offset(x: max(0, 95 * guideSliderValue))
                        }.frame(width: 112, height: 20)
                    }
                }
                .padding(14)
                .frame(width: 190)
                .background(RoundedRectangle(cornerRadius: 18).fill(.regularMaterial).glassEffect(.regular.tint(accent.opacity(0.08)), in: RoundedRectangle(cornerRadius: 18)))
                .opacity(guidePopupVisible ? 1 : 0)
                .scaleEffect(guidePopupVisible ? 1 : 0.86, anchor: .leading)
            }
            // Starts in the open space and lands directly on the upper-right
            // feature tile of the real Orange Slice before the click pulse.
            guidePointer
                .offset(
                    x: 12 - 96 * guidePointerProgress,
                    y: -62 + 28 * guidePointerProgress
                )
        }
        .overlay(alignment: .bottom) {
            Text("Click a tile to open its popup.")
                .font(.system(size: 13, weight: .semibold))
                .offset(y: 20)
        }
    }

    private var guideLanguageScene: some View {
        VStack(spacing: 10) {
            ZStack {
                if settingsManager.formFactor == .orangeSlice {
                    // Keep the real production Orange Slice as the physical body.
                    productionMiniSlice(scale: 1.90)
                        .scaleEffect(guidePressed ? 0.985 : 1)

                    // Tutorial-only turntable face, matched to the live Orange Slice
                    // center. The language label itself rotates as one unit, just as
                    // ContentView.mainSliceLanguageTurntable does in production.
                    Circle()
                        .fill(settingsManager.accentDeepColor.opacity(0.055))
                        .frame(width: 82, height: 82)
                        .glassEffect(.regular.tint(accent.opacity(0.24)), in: Circle())
                        .overlay {
                            Circle().stroke(Color.white.opacity(0.48), lineWidth: 0.8)
                        }

                    ZStack {
                        Text(["EN", "UA", "DE"][guideLanguageIndex % 3])
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .offset(y: -20)
                        Text(["ABC", "АБВ", "ABC"][guideLanguageIndex % 3])
                            .font(.system(size: 5.2, weight: .semibold, design: .rounded))
                            .offset(y: 21)
                    }
                    .rotationEffect(.degrees(guideLanguageRotation))
                    .opacity(guideLanguageOpacity)

                    HStack(spacing: 52) {
                        Circle().fill(Color.primary.opacity(guidePressed && guideHUDDirection < 0 ? 0.14 : 0.07)).frame(width: 25, height: 25)
                            .glassEffect(.regular.tint(accent.opacity(0.10)), in: Circle())
                            .overlay(Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold)))
                            .scaleEffect(guidePressed && guideHUDDirection < 0 ? 0.86 : 1)
                        Circle().fill(Color.primary.opacity(guidePressed && guideHUDDirection > 0 ? 0.14 : 0.07)).frame(width: 25, height: 25)
                            .glassEffect(.regular.tint(accent.opacity(0.10)), in: Circle())
                            .overlay(Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)))
                            .scaleEffect(guidePressed && guideHUDDirection > 0 ? 0.86 : 1)
                    }

                    guidePointer
                        .offset(x: guideHUDDirection > 0 ? 40 : -40, y: 0)
                        .scaleEffect(guidePressed ? 0.82 : 1)
                } else {
                    productionMiniCenterPreview.scaleEffect(1.72)
                    guidePointer
                        .offset(x: guideHUDDirection > 0 ? 58 : -58, y: 1)
                        .scaleEffect(guidePressed ? 0.82 : 1)
                }
            }
            .frame(height: 170)

            Text("Switch input sources easily in one click.")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }


    private var centerOnlySplitGuideCount: Int {
        settingsManager.centerOnlyPage == "twoFeature" ? 2 : 4
    }

    private var centerOnlySplitGuideFeatures: [ZestFeature] {
        centerOnlySplitGuideCount == 2
            ? settingsManager.centerOnlyTwoFeatures
            : settingsManager.centerOnlyFourFeatures
    }

    private var centerOnlySplitGuideColors: [Color] {
        (0..<centerOnlySplitGuideCount).map { settingsManager.accentColor(at: $0) }
    }

    private func productionCenterOnlySplit(
        pressedFeatureIndex: Int? = nil,
        settingsPressed: Bool = false
    ) -> some View {
        ZestV34CenterOnlySplitView(
            features: centerOnlySplitGuideFeatures,
            count: centerOnlySplitGuideCount,
            featureColors: centerOnlySplitGuideColors,
            accentColor: settingsManager.accentColor,
            accentBrightColor: settingsManager.accentBrightColor,
            accentHighlightColor: settingsManager.accentHighlightColor,
            accentDeepColor: settingsManager.accentDeepColor,
            pressedFeatureIndex: pressedFeatureIndex,
            settingsPressed: settingsPressed
        )
    }

    private var guideCenterOnlySplitInteractionScene: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ZStack {
                    productionCenterOnlySplit(
                        pressedFeatureIndex: guidePressed ? 0 : nil
                    )
                    .scaleEffect(1.70)
                    .frame(width: 180, height: 180)

                    // Start in open space, then land on the exact top feature
                    // sector used by the in-field 2/4 Split renderer.
                    guidePointer
                        .offset(
                            x: 94 * (1 - guidePointerProgress),
                            y: -72 + 22 * (1 - guidePointerProgress)
                        )
                        .scaleEffect(guidePressed ? 0.82 : 1)
                }
                .frame(width: 190, height: 190)

                VStack(spacing: 8) {
                    Capsule().fill(accent.opacity(0.24)).frame(width: 122, height: 14)
                    Capsule().fill(accent.opacity(0.15)).frame(width: 90, height: 10)
                    HStack(spacing: 10) {
                        Circle().fill(accent.opacity(0.34)).frame(width: 18, height: 18)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.10)).frame(width: 104, height: 6)
                            Capsule().fill(accent).frame(width: 104 * guideSliderValue, height: 6)
                            Circle().fill(Color.primary).frame(width: 18, height: 18)
                                .offset(x: max(0, 95 * guideSliderValue))
                        }
                        .frame(width: 112, height: 20)
                    }
                }
                .padding(14)
                .frame(width: 190)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.regularMaterial)
                        .glassEffect(
                            .regular.tint(accent.opacity(0.08)),
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                )
                .opacity(guidePopupVisible ? 1 : 0)
                .scaleEffect(guidePopupVisible ? 1 : 0.86, anchor: .leading)
            }

            Text("Click a tile to open its popup.")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
    }

    private var guideCenterOnlySplitSettingsScene: some View {
        VStack(spacing: 10) {
            ZStack {
                productionCenterOnlySplit(settingsPressed: guidePressed)
                    .scaleEffect(1.85)
                    .frame(width: 210, height: 190)

                // The Settings gear is physically centered in the production
                // split renderer, so the cursor ends at the renderer origin.
                guidePointer
                    .offset(
                        x: 116 * (1 - guidePointerProgress),
                        y: -72 * (1 - guidePointerProgress)
                    )
                    .scaleEffect(guidePressed ? 0.82 : 1)
            }
            .frame(width: 300, height: 205)

            Text("Click the center gear to open Settings.")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
    }

    private var guideCenterOnlyLanguageScene: some View {
        VStack(spacing: 8) {
            ZStack {
                // EXACT shared production renderer used by ContentView's live
                // Center Only language mode. The guide only scales it up and
                // drives its existing language-rotation parameters.
                ZestV34CenterOnlyLanguageTurntable(
                    accentColor: settingsManager.accentColor,
                    accentBrightColor: settingsManager.accentBrightColor,
                    accentHighlightColor: settingsManager.accentHighlightColor,
                    accentDeepColor: settingsManager.accentDeepColor,
                    rearGlassPrimaryColor: settingsManager.rearGlassPrimaryColor,
                    rearGlassBrightColor: settingsManager.rearGlassBrightColor,
                    shortLabel: ["EN", "UA", "DE"][guideLanguageIndex % 3],
                    sourceName: ["English", "Ukrainian", "German"][guideLanguageIndex % 3],
                    languageRotation: guideLanguageRotation,
                    languageOpacity: guideLanguageOpacity,
                    pressedDirection: guidePressed ? guideHUDDirection : 0
                )
                .scaleEffect(1.72)

                // The production chevrons sit at ±49 pt from the dial center.
                // Scale the pointer target by the exact same presentation scale
                // so the cursor lands on the real button rather than beside it.
                guidePointer
                    .offset(
                        x: 100 * (1 - guidePointerProgress)
                            + CGFloat(guideHUDDirection) * 84 * guidePointerProgress,
                        y: -70 * (1 - guidePointerProgress)
                            + 1 * guidePointerProgress
                    )
                    .scaleEffect(guidePressed ? 0.82 : 1)
            }
            .frame(width: 340, height: 205)

            Text("Switch input sources with one click.")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var guideCenterOnlySettingsScene: some View {
        VStack(spacing: 8) {
            ZStack {
                ZestV34CenterOnlyLanguageTurntable(
                    accentColor: settingsManager.accentColor,
                    accentBrightColor: settingsManager.accentBrightColor,
                    accentHighlightColor: settingsManager.accentHighlightColor,
                    accentDeepColor: settingsManager.accentDeepColor,
                    rearGlassPrimaryColor: settingsManager.rearGlassPrimaryColor,
                    rearGlassBrightColor: settingsManager.rearGlassBrightColor,
                    shortLabel: "EN",
                    sourceName: "English",
                    settingsPressed: guidePressed
                )
                .scaleEffect(1.72)

                // Starts above/right of the turntable and finishes on the exact
                // center gear, which is the production Settings button.
                guidePointer
                    .offset(
                        x: 98 * (1 - guidePointerProgress),
                        y: -70 * (1 - guidePointerProgress)
                    )
                    .scaleEffect(guidePressed ? 0.82 : 1)
            }
            .frame(width: 340, height: 205)

            Text("Click the center gear to open Settings.")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var guideSettingsScene: some View {
        ZStack {
            productionGuideZest.frame(width: 220, height: 170)

            if settingsManager.formFactor == .orangeSlice {
                // Tile 6 is the lower-left production slot. Keep the gear visible
                // in the tutorial even if the user's draft layout differs.
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.92))
                    .offset(x: -38, y: 43)
                    .scaleEffect(guidePressed ? 0.90 : 1)
            }

            guidePointer
                .offset(
                    x: settingsManager.formFactor == .orangeSlice
                        ? (28 - 66 * guidePointerProgress)
                        : (30 - 6 * guidePointerProgress),
                    y: settingsManager.formFactor == .orangeSlice
                        ? (-42 + 85 * guidePointerProgress)
                        : (-45 + 57 * guidePointerProgress)
                )
                .scaleEffect(guidePressed ? 0.84 : 1)
        }
        .overlay(alignment: .bottom) {
            Text((settingsManager.formFactor == .centerOnly || settingsManager.formFactor == .turntable) ? "Click the center gear to open Settings." : "Click the Settings tile to open Settings.")
                .font(.system(size: 13, weight: .semibold))
                .offset(y: 18)
        }
    }

    private var guideMenuBarScene: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 2) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.primary.opacity(0.075))
                        .frame(width: 650, height: 34)
                    HStack {
                        Text("   Zest   Edit   View")
                        Spacer()
                        ZestMenuBarGlyph(color: .primary).frame(width: 18, height: 18)
                            .scaleEffect(guidePressed ? 0.82 : 1)
                            .brightness(guidePressed ? 0.12 : 0)
                        Text("◉   100%   19:12")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 610)
                }

                ZestMenuBarSettingsPreview(
                    settingsManager: settingsManager,
                    blocks: .constant(settingsManager.menuBarBlocks),
                    pinnedFeatures: .constant(settingsManager.menuBarPinnedFeatures)
                )
                .scaleEffect(0.57, anchor: .top)
                .frame(width: 345, height: 205, alignment: .top)
                .offset(x: 172, y: -2)
                .opacity(guideDashboardVisible ? 1 : 0)
                .scaleEffect(guideDashboardVisible ? 1 : 0.90, anchor: .top)
            }
            .offset(y: -8)

            // Travel to the actual monochrome logo at the right side of the bar.
            guidePointer
                .offset(
                    x: 80 + 140 * guidePointerProgress,
                    y: 100 - 88 * guidePointerProgress
                )
                .scaleEffect(guidePressed ? 0.82 : 1)
        }
        .overlay(alignment: .bottom) {
            Text("Click the Zest menu bar icon to open your dashboard.")
                .font(.system(size: 13, weight: .semibold))
                .offset(y: 18)
        }
    }

    private var guideRapidInputScene: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                keyCap("⌃").scaleEffect(guideKeyRevealCount > 0 ? 1 : 0.7).opacity(guideKeyRevealCount > 0 ? 1 : 0)
                keyCap("⌥").scaleEffect(guideKeyRevealCount > 1 ? 1 : 0.7).opacity(guideKeyRevealCount > 1 ? 1 : 0)
                keyCap(guideHUDDirection > 0 ? "→" : "←").scaleEffect(guideKeyRevealCount > 2 ? 1 : 0.7).opacity(guideKeyRevealCount > 2 ? 1 : 0)
            }

            // Import the real production Saturn HUD instead of maintaining a
            // second approximation in onboarding. Only its presentation size is
            // reduced to fit the guide viewport.
            ZestSaturnHUDView(
                code: ["EN", "UA", "DE"][guideLanguageIndex % 3],
                name: ["English", "Ukrainian", "German"][guideLanguageIndex % 3],
                direction: guideHUDDirection,
                accent: settingsManager.accent
            )
            .id("guide-hud-\(guideLanguageIndex)-\(guideHUDDirection)-\(guideDemoPhase)")
            .scaleEffect(0.58)
            .frame(width: 170, height: 158)

            Text("Use ⌃⌥← / ⌃⌥→ to switch input sources instantly.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var guidePointer: some View { Image(systemName: "cursorarrow").font(.system(size: 24, weight: .semibold)).foregroundStyle(.primary).shadow(color: .black.opacity(0.25), radius: 3, y: 2) }
    private func keyCap(_ text: String) -> some View { Text(text).font(.system(size: 18, weight: .bold, design: .rounded)).frame(minWidth: 48, minHeight: 42).background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)).glassEffect(.regular.tint(accent.opacity(0.08)), in: RoundedRectangle(cornerRadius: 10))) }
    private func shortcutKeyCaps(_ text: String) -> some View { HStack(spacing: 7) { ForEach(Array(text).map(String.init), id: \.self) { keyCap($0) } } }

    private func runGuideAnimation(after initialDelay: Double = 0) {
        guideKeyRevealCount = 0
        guidePointerProgress = 0
        guidePressed = false
        guidePopupVisible = false
        guideSliderValue = 0
        guideDashboardVisible = false
        guideLanguageOpacity = 1
        let token = guideDemoPhase
        func later(_ t: Double, _ action: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay + t) {
                guard token == guideDemoPhase else { return }
                action()
            }
        }
        if reduceMotion {
            guideKeyRevealCount = 20
            guidePointerProgress = 1
            guidePopupVisible = true
            guideSliderValue = 0.62
            guideDashboardVisible = true
            guideLanguageIndex = 0
            guideLanguageRotation = 0
            guideLanguageOpacity = 1
            return
        }

        if settingsManager.formFactor == .centerOnly || settingsManager.formFactor == .turntable {
            if settingsManager.centerOnlyPage == "language" {
                runCenterOnlyGuideAnimation(later)
            } else {
                runCenterOnlySplitGuideAnimation(later)
            }
            return
        }

        if settingsManager.formFactor == .tripleSquare {
            runTripleGuideAnimation(later)
            return
        }

        switch guideStep {
        case 0:
            let n = settingsManager.showZestShortcut.displayString.count
            for i in 1...max(1,n) { later(0.10 * Double(i-1)) { withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) { guideKeyRevealCount = i } } }
            later(0.10 * Double(n) + 0.12) { withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { guideKeyRevealCount = n + 1 } }
        case 1:
            later(0.20) { withAnimation(.easeInOut(duration: 0.65)) { guidePointerProgress = 1 } }
            later(0.88) { withAnimation(.easeInOut(duration: 0.10)) { guidePressed = true } }
            later(1.02) { withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { guidePressed = false; guidePopupVisible = true } }
            later(1.35) { withAnimation(.easeOut(duration: 0.75)) { guideSliderValue = 0.62 } }
        case 2:
            if settingsManager.formFactor == .orangeSlice {
                // Keep all timing/state mutation outside guideScene. This mirrors the
                // production center-ring language transition: exit 54 degrees + fade,
                // swap the language, enter from the opposite side, settle at zero.
                guideLanguageIndex = 0
                guideLanguageRotation = 0
                guideLanguageOpacity = 1
                guideHUDDirection = 1
                later(0.28) { withAnimation(.easeInOut(duration: 0.58)) { guidePointerProgress = 1 } }
                later(0.78) { withAnimation(.easeInOut(duration: 0.10)) { guidePressed = true } }
                later(0.90) { withAnimation(.easeIn(duration: 0.10)) { guideLanguageRotation = 54; guideLanguageOpacity = 0 } }
                later(1.00) {
                    guidePressed = false
                    guideLanguageIndex = 1
                    guideLanguageRotation = -54
                    withAnimation(.easeOut(duration: 0.15)) { guideLanguageRotation = 0; guideLanguageOpacity = 1 }
                }
                later(1.42) { withAnimation(.easeInOut(duration: 0.46)) { guideHUDDirection = -1 } }
                later(1.96) { withAnimation(.easeInOut(duration: 0.10)) { guidePressed = true } }
                later(2.08) { withAnimation(.easeIn(duration: 0.10)) { guideLanguageRotation = -54; guideLanguageOpacity = 0 } }
                later(2.18) {
                    guidePressed = false
                    guideLanguageIndex = 0
                    guideLanguageRotation = 54
                    withAnimation(.easeOut(duration: 0.15)) { guideLanguageRotation = 0; guideLanguageOpacity = 1 }
                }
            } else {
                later(0.35) { withAnimation { guidePressed = true } }
                later(0.52) { withAnimation { guidePressed = false } }
            }
        case 3:
            // Menu-bar dashboard. One continuous pointer flight, one Step-2-style
            // press/release, then reveal the dashboard. No competing animation run.
            later(0.18) { withAnimation(.easeInOut(duration: 0.82)) { guidePointerProgress = 1 } }
            later(1.04) { withAnimation(.easeInOut(duration: 0.10)) { guidePressed = true } }
            later(1.18) { withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { guidePressed = false; guideDashboardVisible = true } }
        case 4:
            runRapidGuide(later)
        default:
            runRapidGuide(later)
        }
    }


    private func runTripleGuideAnimation(
        _ later: (Double, @escaping () -> Void) -> Void
    ) {
        switch guideStep {
        case 0:
            let n = settingsManager.showZestShortcut.displayString.count
            for i in 1...max(1, n) {
                later(0.10 * Double(i - 1)) {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                        guideKeyRevealCount = i
                    }
                }
            }
            later(0.10 * Double(n) + 0.12) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    guideKeyRevealCount = n + 1
                }
            }

        case 1:
            later(0.20) {
                withAnimation(.easeInOut(duration: 0.68)) {
                    guidePointerProgress = 1
                }
            }
            later(0.90) {
                withAnimation(.easeInOut(duration: 0.10)) {
                    guidePressed = true
                }
            }
            later(1.04) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    guidePressed = false
                    guidePopupVisible = true
                }
            }
            later(1.34) {
                withAnimation(.easeOut(duration: 0.75)) {
                    guideSliderValue = 0.62
                }
            }

        case 2:
            later(0.22) {
                withAnimation(.easeInOut(duration: 0.72)) {
                    guidePointerProgress = 1
                }
            }
            later(0.98) {
                withAnimation(.easeInOut(duration: 0.10)) {
                    guidePressed = true
                }
            }
            later(1.12) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    guidePressed = false
                }
            }

        case 3:
            later(0.18) {
                withAnimation(.easeInOut(duration: 0.82)) {
                    guidePointerProgress = 1
                }
            }
            later(1.04) {
                withAnimation(.easeInOut(duration: 0.10)) {
                    guidePressed = true
                }
            }
            later(1.18) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    guidePressed = false
                    guideDashboardVisible = true
                }
            }

        case 4:
            runRapidGuide(later)

        default:
            break
        }
    }

    private func runCenterOnlySplitGuideAnimation(
        _ later: (Double, @escaping () -> Void) -> Void
    ) {
        switch guideStep {
        case 0:
            // Summon: same keycap dissolve/enlarge sequence as the other
            // production guides, followed by the actual selected 2/4 Split.
            let n = settingsManager.showZestShortcut.displayString.count
            for i in 1...max(1, n) {
                later(0.10 * Double(i - 1)) {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                        guideKeyRevealCount = i
                    }
                }
            }
            later(0.10 * Double(n) + 0.12) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    guideKeyRevealCount = n + 1
                }
            }

        case 1:
            // Feature tile -> popup. Pointer lands on the real top sector,
            // presses that production sector, then the popup and slider animate.
            later(0.20) {
                withAnimation(.easeInOut(duration: 0.68)) { guidePointerProgress = 1 }
            }
            later(0.90) {
                withAnimation(.easeInOut(duration: 0.10)) { guidePressed = true }
            }
            later(1.04) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    guidePressed = false
                    guidePopupVisible = true
                }
            }
            later(1.34) {
                withAnimation(.easeOut(duration: 0.75)) { guideSliderValue = 0.62 }
            }

        case 2:
            // Settings: land exactly on the real center gear and use the same
            // press/release rhythm as the feature click.
            later(0.22) {
                withAnimation(.easeInOut(duration: 0.72)) { guidePointerProgress = 1 }
            }
            later(0.98) {
                withAnimation(.easeInOut(duration: 0.10)) { guidePressed = true }
            }
            later(1.12) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    guidePressed = false
                }
            }

        case 3:
            // Reuse the production menu-bar lesson unchanged.
            later(0.18) {
                withAnimation(.easeInOut(duration: 0.82)) { guidePointerProgress = 1 }
            }
            later(1.04) {
                withAnimation(.easeInOut(duration: 0.10)) { guidePressed = true }
            }
            later(1.18) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    guidePressed = false
                    guideDashboardVisible = true
                }
            }

        case 4:
            runRapidGuide(later)

        default:
            break
        }
    }

    private func runCenterOnlyGuideAnimation(
        _ later: (Double, @escaping () -> Void) -> Void
    ) {
        switch guideStep {
        case 0:
            // Language Turntable: use exactly the production 54° exit / entry
            // animation while the pointer physically travels between the real
            // shared chevron buttons.
            guideLanguageIndex = 0
            guideLanguageRotation = 0
            guideLanguageOpacity = 1
            guideHUDDirection = 1

            later(0.24) {
                withAnimation(.easeInOut(duration: 0.62)) {
                    guidePointerProgress = 1
                }
            }
            later(0.82) {
                withAnimation(.easeInOut(duration: 0.10)) {
                    guidePressed = true
                }
            }
            later(0.94) {
                withAnimation(.easeIn(duration: 0.10)) {
                    guideLanguageRotation = 54
                    guideLanguageOpacity = 0
                }
            }
            later(1.04) {
                guidePressed = false
                guideLanguageIndex = 1
                guideLanguageRotation = -54
                withAnimation(.easeOut(duration: 0.15)) {
                    guideLanguageRotation = 0
                    guideLanguageOpacity = 1
                }
            }

            later(1.52) {
                withAnimation(.easeInOut(duration: 0.64)) {
                    guideHUDDirection = -1
                }
            }
            later(2.18) {
                withAnimation(.easeInOut(duration: 0.10)) {
                    guidePressed = true
                }
            }
            later(2.30) {
                withAnimation(.easeIn(duration: 0.10)) {
                    guideLanguageRotation = -54
                    guideLanguageOpacity = 0
                }
            }
            later(2.40) {
                guidePressed = false
                guideLanguageIndex = 0
                guideLanguageRotation = 54
                withAnimation(.easeOut(duration: 0.15)) {
                    guideLanguageRotation = 0
                    guideLanguageOpacity = 1
                }
            }

        case 1:
            // Settings: pointer lands on the production center gear. No popup
            // lesson exists for this form factor.
            later(0.22) {
                withAnimation(.easeInOut(duration: 0.72)) {
                    guidePointerProgress = 1
                }
            }
            later(0.98) {
                withAnimation(.easeInOut(duration: 0.10)) {
                    guidePressed = true
                }
            }
            later(1.12) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    guidePressed = false
                }
            }

        case 2:
            // Menu bar dashboard: same production dashboard lesson used by the
            // other form factors.
            later(0.18) {
                withAnimation(.easeInOut(duration: 0.82)) {
                    guidePointerProgress = 1
                }
            }
            later(1.04) {
                withAnimation(.easeInOut(duration: 0.10)) {
                    guidePressed = true
                }
            }
            later(1.18) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    guidePressed = false
                    guideDashboardVisible = true
                }
            }

        case 3:
            runRapidGuide(later)

        default:
            runRapidGuide(later)
        }
    }

    private func runRapidGuide(_ later: (Double, @escaping () -> Void) -> Void) {
        guideLanguageIndex = 0; guideLanguageRotation = 0; guideHUDDirection = 1
        for i in 1...3 { later(0.10 * Double(i-1)) { withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) { guideKeyRevealCount = i } } }
        later(0.55) { withAnimation(.spring(response: 0.48, dampingFraction: 0.74)) { guideLanguageRotation += 120; guideLanguageIndex = 1 } }
        later(1.35) { guideHUDDirection = -1; guideKeyRevealCount = 0 }
        for i in 1...3 { later(1.45 + 0.10 * Double(i-1)) { withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) { guideKeyRevealCount = i } } }
        later(1.90) { withAnimation(.spring(response: 0.48, dampingFraction: 0.74)) { guideLanguageRotation -= 120; guideLanguageIndex = 0 } }
        later(2.55) { withAnimation(.spring(response: 0.48, dampingFraction: 0.74)) { guideLanguageRotation -= 120; guideLanguageIndex = 2 } }
        later(3.25) { guideHUDDirection = 1; guideKeyRevealCount = 0 }
        for i in 1...3 { later(3.35 + 0.10 * Double(i-1)) { withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) { guideKeyRevealCount = i } } }
        later(3.82) { withAnimation(.spring(response: 0.48, dampingFraction: 0.74)) { guideLanguageRotation += 120; guideLanguageIndex = 0 } }
    }

    private var complete: some View {
        VStack(spacing: 24) {
            Spacer(); onboardingZest(scale: 1.25)
            onboardingHeader("Zest is ready.", "Press \(settingsManager.showZestShortcut.displayString) anytime to bring it up.")
            HStack(spacing: 12) {
                Button("Open Settings") {
                    finishOnboarding(openSettingsAfter: true)
                }
                .buttonStyle(ZestOnboardingSecondaryButton())

                Button("Start Using Zest  →") {
                    finishOnboarding(openSettingsAfter: false)
                }
                .buttonStyle(ZestOnboardingPrimaryButton(accent: accent))
            }; Spacer()
        }
    }

    private func finishOnboarding(openSettingsAfter: Bool) {
        settingsManager.completeOnboarding()
        ZestPostUpdateTracker.shared.acknowledgeCurrentBuild()
        close()

        if openSettingsAfter {
            openSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                focusSettingsWindow()
            }
        }

        Task { @MainActor in
            let notifications = ZestNotificationService.shared
            await notifications.presentLaunchPermissionExplanationIfNeeded()
            if settingsManager.notifyWhenZestStarts {
                await notifications.deliverLaunchNotification()
            }
        }
    }

    private var onboardingAbortOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.12))
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Quit onboarding?")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Text("Your onboarding setup is not complete. If you quit now, Zest will ask you to finish setup the next time it opens.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 390)
                HStack(spacing: 10) {
                    Button("Keep Setting Up") {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) { showAbortConfirmation = false }
                    }
                    .buttonStyle(ZestOnboardingSecondaryButton())
                    Button("Quit Zest") { NSApp.terminate(nil) }
                        .buttonStyle(ZestOnboardingDestructiveButton())
                }
            }
            .padding(30)
            .frame(width: 500)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.regularMaterial)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.20), radius: 30, y: 14)
        }
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        if navigationDirection < 0 {
            // Back navigation must read spatially as going to the previous page:
            // previous content enters from the LEFT, current content exits RIGHT.
            return .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .leading)),
                removal: .opacity.combined(with: .move(edge: .trailing))
            )
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        )
    }

    private func next() {
        if page == 3 { settingsManager.showZestShortcut = shortcutDraft }
        if page == 6 { NotificationCenter.default.post(name: .zestOnboardingCommitLayout, object: nil) }
        navigationDirection = 1
        withAnimation(reduceMotion ? nil : ZestOnboardingMotion.page) { page = min(page + 1, 8) }
    }
    private func onboardingHeader(_ title: String, _ subtitle: String) -> some View { VStack(spacing: 7) { Text(title).font(.system(size: 28, weight: .bold, design: .rounded)).multilineTextAlignment(.center); Text(subtitle).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 650) } }
    private func featureCard(_ title: String, _ text: String, _ symbol: String) -> some View { VStack(alignment: .leading, spacing: 12) { Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(accent); Text(title).font(.system(size: 14, weight: .bold)); Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true); Spacer() }.padding(18).frame(width: 245, height: 170).background(RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.025)).glassEffect(.regular.tint(accent.opacity(0.045)), in: RoundedRectangle(cornerRadius: 20))) }
    private func permissionRow(
        _ title: String,
        _ detail: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 22))
                .foregroundStyle(granted ? accent : .secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .bold))
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(granted ? "Allowed" : actionTitle, action: action)
                .buttonStyle(.bordered)
                .disabled(granted)
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.025))
        )
    }

    private enum RevealKind { case features, permissions, forms }
    private func runStaggeredReveal(kind: RevealKind) {
        if reduceMotion { featureRevealCount = 4; permissionRevealCount = 3; formRevealCount = ZestFormFactor.allCases.count; return }
        switch kind {
        case .features:
            featureRevealCount = 0
            for i in 1...4 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.10 * Double(i - 1)) { withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { featureRevealCount = i } } }
        case .permissions:
            permissionRevealCount = 0
            for i in 1...3 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.10 * Double(i - 1)) { withAnimation(.spring(response: 0.34, dampingFraction: 0.80)) { permissionRevealCount = i } } }
        case .forms:
            formRevealCount = 0
            for i in 1...ZestFormFactor.allCases.count { DispatchQueue.main.asyncAfter(deadline: .now() + 0.10 * Double(i - 1)) { withAnimation(.spring(response: 0.34, dampingFraction: 0.80)) { formRevealCount = i } } }
        }
    }

    private func revealFeatureCard(_ index: Int, _ title: String, _ text: String, _ symbol: String) -> some View {
        featureCard(title, text, symbol)
            .opacity(featureRevealCount > index ? 1 : 0)
            .scaleEffect(featureRevealCount > index ? 1 : 0.88)
    }

    private func productionMiniSlice(scale: CGFloat) -> some View {
        ZestV34MiniSlicePreview(accentColor: accent, accentHighlightColor: settingsManager.accentHighlightColor, accentDeepColor: settingsManager.accentDeepColor)
            .scaleEffect(scale)
            .frame(width: 90 * scale, height: 90 * scale)
    }

    @ViewBuilder private func productionFormPreview(_ factor: ZestFormFactor) -> some View {
        switch factor {
        case .orangeSlice: productionMiniSlice(scale: 1.0)
        case .centerOnly: productionMiniCenterPreview
        case .turntable: productionMiniTurntablePreview
        case .tripleSquare: productionMiniTriplePreview
        }
    }

    private var productionMiniCenterPreview: some View {
        ZestV34CenterOnlyTopThreeView(
            features: [.clipboard, .emoji, .symbols],
            featureColors: [accent, accent, accent],
            displayKind: .clock,
            accentColor: settingsManager.accentColor,
            accentBrightColor: settingsManager.accentBrightColor,
            accentHighlightColor: settingsManager.accentHighlightColor,
            accentDeepColor: settingsManager.accentDeepColor,
            diameter: 74
        )
        .allowsHitTesting(false)
        .frame(width: 104, height: 88)
    }

    private var productionMiniTurntablePreview: some View {
        ZestV34CenterOnlyLanguageTurntable(
            accentColor: settingsManager.accentColor,
            accentBrightColor: settingsManager.accentBrightColor,
            accentHighlightColor: settingsManager.accentHighlightColor,
            accentDeepColor: settingsManager.accentDeepColor,
            rearGlassPrimaryColor: settingsManager.rearGlassPrimaryColor,
            rearGlassBrightColor: settingsManager.rearGlassBrightColor,
            shortLabel: "EN",
            sourceName: "ABC"
        )
        .scaleEffect(0.58)
        .allowsHitTesting(false)
        .frame(width: 104, height: 88)
    }


    private var productionMiniTriplePreview: some View {
        productionTripleControl()
            .scaleEffect(0.66)
            .frame(width: 154, height: 88)
    }


    @ViewBuilder private var productionGuideZest: some View {
        switch settingsManager.formFactor {
        case .orangeSlice: productionMiniSlice(scale: 1.65)
        case .centerOnly: productionMiniCenterPreview.scaleEffect(1.35)
        case .turntable: productionMiniTurntablePreview.scaleEffect(1.35)
        case .tripleSquare: productionMiniTriplePreview.scaleEffect(1.18)
        }
    }

    private var onboardingDashboardPreview: some View {
        VStack(spacing: 9) {
            HStack { ZestMenuBarGlyph(color: accent).frame(width: 26, height: 26); Text("Zest").font(.system(size: 13, weight: .bold)); Spacer() }
            HStack(spacing: 7) { ForEach(["internaldrive", "memorychip", "cpu"], id: \.self) { Image(systemName: $0).frame(width: 54, height: 42).background(RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.10))) } }
            HStack(spacing: 6) { ForEach(settingsManager.menuBarPinnedFeatures.prefix(5)) { f in Image(systemName: f.systemImage).frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.12))) } }
            HStack(spacing: 7) { ForEach(["gearshape", "ladybug", "arrow.clockwise", "power"], id: \.self) { Image(systemName: $0).font(.system(size: 9)).frame(width: 38, height: 25).background(Capsule().fill(Color.primary.opacity(0.05))) } }
        }.padding(12).frame(width: 260).background(RoundedRectangle(cornerRadius: 20).fill(.regularMaterial).glassEffect(.regular.tint(accent.opacity(0.10)), in: RoundedRectangle(cornerRadius: 20)))
    }

    private func onboardingWelcomeZest(scale: CGFloat) -> some View {
        ZestWelcomeHeroAnimation(
            accent: onboardingAccentChoice,
            assembled: assembled,
            centerPowered: heroCenterPowered,
            centerShineProgress: heroCenterShineProgress,
            reduceMotion: reduceMotion,
            scale: scale
        )
    }

    private func onboardingZest(scale: CGFloat) -> some View {
        ZStack {
            Circle().fill(accent.opacity(0.12)).frame(width: 142 * scale, height: 142 * scale).shadow(color: .black.opacity(0.16), radius: 10 * scale, y: 5 * scale)
            ForEach(0..<6) { i in
                Circle().trim(from: CGFloat(i)/6 + 0.008, to: CGFloat(i+1)/6 - 0.008).stroke(onboardingAccentChoice.displayColors[i % onboardingAccentChoice.displayColors.count], style: StrokeStyle(lineWidth: 34 * scale)).rotationEffect(.degrees(-90)).frame(width: 100 * scale, height: 100 * scale)
            }
            Circle().fill(.thinMaterial).frame(width: 48 * scale, height: 48 * scale).overlay(Text("EN").font(.system(size: 13 * scale, weight: .bold)))
        }.frame(width: 165 * scale, height: 165 * scale)
    }
}

struct ZestOnboardingSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .frame(height: 38)
            .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.09 : 0.045)))
            .overlay(Capsule().stroke(Color.white.opacity(0.28), lineWidth: 0.7))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct ZestOnboardingDestructiveButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 38)
            .background(Capsule().fill(Color.red.opacity(configuration.isPressed ? 0.70 : 0.88)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct ZestOnboardingPrimaryButton: ButtonStyle {
    let accent: Color
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 12, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 20).frame(height: 38).background(Capsule().fill(accent.opacity(configuration.isPressed ? 0.68 : 0.90))).scaleEffect(configuration.isPressed ? 0.97 : 1) }
}

@MainActor
func focusSettingsWindow() {
    NSApp.activate(ignoringOtherApps: true)
    if let window = NSApp.windows.first(where: { window in
        let id = window.identifier?.rawValue.lowercased() ?? ""
        let title = window.title.lowercased()
        return id.contains("settings") || title.contains("settings") || String(describing: type(of: window.contentViewController)).lowercased().contains("settings")
    }) {
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
    }
}
