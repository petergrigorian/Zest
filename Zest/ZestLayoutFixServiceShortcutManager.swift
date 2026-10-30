//
//  ZestLayoutFixServiceShortcutManager.swift
//  Zest
//
//  0.1.2 — installs native keyboard equivalents for Zest's Layout Fix Services.
//
//  The Services transport is the part that finally gives Zest the source app's
//  real selected text.  Keep invocation native too: each configured target gets
//  a contextual macOS Service shortcut (Control + Shift + 1…9).
//

import AppKit
import Foundation
import CoreFoundation

@MainActor
final class ZestLayoutFixServiceShortcutManager {
    static let shared = ZestLayoutFixServiceShortcutManager()

    private let preferencesDomain = "pbs" as CFString
    private let servicesStatusKey = "NSServicesStatus" as CFString
    private let serviceMessage = "layoutFixService"
    private let bundleIdentifier = "com.petergrigorian.Zest"

    private init() {}

    /// Installs contextual Service shortcuts for the currently configured
    /// Layout Fix targets.  A target assigned to slot 1 becomes ⌃⇧1, slot 2
    /// becomes ⌃⇧2, and so on.  Unassigned slots remain available from the
    /// Services menu but have no keyboard equivalent.
    @discardableResult
    func applyConfiguredShortcuts(
        targets: [ZestLayoutFixTarget],
        enabled: Bool
    ) -> Bool {
        let copied = CFPreferencesCopyAppValue(
            servicesStatusKey,
            preferencesDomain
        )

        var allServices = (copied as? [String: Any]) ?? [:]
        let targetsBySlot = Dictionary(
            uniqueKeysWithValues: targets.map { ($0.triggerLabel, $0) }
        )

        for slot in 1...9 {
            let slotLabel = String(slot)
            let statusKey = resolvedStatusKey(
                slot: slot,
                existingKeys: Array(allServices.keys)
            )

            var status = (allServices[statusKey] as? [String: Any]) ?? [:]
            status["enabled_context_menu"] = true
            status["enabled_services_menu"] = true

            if enabled, targetsBySlot[slotLabel] != nil {
                // Cocoa's user key-equivalent syntax:
                // ^ = Control, $ = Shift.  No Command modifier is required.
                status["key_equivalent"] = "^$\(slotLabel)"
            } else {
                status.removeValue(forKey: "key_equivalent")
            }

            allServices[statusKey] = status
        }

        CFPreferencesSetAppValue(
            servicesStatusKey,
            allServices as CFDictionary,
            preferencesDomain
        )

        let synchronized = CFPreferencesAppSynchronize(preferencesDomain)
        NSUpdateDynamicServices()
        flushServicesCache()

        if synchronized {
            let installed = targets
                .sorted { $0.triggerLabel < $1.triggerLabel }
                .map { "⌃⇧\($0.triggerLabel) → \($0.shortLabel)" }
                .joined(separator: ", ")

            print(
                "⌨️ LAYOUT FIX SERVICE SHORTCUTS →",
                enabled ? (installed.isEmpty ? "no configured targets" : installed) : "disabled"
            )
            print("⌨️ LAYOUT FIX SERVICE SHORTCUTS → reopen source apps if macOS has cached the Services menu")
        } else {
            print("⌨️ LAYOUT FIX SERVICE SHORTCUTS → failed to synchronize pbs preferences")
        }

        return synchronized
    }

    private func resolvedStatusKey(
        slot: Int,
        existingKeys: [String]
    ) -> String {
        let needle = "Layout Fix \(slot)"

        if let existing = existingKeys.first(where: {
            $0.contains(bundleIdentifier)
                && $0.contains(needle)
                && $0.hasSuffix(" - \(serviceMessage)")
        }) {
            return existing
        }

        // NSServices still stores the Info.plist menu title in the pbs status
        // key even though modern macOS hides the old "Zest/" menu prefix.
        return "\(bundleIdentifier) - Zest/Layout Fix \(slot) - \(serviceMessage)"
    }

    private func flushServicesCache() {
        let executable = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            return
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["-flush"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            print("⌨️ LAYOUT FIX SERVICE SHORTCUTS → pbs flush failed:", error.localizedDescription)
        }
    }
}
