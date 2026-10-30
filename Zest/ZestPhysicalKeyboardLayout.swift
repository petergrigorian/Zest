//
//  ZestPhysicalKeyboardLayout.swift
//  Zest
//
//  0.1.2 — physical-key remapping between installed macOS input sources.
//

import Foundation
import Carbon

struct ZestLayoutRemapResult {
    let sourceName: String
    let targetName: String
    let targetCode: String
    let correctedText: String
    let coverage: Double
}

@MainActor
final class ZestPhysicalKeyboardLayoutMapper {
    static let shared = ZestPhysicalKeyboardLayoutMapper()

    private struct KeyStroke: Hashable {
        let keyCode: UInt16
        let shifted: Bool
    }

    private struct Snapshot {
        let source: ZestInputSource
        let strokeToCharacter: [KeyStroke: String]
        let characterToStroke: [String: KeyStroke]
        let script: ScriptKind
    }

    enum ScriptKind: String {
        case latin = "Latin"
        case cyrillic = "Cyrillic"
        case unsupported = "Unsupported"
    }

    private var cache: [String: Snapshot] = [:]

    private init() {}

    func supportKind(for source: ZestInputSource) -> ScriptKind {
        snapshot(for: source)?.script ?? .unsupported
    }

    func isSupported(_ source: ZestInputSource) -> Bool {
        supportKind(for: source) != .unsupported
    }

    func remap(
        _ text: String,
        to targetSourceID: String,
        installedSources: [ZestInputSource],
        preferredSourceID: String?
    ) -> ZestLayoutRemapResult? {
        guard !text.isEmpty,
              let targetSource = installedSources.first(where: { $0.id == targetSourceID }),
              let target = snapshot(for: targetSource),
              target.script != .unsupported
        else { return nil }

        let sourceSnapshots = installedSources
            .filter { $0.id != targetSourceID }
            .compactMap { snapshot(for: $0) }
            .filter { $0.script != .unsupported }

        var best: (Snapshot, String, Double)?

        for source in sourceSnapshots {
            var output = ""
            var mappedCount = 0
            var relevantCount = 0

            for character in text {
                if character.isWhitespace {
                    output.append(character)
                    continue
                }

                relevantCount += 1
                let raw = String(character)

                guard let stroke = source.characterToStroke[raw],
                      let targetCharacter = target.strokeToCharacter[stroke],
                      !targetCharacter.isEmpty
                else {
                    output.append(character)
                    continue
                }

                output.append(contentsOf: targetCharacter)
                mappedCount += 1
            }

            guard relevantCount > 0 else { continue }
            let coverage = Double(mappedCount) / Double(relevantCount)
            guard coverage >= 0.45, output != text else { continue }

            var score = coverage
            if source.source.id == preferredSourceID { score += 0.22 }
            if source.script != target.script { score += 0.10 }
            score += languageHintScore(output, target: target.source)

            if best == nil || score > best!.2 {
                best = (source, output, score)
            }
        }

        guard let best else { return nil }
        return ZestLayoutRemapResult(
            sourceName: best.0.source.name,
            targetName: targetSource.name,
            targetCode: targetSource.shortLabel,
            correctedText: best.1,
            coverage: min(best.2, 1.0)
        )
    }

    private func snapshot(for source: ZestInputSource) -> Snapshot? {
        if let cached = cache[source.id] { return cached }

        guard let pointer = TISGetInputSourceProperty(
            source.source,
            kTISPropertyUnicodeKeyLayoutData
        ) else {
            return nil
        }

        let data = Unmanaged<CFData>
            .fromOpaque(pointer)
            .takeUnretainedValue()

        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes)
            .assumingMemoryBound(to: UCKeyboardLayout.self)

        let keyCodes: [UInt16] = Array(0...50).map(UInt16.init)
        var strokeToCharacter: [KeyStroke: String] = [:]
        var characterToStroke: [String: KeyStroke] = [:]

        for keyCode in keyCodes {
            for shifted in [false, true] {
                guard let value = translatedCharacter(
                    layout: layout,
                    keyCode: keyCode,
                    shifted: shifted
                ),
                !value.isEmpty,
                value != "\u{0}"
                else { continue }

                let stroke = KeyStroke(keyCode: keyCode, shifted: shifted)
                strokeToCharacter[stroke] = value
                characterToStroke[value] = stroke
            }
        }

        let all = strokeToCharacter.values.joined()
        let latin = all.unicodeScalars.filter {
            ($0.value >= 0x0041 && $0.value <= 0x024F)
        }.count
        let cyrillic = all.unicodeScalars.filter {
            ($0.value >= 0x0400 && $0.value <= 0x052F)
        }.count

        let script: ScriptKind
        if latin >= 12 {
            script = .latin
        } else if cyrillic >= 12 {
            script = .cyrillic
        } else {
            script = .unsupported
        }

        let result = Snapshot(
            source: source,
            strokeToCharacter: strokeToCharacter,
            characterToStroke: characterToStroke,
            script: script
        )
        cache[source.id] = result
        return result
    }

    private func translatedCharacter(
        layout: UnsafePointer<UCKeyboardLayout>,
        keyCode: UInt16,
        shifted: Bool
    ) -> String? {
        var deadKeyState: UInt32 = 0
        var length: Int = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let modifierState: UInt32 = shifted ? UInt32(shiftKey >> 8) : 0

        let status: OSStatus = characters.withUnsafeMutableBufferPointer { buffer in
            UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDown),
                modifierState,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                buffer.count,
                &length,
                buffer.baseAddress
            )
        }

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: Int(length))
    }

    private func languageHintScore(_ text: String, target: ZestInputSource) -> Double {
        let lower = text.lowercased()
        let language = target.languages.first?.lowercased() ?? ""

        let hints: [String]
        if language.hasPrefix("en") {
            hints = ["the", "and", "you", "this", "with", "for", "to", "is"]
        } else if language.hasPrefix("uk") {
            hints = ["що", "це", "для", "і", "не", "на", "як", "ти"]
        } else if language.hasPrefix("ru") {
            hints = ["что", "это", "для", "и", "не", "на", "как", "ты"]
        } else if language.hasPrefix("de") {
            hints = ["der", "die", "das", "und", "ist", "nicht", "mit", "für"]
        } else {
            return 0
        }

        let hits = hints.reduce(0) { $0 + (lower.contains($1) ? 1 : 0) }
        return min(0.20, Double(hits) * 0.035)
    }
}
