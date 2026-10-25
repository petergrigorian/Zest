//
//  ZestSettingsManager.swift
//  Zest
//
//  Persistent settings model for Zest.
//

import SwiftUI
import AppKit
import Combine


// MARK: - Accent Color

struct ZestAccentPalette {

    let primary: Color
    let bright: Color
    let highlight: Color
    let deep: Color
}


enum ZestAccent:
    String,
    CaseIterable,
    Identifiable,
    Codable {

    case orange
    case amber
    case red
    case pink
    case purple
    case blue
    case cyan
    case green
    case graphite
    case silver
    case unicorn
    case rainbow
    case landscape
    case aqua


    var id: String {
        rawValue
    }


    var title: String {

        switch self {

        case .orange:
            return "Orange"

        case .amber:
            return "Amber"

        case .red:
            return "Red"

        case .pink:
            return "Strawberry"

        case .purple:
            return "Purple"

        case .blue:
            return "Blueberry"

        case .cyan:
            return "Sea Foam"

        case .green:
            return "Moss"

        case .graphite:
            return "Graphite"

        case .silver:
            return "Silver"

        case .unicorn:
            return "Unicorn"

        case .rainbow:
            return "Rainbow"

        case .landscape:
            return "Landscape"

        case .aqua:
            return "Aqua"
        }
    }


    var palette: ZestAccentPalette {

        switch self {

        case .orange:
            return ZestAccentPalette(
                primary: Color(red: 1.00, green: 0.35, blue: 0.01),
                bright: Color(red: 1.00, green: 0.59, blue: 0.035),
                highlight: Color(red: 1.00, green: 0.76, blue: 0.11),
                deep: Color(red: 0.82, green: 0.25, blue: 0.01)
            )

        case .amber:
            return ZestAccentPalette(
                primary: Color(red: 1.00, green: 0.64, blue: 0.02),
                bright: Color(red: 1.00, green: 0.78, blue: 0.05),
                highlight: Color(red: 1.00, green: 0.90, blue: 0.28),
                deep: Color(red: 0.76, green: 0.40, blue: 0.00)
            )

        case .red:
            return ZestAccentPalette(
                primary: Color(red: 0.96, green: 0.08, blue: 0.20),
                bright: Color(red: 1.00, green: 0.20, blue: 0.30),
                highlight: Color(red: 1.00, green: 0.43, blue: 0.48),
                deep: Color(red: 0.60, green: 0.015, blue: 0.10)
            )

        case .pink:
            return ZestAccentPalette(
                primary: Color(red: 0.96, green: 0.20, blue: 0.46),
                bright: Color(red: 1.00, green: 0.36, blue: 0.58),
                highlight: Color(red: 1.00, green: 0.58, blue: 0.72),
                deep: Color(red: 0.66, green: 0.07, blue: 0.29)
            )

        case .purple:
            return ZestAccentPalette(
                primary: Color(red: 0.53, green: 0.18, blue: 0.92),
                bright: Color(red: 0.68, green: 0.30, blue: 1.00),
                highlight: Color(red: 0.80, green: 0.52, blue: 1.00),
                deep: Color(red: 0.31, green: 0.06, blue: 0.62)
            )

        case .blue:
            return ZestAccentPalette(
                primary: Color(red: 0.16, green: 0.34, blue: 0.94),
                bright: Color(red: 0.25, green: 0.52, blue: 1.00),
                highlight: Color(red: 0.48, green: 0.70, blue: 1.00),
                deep: Color(red: 0.055, green: 0.16, blue: 0.62)
            )

        case .cyan:
            return ZestAccentPalette(
                primary: Color(red: 0.08, green: 0.70, blue: 0.67),
                bright: Color(red: 0.13, green: 0.84, blue: 0.79),
                highlight: Color(red: 0.42, green: 0.94, blue: 0.86),
                deep: Color(red: 0.025, green: 0.43, blue: 0.43)
            )

        case .green:
            return ZestAccentPalette(
                primary: Color(red: 0.30, green: 0.52, blue: 0.18),
                bright: Color(red: 0.43, green: 0.66, blue: 0.24),
                highlight: Color(red: 0.63, green: 0.78, blue: 0.40),
                deep: Color(red: 0.16, green: 0.32, blue: 0.09)
            )

        case .graphite:
            return ZestAccentPalette(
                primary: Color(red: 0.34, green: 0.36, blue: 0.39),
                bright: Color(red: 0.48, green: 0.50, blue: 0.54),
                highlight: Color(red: 0.68, green: 0.70, blue: 0.73),
                deep: Color(red: 0.16, green: 0.17, blue: 0.19)
            )

        case .silver:
            return ZestAccentPalette(
                primary: Color(red: 0.62, green: 0.65, blue: 0.69),
                bright: Color(red: 0.75, green: 0.78, blue: 0.82),
                highlight: Color(red: 0.90, green: 0.92, blue: 0.94),
                deep: Color(red: 0.36, green: 0.39, blue: 0.43)
            )

        case .unicorn:
            // Keep the pastel character, but move the palette farther away
            // from white so the glass retains visible color and depth.
            return ZestAccentPalette(
                primary: Color(red: 0.48, green: 0.60, blue: 0.98),
                bright: Color(red: 0.94, green: 0.43, blue: 0.76),
                highlight: Color(red: 0.98, green: 0.78, blue: 0.30),
                deep: Color(red: 0.34, green: 0.24, blue: 0.66)
            )

        case .rainbow:
            return ZestAccentPalette(
                primary: Color(red: 0.36, green: 0.50, blue: 1.00),
                bright: Color(red: 0.98, green: 0.32, blue: 0.55),
                highlight: Color(red: 1.00, green: 0.80, blue: 0.20),
                deep: Color(red: 0.35, green: 0.18, blue: 0.62)
            )

        case .landscape:
            return ZestAccentPalette(
                primary: Color(red: 0.08, green: 0.43, blue: 0.96),
                bright: Color(red: 0.20, green: 0.62, blue: 1.00),
                highlight: Color(red: 1.00, green: 0.82, blue: 0.12),
                deep: Color(red: 0.035, green: 0.20, blue: 0.58)
            )

        case .aqua:
            // Classic Mac OS X Aqua: a saturated cobalt/cyan body with a
            // bright watery crown and a distinctly darker lower edge.
            return ZestAccentPalette(
                primary: Color(red: 0.10, green: 0.48, blue: 0.94),
                bright: Color(red: 0.16, green: 0.68, blue: 1.00),
                highlight: Color(red: 0.66, green: 0.88, blue: 1.00),
                deep: Color(red: 0.035, green: 0.16, blue: 0.55)
            )
        }
    }


    var color: Color {
        palette.primary
    }

    /// Colors used when a theme is intentionally multi-color. Single-color
    /// accents keep their familiar highlight/primary/deep rendering.
    var displayColors: [Color] {
        switch self {
        case .unicorn:
            return [
                Color(red: 0.96, green: 0.43, blue: 0.76),
                Color(red: 0.48, green: 0.63, blue: 1.00),
                Color(red: 0.38, green: 0.84, blue: 0.62),
                Color(red: 0.98, green: 0.78, blue: 0.30)
            ]
        case .rainbow:
            return [.red, .orange, .yellow, .green, .cyan, .blue, .purple]
        case .landscape:
            return [
                Color(red: 0.08, green: 0.43, blue: 0.96),
                Color(red: 0.20, green: 0.62, blue: 1.00),
                Color(red: 1.00, green: 0.82, blue: 0.12),
                Color(red: 1.00, green: 0.68, blue: 0.05)
            ]
        case .aqua:
            // Aqua is intentionally NOT distributed per tile. These stops are
            // for swatches/HUD gradients; all foreground controls use primary.
            return [
                Color(red: 0.72, green: 0.91, blue: 1.00),
                Color(red: 0.20, green: 0.68, blue: 1.00),
                Color(red: 0.10, green: 0.48, blue: 0.94),
                Color(red: 0.035, green: 0.16, blue: 0.55)
            ]
        default:
            return [palette.highlight, palette.primary, palette.deep]
        }
    }

    var isColorScheme: Bool {
        switch self {
        case .unicorn, .rainbow, .landscape, .aqua: return true
        default: return false
        }
    }
}


