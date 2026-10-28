//
//  ZestRapidSymbolEngine.swift
//  Zest
//
//  0.1.1 — leader-key rapid symbol input protocol
//
//  Protocol:
//  1. The AppDelegate calls arm() from any global shortcut you choose.
//  2. Zest shows a small HUD.
//  3. The next mapped key is swallowed and replaced by its Unicode symbol.
//

import Foundation
import AppKit
import ApplicationServices
import Carbon

@MainActor
final class ZestRapidSymbolEngine {
    static let shared = ZestRapidSymbolEngine()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isArmed = false
    private let hud = ZestRapidSymbolHUDController()

    /// Default one-keystroke protocol.
    /// Customize this later from Zest Settings.
    private var mappings: [String: String] = [
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

    private init() {}

    func start() {
        guard eventTap == nil else { return }

        let mask =
            CGEventMask(1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = {
            _, type, event, refcon in

            guard type == .keyDown,
                  let refcon else {
                return Unmanaged.passUnretained(event)
            }

            let engine =
                Unmanaged<ZestRapidSymbolEngine>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()

            return engine.handle(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged
                .passUnretained(self)
                .toOpaque()
        ) else {
            print(
                "🍊 RAPID SYMBOLS → could not create event tap. " +
                "Accessibility permission is required."
            )
            return
        }

        eventTap = tap
        runLoopSource =
            CFMachPortCreateRunLoopSource(
                kCFAllocatorDefault,
                tap,
                0
            )

        if let runLoopSource {
            CFRunLoopAddSource(
                CFRunLoopGetMain(),
                runLoopSource,
                .commonModes
            )
        }

        CGEvent.tapEnable(
            tap: tap,
            enable: true
        )
    }

    func arm() {
        start()

        guard eventTap != nil else { return }

        // Never try to intercept symbol entry while Secure Event Input is active.
        guard !IsSecureEventInputEnabled() else {
            hud.show(
                title: "Rapid Symbols unavailable",
                symbol: "lock.fill",
                subtitle: "Secure input is active"
            )
            return
        }

        isArmed = true

        hud.show(
            title: "Rapid Symbol Input",
            symbol: "sparkles",
            subtitle: "Press a symbol key"
        )
    }

    func cancel() {
        isArmed = false
        hud.hide()
    }

    private nonisolated func handle(
        _ event: CGEvent
    ) -> Unmanaged<CGEvent>? {

        MainActor.assumeIsolated {
            guard isArmed else {
                return Unmanaged.passUnretained(event)
            }

            if event.getIntegerValueField(
                .keyboardEventKeycode
            ) == 53 {
                cancel()
                return nil
            }

            guard let character =
                string(from: event),
                let replacement =
                    mappings[character] else {

                hud.show(
                    title: "No Symbol",
                    symbol: "questionmark",
                    subtitle: "No mapping for \(string(from: event) ?? "key")"
                )

                isArmed = false
                return nil
            }

            isArmed = false
            postUnicode(replacement)

            hud.show(
                title: "Inserted",
                symbol: replacement,
                subtitle: character
            )

            return nil
        }
    }

    private nonisolated func string(
        from event: CGEvent
    ) -> String? {
        var actualLength = 0
        var buffer = [UniChar](repeating: 0, count: 8)

        event.keyboardGetUnicodeString(
            maxStringLength: buffer.count,
            actualStringLength: &actualLength,
            unicodeString: &buffer
        )

        guard actualLength > 0 else { return nil }

        return String(
            utf16CodeUnits: buffer,
            count: actualLength
        )
    }

    private nonisolated func postUnicode(
        _ string: String
    ) {
        let source = CGEventSource(
            stateID: .hidSystemState
        )

        let utf16 = Array(string.utf16)

        guard let down = CGEvent(
            keyboardEventSource: source,
            virtualKey: 0,
            keyDown: true
        ),
        let up = CGEvent(
            keyboardEventSource: source,
            virtualKey: 0,
            keyDown: false
        ) else {
            return
        }

        down.keyboardSetUnicodeString(
            stringLength: utf16.count,
            unicodeString: utf16
        )

        up.keyboardSetUnicodeString(
            stringLength: utf16.count,
            unicodeString: utf16
        )

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
