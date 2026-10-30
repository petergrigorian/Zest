//
//  ZestLayoutFixServices.swift
//  Zest
//
//  0.1.2 — native macOS Services transport for Layout Fix.
//
//  AppKit Services are intentionally used here instead of trying to capture
//  another application's selection with Accessibility or synthetic Command-C.
//  The source application writes its own current selection to the service
//  pasteboard and reads the transformed string back into that same selection.
//

import AppKit
import Foundation

@MainActor
final class ZestLayoutFixServicesProvider: NSObject {
    private let settingsManager: ZestSettingsManager
    private let inputSources = InputSourceManager()
    private let hud = ZestLayoutFixHUDController.shared

    private let legacyStringType = NSPasteboard.PasteboardType(rawValue: "NSStringPboardType")

    init(settingsManager: ZestSettingsManager) {
        self.settingsManager = settingsManager
        super.init()
    }

    /// Entry point advertised by Info.plist/NSServices.
    ///
    /// Every service slot calls the same selector and supplies its slot number
    /// through NSUserData.  The current Zest settings decide which installed
    /// input source that slot targets, so the Info.plist never has to change
    /// when the user changes languages.
    @objc func layoutFixService(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let slot = (userData ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        print("⌨️ LAYOUT FIX SERVICE → invoked slot:", slot.isEmpty ? "<none>" : slot)

        guard settingsManager.layoutFixEnabled else {
            error.pointee = "Layout Fix is disabled in Zest Settings." as NSString
            hud.showFailure(message: "Layout Fix disabled")
            return
        }

        guard let target = settingsManager.layoutFixTargets.first(where: { $0.triggerLabel == slot }) else {
            error.pointee = "No input source is assigned to Layout Fix slot \(slot)." as NSString
            hud.showFailure(message: "Configure slot \(slot)")
            print("⌨️ LAYOUT FIX SERVICE → no target assigned to slot", slot)
            return
        }

        guard let selectedText = serviceString(from: pasteboard), !selectedText.isEmpty else {
            error.pointee = "The source application did not provide selected text." as NSString
            hud.showFailure(message: "No selected text")
            print("⌨️ LAYOUT FIX SERVICE → service pasteboard contained no text")
            return
        }

        inputSources.refresh()

        print(
            "⌨️ LAYOUT FIX SERVICE → received chars:", selectedText.count,
            "target:", target.name,
            "slot:", slot
        )

        hud.showPending(targetCode: target.shortLabel, targetName: target.name)

        guard let result = ZestPhysicalKeyboardLayoutMapper.shared.remap(
            selectedText,
            to: target.inputSourceID,
            installedSources: inputSources.sources,
            preferredSourceID: inputSources.currentSource?.id
        ) else {
            error.pointee = "Zest could not map the selected text to \(target.name)." as NSString
            hud.showFailure(message: "Could not remap text")
            print("⌨️ LAYOUT FIX SERVICE → mapper returned no result")
            return
        }

        writeServiceString(result.correctedText, to: pasteboard)

        if let targetSource = inputSources.source(withID: target.inputSourceID) {
            inputSources.select(targetSource)
        }

        hud.show(targetCode: target.shortLabel, targetName: "Layout Fix")

        print(
            "⌨️ LAYOUT FIX SERVICE → returned chars:", result.correctedText.count,
            "source:", result.sourceName,
            "target:", result.targetName,
            "coverage:", String(format: "%.2f", result.coverage)
        )
    }

    private func serviceString(from pasteboard: NSPasteboard) -> String? {
        if let value = pasteboard.string(forType: .string), !value.isEmpty {
            return value
        }

        if let value = pasteboard.string(forType: legacyStringType), !value.isEmpty {
            return value
        }

        // Some service requestors vend plain text through a pasteboard item
        // even when string(forType:) does not resolve the preferred alias.
        for item in pasteboard.pasteboardItems ?? [] {
            if let value = item.string(forType: .string), !value.isEmpty {
                return value
            }
            if let value = item.string(forType: legacyStringType), !value.isEmpty {
                return value
            }
        }

        return nil
    }

    private func writeServiceString(_ string: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, legacyStringType], owner: nil)
        pasteboard.setString(string, forType: .string)
        pasteboard.setString(string, forType: legacyStringType)
    }
}