// MARK: - Form Factor

enum ZestFormFactor:
    String,
    CaseIterable,
    Identifiable,
    Codable {

    case centerOnly
    case orangeSlice
    case tripleSquare


    var id: String {
        rawValue
    }


    var title: String {

        switch self {

        case .centerOnly:
            return "Center Only"

        case .orangeSlice:
            return "Orange Slice"

        case .tripleSquare:
            return "Triple Square"
        }
    }


    var subtitle: String {

        switch self {

        case .centerOnly:
            return "Compact input control"

        case .orangeSlice:
            return "Classic Zest layout"

        case .tripleSquare:
            return "Three customizable controls"
        }
    }
}


// MARK: - Menu Bar Dashboard Structure

enum ZestMenuBarBlock: String, CaseIterable, Identifiable, Codable {
    case monitors
    case pinnedActions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monitors: return "Monitors"
        case .pinnedActions: return "Pinned Actions"
        }
    }

    var systemImage: String {
        switch self {
        case .monitors: return "waveform.path.ecg"
        case .pinnedActions: return "square.grid.3x1.folder.badge.plus"
        }
    }
}


// MARK: - Assignable Features

enum ZestFeature:
    String,
    CaseIterable,
    Identifiable,
    Codable {

    case size
    case font
    case clipboard
    case emoji
    case symbols
    case settings

    // Configurable action tiles.
    case openShortcut
    case runShortcut
    case empty


    var id: String {
        rawValue
    }


    var title: String {

        switch self {

        case .size:
            return "Size"

        case .font:
            return "Font"

        case .clipboard:
            return "Clipboard"

        case .emoji:
            return "Emoji"

        case .symbols:
            return "Symbols"

        case .settings:
            return "Settings"

        case .openShortcut:
            return "Application"

        case .runShortcut:
            return "Shortcut"
        case .empty:
            return ""
        }
    }


    var paletteSubtitle: String {

        switch self {
        case .size:
            return "Text size"
        case .font:
            return "Font & style"
        case .clipboard:
            return "Recent copies"
        case .emoji:
            return "Emoji picker"
        case .symbols:
            return "Symbols"
        case .settings:
            return "Zest controls"
        case .openShortcut:
            return "Open an app"
        case .runShortcut:
            return "Run an action"
        case .empty:
            return ""
        }
    }


    var systemImage: String {

        switch self {

        case .size:
            return "textformat.size"

        case .font:
            return "textformat"

        case .clipboard:
            return "clipboard"

        case .emoji:
            return "face.smiling"

        case .symbols:
            return "text.and.command.interface.window"

        case .settings:
            return "gearshape"

        case .openShortcut:
            return "arrow.up.forward.app"

        case .runShortcut:
            return "play.fill"
        case .empty:
            return "circle.dashed"
        }
    }
}


