//
//  ZestActionIconResolver.swift
//  Zest
//
//  0.1.1 — real app icons + URL favicons + safe Shortcut fallback
//

import Foundation
import AppKit
import Combine

@MainActor
final class ZestActionIconResolver: ObservableObject {
    static let shared = ZestActionIconResolver()

    @Published private(set) var urlIcons: [String: NSImage] = [:]

    private let cache = NSCache<NSString, NSImage>()

    private init() {}

    func applicationIcon(path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }

    func shortcutFallbackIcon() -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.shortcuts"
        ) else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: url.path)
    }

    func cachedURLIcon(for urlString: String) -> NSImage? {
        if let cached = cache.object(
            forKey: urlString as NSString
        ) {
            return cached
        }

        return urlIcons[urlString]
    }

    func loadURLIcon(for urlString: String) {
        guard cachedURLIcon(for: urlString) == nil,
              let pageURL = normalizedURL(urlString),
              let host = pageURL.host else {
            return
        }

        // Prefer the site's own favicon. No third-party favicon service is used.
        var components = URLComponents()
        components.scheme = pageURL.scheme ?? "https"
        components.host = host
        components.path = "/favicon.ico"

        guard let faviconURL = components.url else {
            return
        }

        Task {
            do {
                let (data, response) =
                    try await URLSession.shared.data(from: faviconURL)

                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    return
                }

                guard let image = NSImage(data: data) else {
                    return
                }

                cache.setObject(
                    image,
                    forKey: urlString as NSString
                )

                urlIcons[urlString] = image
            } catch {
                // Favicon is decorative. A missing icon must never stop the URL tile.
            }
        }
    }

    func openURL(
        _ urlString: String,
        browserBundleIdentifier: String? = nil
    ) -> Bool {

        guard let url = normalizedURL(urlString) else {
            return false
        }

        if let browserBundleIdentifier,
           let browserURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: browserBundleIdentifier
           ) {
            let configuration =
                NSWorkspace.OpenConfiguration()

            NSWorkspace.shared.open(
                [url],
                withApplicationAt: browserURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    print(
                        "🍊 URL OPEN ERROR →",
                        error.localizedDescription
                    )
                }
            }

            return true
        }

        return NSWorkspace.shared.open(url)
    }

    private func normalizedURL(
        _ raw: String
    ) -> URL? {
        let trimmed = raw.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           url.scheme != nil {
            return url
        }

        return URL(string: "https://\(trimmed)")
    }
}

struct ZestURLTarget:
    Codable,
    Equatable {
    var name: String
    var urlString: String
    var browserBundleIdentifier: String?
    var askBeforeOpening: Bool
}

struct ZestURLTargetStore {
    static let shared = ZestURLTargetStore()

    private let sliceKey =
        "zest.actions.urlTargets.slice"
    private let centerKey =
        "zest.actions.urlTargets.center"

    private init() {}

    func sliceTargets() -> [Int: ZestURLTarget] {
        decodeSlice(sliceKey)
    }

    func centerTargets() -> [String: ZestURLTarget] {
        decodeCenter(centerKey)
    }

    func target(for slot: Int) -> ZestURLTarget? {
        sliceTargets()[slot]
    }

    func target(centerKey key: String) -> ZestURLTarget? {
        centerTargets()[key]
    }

    func set(
        _ target: ZestURLTarget?,
        for slot: Int
    ) {
        var values = sliceTargets()

        if let target {
            values[slot] = target
        } else {
            values.removeValue(forKey: slot)
        }

        encode(values, key: sliceKey)
    }

    func set(
        _ target: ZestURLTarget?,
        centerKey key: String
    ) {
        var values = centerTargets()

        if let target {
            values[key] = target
        } else {
            values.removeValue(forKey: key)
        }

        encode(values, key: centerKey)
    }

    private func decodeSlice(
        _ key: String
    ) -> [Int: ZestURLTarget] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(
                [Int: ZestURLTarget].self,
                from: data
              ) else {
            return [:]
        }

        return value
    }

    private func decodeCenter(
        _ key: String
    ) -> [String: ZestURLTarget] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(
                [String: ZestURLTarget].self,
                from: data
              ) else {
            return [:]
        }

        return value
    }

    private func encode<T: Encodable>(
        _ value: T,
        key: String
    ) {
        guard let data = try? JSONEncoder().encode(value) else {
            return
        }

        UserDefaults.standard.set(data, forKey: key)
    }
}
