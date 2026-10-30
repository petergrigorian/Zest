//
//  ZestRapidSymbolEngine.swift
//  Zest
//
//  0.1.2 — leader-key Rapid Symbols without a persistent CGEvent tap.
//

import Foundation
import AppKit
import Carbon

private let zestRapidSymbolSignature: OSType = 0x5A525359 // 'ZRSY'

private let zestRapidSymbolHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID(signature: 0, id: 0)
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    // This handler stays installed for the lifetime of Zest after Rapid Symbols
    // is used once. Never consume another subsystem's Carbon hotkey merely
    // because it happens to reuse the same numeric ID.
    guard hotKeyID.signature == zestRapidSymbolSignature else {
        return OSStatus(eventNotHandledErr)
    }

    let engine = Unmanaged<ZestRapidSymbolEngine>
        .fromOpaque(userData)
        .takeUnretainedValue()

    DispatchQueue.main.async {
        Task { @MainActor in
            engine.handleHotKeyID(hotKeyID.id)
        }
    }
    return noErr
}

@MainActor
final class ZestRapidSymbolEngine {
    static let shared = ZestRapidSymbolEngine()

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var symbolByHotKeyID: [UInt32: String] = [:]
    private var timeoutWorkItem: DispatchWorkItem?
    private let hud = ZestRapidSymbolHUDController()
    private var rapidClipboardManager: ClipboardHistoryManager?
    private var rapidTextInserter: ZestTextInserter?

    let mappings: [String: String] = [
        "-": "—",
        "=": "≠",
        "1": "©",
        "2": "®",
        "3": "™",
        "4": "•",
        "5": "°",
        "6": "…",
        "7": "→",
        "8": "←",
        "9": "↑",
        "0": "↓"
    ]

    private let keyCodes: [String: UInt32] = [
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
        "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
        "-": 27, "=": 24
    ]

    private init() {}


    func arm() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            ZestTextInserter.rememberExternalTarget(front)
        }

        // Use the exact same insertion object/path as Emoji and Symbols.
        // Creating it while the external editor is still frontmost preserves
        // the same destination semantics those panels rely on.
        let clipboardManager = ClipboardHistoryManager()
        rapidClipboardManager = clipboardManager
        rapidTextInserter = ZestTextInserter(clipboardManager: clipboardManager)

        guard !IsSecureEventInputEnabled() else {
            hud.showMessage(
                title: "Rapid Symbols unavailable",
                symbol: "lock.fill",
                subtitle: "Secure input is active"
            )
            return
        }

        ensureHandler()
        guard eventHandler != nil else {
            hud.showMessage(
                title: "Rapid Symbols unavailable",
                symbol: "exclamationmark.triangle.fill",
                subtitle: "Keyboard hotkeys could not be prepared"
            )
            return
        }

        unregisterTemporaryHotKeys()

        var nextID: UInt32 = 1
        for key in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="] {
            guard let keyCode = keyCodes[key], let symbol = mappings[key] else { continue }
            if let ref = register(keyCode: keyCode, modifiers: 0, id: nextID) {
                hotKeyRefs.append(ref)
                symbolByHotKeyID[nextID] = symbol
                nextID += 1
            }
        }

        // Escape cancels the armed state without needing an event tap.
        if let escape = register(keyCode: 53, modifiers: 0, id: 999) {
            hotKeyRefs.append(escape)
        }

        guard !symbolByHotKeyID.isEmpty else {
            hud.showMessage(
                title: "Rapid Symbols unavailable",
                symbol: "exclamationmark.triangle.fill",
                subtitle: "The symbol keys are already reserved"
            )
            return
        }

        timeoutWorkItem?.cancel()
        hud.showMappings(mappings)

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.cancel() }
        }
        timeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    func cancel() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        unregisterTemporaryHotKeys()
        removeHandler()
        hud.hide()
        rapidTextInserter = nil
        rapidClipboardManager = nil
    }

    fileprivate func handleHotKeyID(_ id: UInt32) {
        if id == 999 {
            cancel()
            return
        }

        guard let replacement = symbolByHotKeyID[id] else { return }

        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        unregisterTemporaryHotKeys()
        removeHandler()

        rapidTextInserter?.insertUsingPasteboard(replacement)

        // Keep the inserter alive long enough for its delayed Command-V and
        // pasteboard restoration to complete, then release the one-shot state.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.rapidTextInserter = nil
            self?.rapidClipboardManager = nil
        }

        hud.showMessage(
            title: "Inserted",
            symbol: replacement,
            subtitle: "Rapid Symbols"
        )
    }

    private func ensureHandler() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            zestRapidSymbolHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        if status != noErr {
            eventHandler = nil
            print("🍊 RAPID SYMBOL HOTKEY ERROR →", status)
        }
    }

    private func removeHandler() {
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func register(
        keyCode: UInt32,
        modifiers: UInt32,
        id: UInt32
    ) -> EventHotKeyRef? {
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(
            signature: zestRapidSymbolSignature,
            id: id
        )
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        return status == noErr ? reference : nil
    }

    private func unregisterTemporaryHotKeys() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        symbolByHotKeyID.removeAll()
    }
}
