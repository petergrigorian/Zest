//
//  ZestSettingsBackupService.swift
//  Zest
//
//  0.1.1 — Settings schema + pre-update backups
//

import Foundation

final class ZestSettingsBackupService {
    static let shared = ZestSettingsBackupService()

    static let currentSchemaVersion = 1
    private let schemaKey = "zest.settings.schemaVersion"

    private init() {}

    func ensureSchemaVersion() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: schemaKey) == nil {
            defaults.set(Self.currentSchemaVersion, forKey: schemaKey)
        }
    }

    @discardableResult
    func createBackup(reason: String) -> URL? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }

        let defaults = UserDefaults.standard
        defaults.synchronize()

        guard let domain = defaults.persistentDomain(forName: bundleID) else {
            return nil
        }

        let fm = FileManager.default
        guard let support = fm.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let directory = support
            .appendingPathComponent("Zest", isDirectory: true)
            .appendingPathComponent("Settings Backups", isDirectory: true)

        do {
            try fm.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let version = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown"

            let build = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "unknown"

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

            let safeReason = reason
                .replacingOccurrences(
                    of: "[^A-Za-z0-9._-]+",
                    with: "-",
                    options: .regularExpression
                )

            let fileName =
                "Zest-\(version)-\(build)-\(formatter.string(from: Date()))-\(safeReason).plist"

            let destination = directory.appendingPathComponent(fileName)

            let payload: [String: Any] = [
                "metadata": [
                    "bundleIdentifier": bundleID,
                    "version": version,
                    "build": build,
                    "schemaVersion": Self.currentSchemaVersion,
                    "createdAt": Date(),
                    "reason": reason
                ],
                "defaults": domain
            ]

            let data = try PropertyListSerialization.data(
                fromPropertyList: payload,
                format: .xml,
                options: 0
            )

            try data.write(to: destination, options: .atomic)

            pruneOldBackups(in: directory, keeping: 20)
            return destination
        } catch {
            print("🍊 SETTINGS BACKUP ERROR →", error.localizedDescription)
            return nil
        }
    }

    private func pruneOldBackups(in directory: URL, keeping limit: Int) {
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let sorted = files.sorted {
            let lhs = (try? $0.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast

            let rhs = (try? $1.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast

            return lhs > rhs
        }

        for url in sorted.dropFirst(limit) {
            try? fm.removeItem(at: url)
        }
    }
}