// MARK: - Configurable Action Targets

struct ZestApplicationTarget: Codable, Equatable {
    var name: String
    var bundleIdentifier: String?
    var path: String
}

struct ZestShortcutTarget: Codable, Equatable {
    var name: String
}


// MARK: - Slice Slot

enum ZestSliceSlot:
    Int,
    CaseIterable,
    Identifiable,
    Codable {

    case slot2 = 2
    case slot3 = 3
    case slot4 = 4
    case slot5 = 5
    case slot6 = 6
    case slot7 = 7


    var id: Int {
        rawValue
    }


    var title: String {
        "Slot \(rawValue)"
    }
}


// MARK: - Shortcut Model

struct ZestKeyboardShortcut:
    Codable,
    Equatable {

    var keyCode: UInt16

    var command: Bool
    var option: Bool
    var control: Bool
    var shift: Bool


    // Factory summon shortcut: ⇧⌃Z
    static let defaultShowZest =
        ZestKeyboardShortcut(
            keyCode: 6,
            command: false,
            option: false,
            control: true,
            shift: true
        )


    var modifierDescription: String {

        var value = ""


        if control {
            value += "⌃"
        }


        if option {
            value += "⌥"
        }


        if shift {
            value += "⇧"
        }


        if command {
            value += "⌘"
        }


        return value
    }


    var keyDescription: String {
        // macOS virtual key codes. Keeping the display map here means the
        // recorder can show real key names instead of opaque “Key 7” labels.
        let names: [UInt16: String] = [
            0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V",
            11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 18:"1", 19:"2",
            20:"3", 21:"4", 22:"6", 23:"5", 24:"=", 25:"9", 26:"7", 27:"-", 28:"8", 29:"0",
            30:"]", 31:"O", 32:"U", 33:"[", 34:"I", 35:"P", 36:"Return", 37:"L", 38:"J", 39:"'",
            40:"K", 41:";", 42:"\\", 43:",", 44:"/", 45:"N", 46:"M", 47:".", 48:"Tab", 49:"Space",
            50:"`", 51:"Delete", 53:"Esc", 65:".", 67:"*", 69:"+", 71:"Clear", 75:"/", 76:"Enter",
            78:"-", 81:"=", 82:"0", 83:"1", 84:"2", 85:"3", 86:"4", 87:"5", 88:"6", 89:"7",
            91:"8", 92:"9", 96:"F5", 97:"F6", 98:"F7", 99:"F3", 100:"F8", 101:"F9",
            103:"F11", 109:"F10", 111:"F12", 115:"Home", 116:"Page Up", 117:"Forward Delete",
            118:"F4", 119:"End", 120:"F2", 121:"Page Down", 122:"F1", 123:"←", 124:"→", 125:"↓", 126:"↑"
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }


    var displayString: String {
        modifierDescription
        + keyDescription
    }
}


// MARK: - Settings Manager

@MainActor
final class ZestSettingsManager:
    ObservableObject {

    // MARK: Published Settings

    @Published
    var accent: ZestAccent {
        didSet {
            save()
        }
    }


    @Published
    var formFactor: ZestFormFactor {
        didSet {
            save()
        }
    }


    // Center Only has three layouts: language, twoFeature and fourFeature.
    @Published
    var centerOnlyPage: String {
        didSet { save() }
    }

    @Published
    var centerOnlyTwoFeatures: [ZestFeature] {
        didSet { save() }
    }

    @Published
    var centerOnlyFourFeatures: [ZestFeature] {
        didSet { save() }
    }

    @Published
    var tripleFeatures: [ZestFeature] {
        didSet { save() }
    }

    // Master switch for Zest's persistent menu-bar presence.
    @Published
    var showInMenuBar: Bool {
        didSet { saveBoolImmediately(showInMenuBar, key: Key.showInMenuBar) }
    }

    // Structural blocks shown in the menu-bar dashboard. Their order is the
    // order rendered in the widget; either block may be omitted.
    @Published
    var menuBarBlocks: [ZestMenuBarBlock] {
        didSet { save() }
    }

    // Five quick-access features shown when the Pinned Actions block is present.
    @Published
    var menuBarPinnedFeatures: [ZestFeature] {
        didSet { save() }
    }

    // Rapid Input Source Switching can be used with every form factor.
    // When Center Only / Language Switcher is visible, the same shortcuts
    // animate the Saturn UI as they switch the actual macOS input source.
    @Published var rapidInputSourceSwitching: Bool {
        didSet { saveBoolImmediately(rapidInputSourceSwitching, key: Key.rapidInputSourceSwitching) }
    }
    @Published var saturnPreviousShortcut: ZestKeyboardShortcut { didSet { saveShortcutImmediately(saturnPreviousShortcut, key: Key.saturnPreviousShortcut) } }
    @Published var saturnNextShortcut: ZestKeyboardShortcut { didSet { saveShortcutImmediately(saturnNextShortcut, key: Key.saturnNextShortcut) } }


    @Published
    var sliceAssignments:
        [ZestSliceSlot: ZestFeature] {

        didSet {
            save()
        }
    }


    @Published
    var applicationTargets:
        [ZestSliceSlot: ZestApplicationTarget] {
        didSet { save() }
    }

    @Published
    var shortcutTargets:
        [ZestSliceSlot: ZestShortcutTarget] {
        didSet { save() }
    }

    @Published var centerApplicationTargets: [String: ZestApplicationTarget] { didSet { save() } }
    @Published var centerShortcutTargets: [String: ZestShortcutTarget] { didSet { save() } }


    @Published
    var showZestShortcut:
        ZestKeyboardShortcut {

        didSet {
            saveShortcutImmediately(showZestShortcut, key: Key.showZestShortcut)
        }
    }


    @Published
    var hasCompletedOnboarding: Bool {
        didSet { saveBoolImmediately(hasCompletedOnboarding, key: Key.hasCompletedOnboarding) }
    }

    @Published
    var launchAtLogin:
        Bool {

        didSet {
            save()
        }
    }


    // MARK: Convenience

    var accentColor: Color {
        accent.palette.primary
    }


    var accentBrightColor: Color {
        accent.palette.bright
    }


    var accentHighlightColor: Color {
        accent.palette.highlight
    }


    var accentDeepColor: Color {
        accent.palette.deep
    }


    /// Returns a stable per-piece color for multi-color schemes while keeping
    /// legacy accents monochromatic. This lets existing rendering code remain
    /// compatible and lets tiles opt into richer themes incrementally.
    func accentColor(at index: Int) -> Color {
        // Classic Aqua buttons are one consistent blue material. Unlike
        // Rainbow/Unicorn/Landscape, Aqua's variation belongs inside each
        // button's glossy shading rather than between neighboring buttons.
        if accent == .aqua { return accent.palette.primary }

        guard accent.isColorScheme else { return accent.palette.primary }
        let colors = accent.displayColors
        return colors[((index % colors.count) + colors.count) % colors.count]
    }


    /// Rear support glass is silver/graphite in Aqua, matching the chrome-like
    /// window and bezel materials of classic Mac OS X. Other themes continue
    /// to derive their support glass from their accent.
    var rearGlassPrimaryColor: Color {
        accent == .aqua
            ? Color(red: 0.64, green: 0.68, blue: 0.74)
            : accent.palette.primary
    }

    var rearGlassBrightColor: Color {
        accent == .aqua
            ? Color(red: 0.82, green: 0.85, blue: 0.89)
            : accent.palette.bright
    }

    var rearGlassHighlightColor: Color {
        accent == .aqua
            ? Color(red: 0.96, green: 0.97, blue: 0.985)
            : accent.palette.highlight
    }

    var rearGlassDeepColor: Color {
        accent == .aqua
            ? Color(red: 0.34, green: 0.38, blue: 0.44)
            : accent.palette.deep
    }


    // MARK: Storage

    private let defaults:
        UserDefaults


    private enum Key {

        static let accent =
            "zest.settings.accent"

        static let formFactor =
            "zest.settings.formFactor"

        static let centerOnlyPage =
            "zest.settings.centerOnlyPage"

        static let centerOnlyTwoFeatures =
            "zest.settings.centerOnlyTwoFeatures"

        static let centerOnlyFourFeatures =
            "zest.settings.centerOnlyFourFeatures"

        static let tripleFeatures = "zest.settings.tripleFeatures"
        static let showInMenuBar = "zest.settings.showInMenuBar"
        static let menuBarBlocks = "zest.settings.menuBarBlocks"
        static let menuBarPinnedFeatures = "zest.settings.menuBarPinnedFeatures"
        static let rapidInputSourceSwitching = "zest.settings.rapidInputSourceSwitching"
        static let saturnPreviousShortcut = "zest.settings.saturnPreviousShortcut"
        static let saturnNextShortcut = "zest.settings.saturnNextShortcut"

        static let sliceAssignments =
            "zest.settings.sliceAssignments"

        static let applicationTargets =
            "zest.settings.applicationTargets"

        static let shortcutTargets =
            "zest.settings.shortcutTargets"
        static let centerApplicationTargets = "zest.settings.centerApplicationTargets"
        static let centerShortcutTargets = "zest.settings.centerShortcutTargets"

        static let showZestShortcut =
            "zest.settings.showZestShortcut"

        static let launchAtLogin =
            "zest.settings.launchAtLogin"

        static let hasCompletedOnboarding =
            "zest.onboarding.completed"
    }


    // Prevent property observers from writing
    // half-loaded state during initialization.

    private var isLoading =
        true

    // Layout editing is transactional: while the Settings editor is dirty,
    // layout/form-factor changes live in memory but are not written to disk.
    @Published private(set) var isLayoutEditing = false

    private var layoutSnapshotFormFactor: ZestFormFactor?
    private var layoutSnapshotCenterOnlyPage: String?
    private var layoutSnapshotCenterOnlyTwoFeatures: [ZestFeature]?
    private var layoutSnapshotCenterOnlyFourFeatures: [ZestFeature]?
    private var layoutSnapshotTripleFeatures: [ZestFeature]?
    private var layoutSnapshotAssignments: [ZestSliceSlot: ZestFeature]?
    private var layoutSnapshotApplications: [ZestSliceSlot: ZestApplicationTarget]?
    private var layoutSnapshotShortcuts: [ZestSliceSlot: ZestShortcutTarget]?
    private var layoutSnapshotCenterApplications: [String: ZestApplicationTarget]?
    private var layoutSnapshotCenterShortcuts: [String: ZestShortcutTarget]?


    // MARK: Init

    init(
        defaults:
            UserDefaults = .standard
    ) {

        self.defaults =
            defaults


        // Defaults

        accent =
            .orange

        formFactor =
            .orangeSlice

        centerOnlyPage =
            "language"

        centerOnlyTwoFeatures = [.emoji, .clipboard]
        centerOnlyFourFeatures = [.size, .font, .emoji, .symbols]
        tripleFeatures = [.clipboard, .emoji, .symbols]
        showInMenuBar = true
        hasCompletedOnboarding = false
        menuBarBlocks = [.monitors, .pinnedActions]
        menuBarPinnedFeatures = [.size, .font, .clipboard, .emoji, .symbols]
        rapidInputSourceSwitching = true

        // Default rapid input-source steering: Control + Option + Left/Right.
        // Both shortcuts remain fully recordable in Settings.
        saturnPreviousShortcut = ZestKeyboardShortcut(keyCode: 123, command: false, option: true, control: true, shift: false)
        saturnNextShortcut = ZestKeyboardShortcut(keyCode: 124, command: false, option: true, control: true, shift: false)

        sliceAssignments =
            Self.defaultSliceAssignments

        applicationTargets = [:]
        shortcutTargets = [:]
        centerApplicationTargets = [:]
        centerShortcutTargets = [:]

        showZestShortcut =
            .defaultShowZest

        launchAtLogin =
            false


        load()


        isLoading =
            false
    }


    // MARK: Default Layout

    static var defaultSliceAssignments:
        [ZestSliceSlot: ZestFeature] {

        [
            .slot2: .size,
            .slot3: .font,
            .slot4: .clipboard,
            .slot5: .emoji,
            .slot6: .symbols,
            .slot7: .settings
        ]
    }


    // MARK: Feature Assignment

    func feature(
        for slot:
            ZestSliceSlot
    ) -> ZestFeature {

        sliceAssignments[slot]
        ?? Self.defaultSliceAssignments[slot]
        ?? .settings
    }


    func assign(
        _ feature:
            ZestFeature,
        to slot:
            ZestSliceSlot
    ) {

        var updated =
            sliceAssignments


        // Keep the normal slice one-feature-per-slot.
        //
        // If the chosen feature already exists in
        // another slot, swap the two features rather
        // than creating a duplicate.

        if let existingSlot =
            updated.first(
                where: {
                    $0.value == feature
                    && $0.key != slot
                }
            )?
            .key {

            let displacedFeature =
                updated[slot]


            updated[slot] =
                feature


            if let displacedFeature {

                updated[existingSlot] =
                    displacedFeature

            } else {

                updated.removeValue(
                    forKey:
                        existingSlot
                )
            }

        } else {

            updated[slot] =
                feature
        }


        sliceAssignments =
            updated
    }


    func removeAllSliceFeatures() {
        sliceAssignments = [:]
    }


    func isConfigured(_ feature: ZestFeature, in slot: ZestSliceSlot) -> Bool {
        switch feature {
        case .openShortcut:
            return applicationTargets[slot] != nil
        case .runShortcut:
            return shortcutTargets[slot] != nil
        default:
            return true
        }
    }


    func configureApplication(_ target: ZestApplicationTarget, for slot: ZestSliceSlot) {
        applicationTargets[slot] = target
    }


    func configureShortcut(_ target: ZestShortcutTarget, for slot: ZestSliceSlot) {
        shortcutTargets[slot] = target
    }


    @discardableResult
    func performConfiguredAction(for feature: ZestFeature, in slot: ZestSliceSlot) -> Bool {
        switch feature {
        case .openShortcut:
            guard let target = applicationTargets[slot] else { return false }
            let url = URL(fileURLWithPath: target.path)
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: NSWorkspace.OpenConfiguration()
            )
            return true

        case .runShortcut:
            guard let target = shortcutTargets[slot] else { return false }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", target.name]
            do {
                try process.run()
                return true
            } catch {
                print("🍊 SHORTCUT ERROR → \(error.localizedDescription)")
                return false
            }

        default:
            return false
        }
    }


    func centerActionKey(count: Int, index: Int) -> String { "\(count)-\(index)" }

    func isCenterConfigured(_ feature: ZestFeature, count: Int, index: Int) -> Bool {
        let key = centerActionKey(count: count, index: index)
        if feature == .openShortcut { return centerApplicationTargets[key] != nil }
        if feature == .runShortcut { return centerShortcutTargets[key] != nil }
        return true
    }

    func configureCenterApplication(_ target: ZestApplicationTarget, count: Int, index: Int) {
        centerApplicationTargets[centerActionKey(count: count, index: index)] = target
    }
    func configureCenterShortcut(_ target: ZestShortcutTarget, count: Int, index: Int) {
        centerShortcutTargets[centerActionKey(count: count, index: index)] = target
    }
    @discardableResult func performCenterConfiguredAction(_ feature: ZestFeature, count: Int, index: Int) -> Bool {
        let key = centerActionKey(count: count, index: index)
        if feature == .openShortcut, let target = centerApplicationTargets[key] {
            return NSWorkspace.shared.open(URL(fileURLWithPath: target.path))
        }
        if feature == .runShortcut, let target = centerShortcutTargets[key] {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts"); process.arguments = ["run", target.name]
            do { try process.run(); return true } catch { return false }
        }
        return false
    }

    // MARK: Runtime Layout Snapshot

    // The Settings editor is transactional. Runtime Zest keeps rendering the
    // last saved layout while the user experiments with a draft, then switches
    // atomically when Save commits the edit.
    var runtimeFormFactor: ZestFormFactor {
        isLayoutEditing ? (layoutSnapshotFormFactor ?? formFactor) : formFactor
    }

    var runtimeCenterOnlyPage: String {
        isLayoutEditing ? (layoutSnapshotCenterOnlyPage ?? centerOnlyPage) : centerOnlyPage
    }

    var runtimeCenterOnlyTwoFeatures: [ZestFeature] {
        isLayoutEditing ? (layoutSnapshotCenterOnlyTwoFeatures ?? centerOnlyTwoFeatures) : centerOnlyTwoFeatures
    }

    var runtimeCenterOnlyFourFeatures: [ZestFeature] {
        isLayoutEditing ? (layoutSnapshotCenterOnlyFourFeatures ?? centerOnlyFourFeatures) : centerOnlyFourFeatures
    }

    var runtimeTripleFeatures: [ZestFeature] {
        isLayoutEditing ? (layoutSnapshotTripleFeatures ?? tripleFeatures) : tripleFeatures
    }

    var runtimeSliceAssignments: [ZestSliceSlot: ZestFeature] {
        isLayoutEditing ? (layoutSnapshotAssignments ?? sliceAssignments) : sliceAssignments
    }

    // MARK: Layout Editing Transaction

    func beginLayoutEditing() {
        guard !isLayoutEditing else { return }

        layoutSnapshotFormFactor = formFactor
        layoutSnapshotCenterOnlyPage = centerOnlyPage
        layoutSnapshotCenterOnlyTwoFeatures = centerOnlyTwoFeatures
        layoutSnapshotCenterOnlyFourFeatures = centerOnlyFourFeatures
        layoutSnapshotTripleFeatures = tripleFeatures
        layoutSnapshotAssignments = sliceAssignments
        layoutSnapshotApplications = applicationTargets
        layoutSnapshotShortcuts = shortcutTargets
        layoutSnapshotCenterApplications = centerApplicationTargets
        layoutSnapshotCenterShortcuts = centerShortcutTargets
        isLayoutEditing = true
    }


    func commitLayoutEditing() {
        guard isLayoutEditing else { return }

        isLayoutEditing = false
        layoutSnapshotFormFactor = nil
        layoutSnapshotCenterOnlyPage = nil
        layoutSnapshotCenterOnlyTwoFeatures = nil
        layoutSnapshotCenterOnlyFourFeatures = nil
        layoutSnapshotTripleFeatures = nil
        layoutSnapshotAssignments = nil
        layoutSnapshotApplications = nil
        layoutSnapshotShortcuts = nil
        layoutSnapshotCenterApplications = nil
        layoutSnapshotCenterShortcuts = nil

        // Persist the complete, validated layout atomically from the user's
        // point of view.
        save()
    }


    func cancelLayoutEditing() {
        guard isLayoutEditing else { return }

        isLoading = true

        if let value = layoutSnapshotFormFactor {
            formFactor = value
        }

        if let value = layoutSnapshotCenterOnlyPage {
            centerOnlyPage = value
        }
        if let value = layoutSnapshotCenterOnlyTwoFeatures {
            centerOnlyTwoFeatures = value
        }
        if let value = layoutSnapshotCenterOnlyFourFeatures {
            centerOnlyFourFeatures = value
        }
        if let value = layoutSnapshotTripleFeatures {
            tripleFeatures = value
        }

        if let value = layoutSnapshotAssignments {
            sliceAssignments = value
        }

        if let value = layoutSnapshotApplications {
            applicationTargets = value
        }

        if let value = layoutSnapshotShortcuts {
            shortcutTargets = value
        }
        if let value = layoutSnapshotCenterApplications { centerApplicationTargets = value }
        if let value = layoutSnapshotCenterShortcuts { centerShortcutTargets = value }

        isLoading = false
        isLayoutEditing = false

        layoutSnapshotFormFactor = nil
        layoutSnapshotCenterOnlyPage = nil
        layoutSnapshotCenterOnlyTwoFeatures = nil
        layoutSnapshotCenterOnlyFourFeatures = nil
        layoutSnapshotTripleFeatures = nil
        layoutSnapshotAssignments = nil
        layoutSnapshotApplications = nil
        layoutSnapshotShortcuts = nil
        layoutSnapshotCenterApplications = nil
        layoutSnapshotCenterShortcuts = nil

        save()
    }


    var isOrangeSliceComplete: Bool {
        ZestSliceSlot.allCases.allSatisfy {
            sliceAssignments[$0] != nil
        }
    }


    // MARK: Reset

    func resetAppearance() {

        accent =
            .orange

        formFactor =
            .orangeSlice

        centerOnlyPage = "language"
        centerOnlyTwoFeatures = [.emoji, .clipboard]
        centerOnlyFourFeatures = [.size, .font, .emoji, .symbols]
        tripleFeatures = [.clipboard, .emoji, .symbols]
        menuBarBlocks = [.monitors, .pinnedActions]
        menuBarPinnedFeatures = [.size, .font, .clipboard, .emoji, .symbols]
        rapidInputSourceSwitching = true

        // Default rapid input-source steering: Control + Option + Left/Right.
        // Both shortcuts remain fully recordable in Settings.
        saturnPreviousShortcut = ZestKeyboardShortcut(keyCode: 123, command: false, option: true, control: true, shift: false)
        saturnNextShortcut = ZestKeyboardShortcut(keyCode: 124, command: false, option: true, control: true, shift: false)

        sliceAssignments =
            Self.defaultSliceAssignments

        applicationTargets = [:]
        shortcutTargets = [:]
        centerApplicationTargets = [:]
        centerShortcutTargets = [:]
    }


    func resetShortcut() {

        showZestShortcut =
            .defaultShowZest
    }


    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func resetOnboardingState() {
        hasCompletedOnboarding = false
    }


    func resetAll() {

        accent =
            .orange

        formFactor =
            .orangeSlice

        centerOnlyPage = "language"
        centerOnlyTwoFeatures = [.emoji, .clipboard]
        centerOnlyFourFeatures = [.size, .font, .emoji, .symbols]
        tripleFeatures = [.clipboard, .emoji, .symbols]
        menuBarBlocks = [.monitors, .pinnedActions]
        menuBarPinnedFeatures = [.size, .font, .clipboard, .emoji, .symbols]
        rapidInputSourceSwitching = true

        // Default rapid input-source steering: Control + Option + Left/Right.
        // Both shortcuts remain fully recordable in Settings.
        saturnPreviousShortcut = ZestKeyboardShortcut(keyCode: 123, command: false, option: true, control: true, shift: false)
        saturnNextShortcut = ZestKeyboardShortcut(keyCode: 124, command: false, option: true, control: true, shift: false)

        sliceAssignments =
            Self.defaultSliceAssignments

        applicationTargets = [:]
        shortcutTargets = [:]

        showZestShortcut =
            .defaultShowZest

        launchAtLogin =
            false
    }


    // MARK: Load

    private func load() {

        if let rawAccent =
            defaults.string(
                forKey:
                    Key.accent
            ),
           let savedAccent =
            ZestAccent(
                rawValue:
                    rawAccent
            ) {

            accent =
                savedAccent
        }


        if let rawFormFactor =
            defaults.string(
                forKey:
                    Key.formFactor
            ),
           let savedFormFactor =
            ZestFormFactor(
                rawValue:
                    rawFormFactor
            ) {

            formFactor =
                savedFormFactor
        }


        if let savedCenterOnlyPage = defaults.string(forKey: Key.centerOnlyPage) {
            centerOnlyPage = savedCenterOnlyPage
        }
        if let data = defaults.data(forKey: Key.centerOnlyTwoFeatures),
           let decoded = try? JSONDecoder().decode([ZestFeature].self, from: data),
           decoded.count == 2 {
            centerOnlyTwoFeatures = decoded
        }
        if let data = defaults.data(forKey: Key.centerOnlyFourFeatures),
           let decoded = try? JSONDecoder().decode([ZestFeature].self, from: data),
           decoded.count == 4 {
            centerOnlyFourFeatures = decoded
        }
        if let data = defaults.data(forKey: Key.tripleFeatures),
           let decoded = try? JSONDecoder().decode([ZestFeature].self, from: data), decoded.count == 3 {
            tripleFeatures = decoded
        }
        if defaults.object(forKey: Key.showInMenuBar) != nil {
            showInMenuBar = defaults.bool(forKey: Key.showInMenuBar)
        }

        if defaults.object(forKey: Key.hasCompletedOnboarding) != nil {
            hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        }

        if let data = defaults.data(forKey: Key.menuBarBlocks),
           let decoded = try? JSONDecoder().decode([ZestMenuBarBlock].self, from: data),
           !decoded.isEmpty {
            menuBarBlocks = Array(decoded.prefix(2))
        }
        if let data = defaults.data(forKey: Key.menuBarPinnedFeatures),
           let decoded = try? JSONDecoder().decode([ZestFeature].self, from: data), decoded.count == 5 {
            menuBarPinnedFeatures = decoded
        }
        if defaults.object(forKey: Key.rapidInputSourceSwitching) != nil {
            rapidInputSourceSwitching = defaults.bool(forKey: Key.rapidInputSourceSwitching)
        }
        if let data = defaults.data(forKey: Key.saturnPreviousShortcut),
           let decoded = try? JSONDecoder().decode(ZestKeyboardShortcut.self, from: data) { saturnPreviousShortcut = decoded }
        if let data = defaults.data(forKey: Key.saturnNextShortcut),
           let decoded = try? JSONDecoder().decode(ZestKeyboardShortcut.self, from: data) { saturnNextShortcut = decoded }


        if let data =
            defaults.data(
                forKey:
                    Key.sliceAssignments
            ),
           let decoded =
            try? JSONDecoder()
                .decode(
                    [Int: ZestFeature].self,
                    from:
                        data
                ) {

            var assignments:
                [ZestSliceSlot: ZestFeature]
                = [:]


            for (
                rawSlot,
                feature
            ) in decoded {

                guard let slot =
                    ZestSliceSlot(
                        rawValue:
                            rawSlot
                    )
                else {
                    continue
                }


                assignments[slot] =
                    feature
            }


            sliceAssignments =
                assignments
        }


        if let data = defaults.data(forKey: Key.applicationTargets),
           let decoded = try? JSONDecoder().decode([Int: ZestApplicationTarget].self, from: data) {
            applicationTargets = Dictionary(uniqueKeysWithValues: decoded.compactMap { raw, value in
                ZestSliceSlot(rawValue: raw).map { ($0, value) }
            })
        }

        if let data = defaults.data(forKey: Key.shortcutTargets),
           let decoded = try? JSONDecoder().decode([Int: ZestShortcutTarget].self, from: data) {
            shortcutTargets = Dictionary(uniqueKeysWithValues: decoded.compactMap { raw, value in
                ZestSliceSlot(rawValue: raw).map { ($0, value) }
            })
        }

        if let data = defaults.data(forKey: Key.centerApplicationTargets),
           let decoded = try? JSONDecoder().decode([String: ZestApplicationTarget].self, from: data) { centerApplicationTargets = decoded }
        if let data = defaults.data(forKey: Key.centerShortcutTargets),
           let decoded = try? JSONDecoder().decode([String: ZestShortcutTarget].self, from: data) { centerShortcutTargets = decoded }


        if let data =
            defaults.data(
                forKey:
                    Key.showZestShortcut
            ),
           let shortcut =
            try? JSONDecoder()
                .decode(
                    ZestKeyboardShortcut.self,
                    from:
                        data
                ) {

            showZestShortcut =
                shortcut
        }


        if defaults.object(
            forKey:
                Key.launchAtLogin
        ) != nil {

            launchAtLogin =
                defaults.bool(
                    forKey:
                        Key.launchAtLogin
                )
        }
    }


    // MARK: Shortcut Persistence

    /// Keyboard shortcuts are preferences, not part of the transactional
    /// layout editor. Persist them immediately even while a layout preview is
    /// being edited, so the global event monitor sees the new binding at once.
    private func saveBoolImmediately(_ value: Bool, key: String) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key)
        defaults.synchronize()
    }

    private func saveShortcutImmediately(_ shortcut: ZestKeyboardShortcut, key: String) {
        guard !isLoading else { return }
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: key)
            defaults.synchronize()
        }
    }


    // MARK: Save

    private func save() {

        guard !isLoading else {
            return
        }

        // Explicit Save/Cancel owns persistence while a layout edit session
        // is active. This prevents half-edited rings surviving a relaunch.
        guard !isLayoutEditing else {
            return
        }


        defaults.set(
            accent.rawValue,
            forKey:
                Key.accent
        )


        defaults.set(
            formFactor.rawValue,
            forKey:
                Key.formFactor
        )


        defaults.set(
            centerOnlyPage,
            forKey:
                Key.centerOnlyPage
        )
        if let data = try? JSONEncoder().encode(centerOnlyTwoFeatures) {
            defaults.set(data, forKey: Key.centerOnlyTwoFeatures)
        }
        if let data = try? JSONEncoder().encode(centerOnlyFourFeatures) {
            defaults.set(data, forKey: Key.centerOnlyFourFeatures)
        }
        if let data = try? JSONEncoder().encode(tripleFeatures) { defaults.set(data, forKey: Key.tripleFeatures) }
        if let data = try? JSONEncoder().encode(menuBarBlocks) { defaults.set(data, forKey: Key.menuBarBlocks) }
        if let data = try? JSONEncoder().encode(menuBarPinnedFeatures) { defaults.set(data, forKey: Key.menuBarPinnedFeatures) }
        if let data = try? JSONEncoder().encode(saturnPreviousShortcut) { defaults.set(data, forKey: Key.saturnPreviousShortcut) }
        if let data = try? JSONEncoder().encode(saturnNextShortcut) { defaults.set(data, forKey: Key.saturnNextShortcut) }


        let encodableAssignments:
            [Int: ZestFeature] =
            Dictionary(
                uniqueKeysWithValues:
                    sliceAssignments.map {
                        (
                            $0.key.rawValue,
                            $0.value
                        )
                    }
            )


        if let data =
            try? JSONEncoder()
                .encode(
                    encodableAssignments
                ) {

            defaults.set(
                data,
                forKey:
                    Key.sliceAssignments
            )
        }


        let encodedApps = Dictionary(uniqueKeysWithValues: applicationTargets.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(encodedApps) {
            defaults.set(data, forKey: Key.applicationTargets)
        }

        let encodedShortcuts = Dictionary(uniqueKeysWithValues: shortcutTargets.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(encodedShortcuts) {
            defaults.set(data, forKey: Key.shortcutTargets)
        }

        if let data = try? JSONEncoder().encode(centerApplicationTargets) { defaults.set(data, forKey: Key.centerApplicationTargets) }
        if let data = try? JSONEncoder().encode(centerShortcutTargets) { defaults.set(data, forKey: Key.centerShortcutTargets) }


        if let data =
            try? JSONEncoder()
                .encode(
                    showZestShortcut
                ) {

            defaults.set(
                data,
                forKey:
                    Key.showZestShortcut
            )
        }


        defaults.set(
            launchAtLogin,
            forKey:
                Key.launchAtLogin
        )
    }
}
