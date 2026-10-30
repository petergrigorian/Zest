//
//  ZestReleaseNotesService.swift
//  Zest
//
//  0.1.2 — GitHub-backed release notes preview
//

import Foundation
import Combine

@MainActor
final class ZestReleaseNotesService: ObservableObject {
    static let shared = ZestReleaseNotesService()

    @Published private(set) var text: String = ""
    @Published private(set) var sourceURL: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private let repository = "petergrigorian/Zest"
    private init() {}

    func clear() {
        text = ""
        sourceURL = nil
        lastError = nil
        isLoading = false
    }

    /// Prefer the exact GitHub release referenced by Sparkle. If the appcast only
    /// supplies inline notes, they remain the fallback so the updater never loses
    /// release information because GitHub is temporarily unavailable.
    func load(
        releaseURL: URL?,
        installedOrAvailableVersion version: String,
        fallbackText: String?
    ) async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        if let releaseURL,
           let tag = githubTag(from: releaseURL),
           let result = await fetchRelease(tag: tag) {
            text = result.body
            sourceURL = result.htmlURL
            return
        }

        if let result = await fetchMostRelevantRelease(version: version) {
            text = result.body
            sourceURL = result.htmlURL
            return
        }

        let fallback = fallbackText?
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !fallback.isEmpty {
            text = fallback
            sourceURL = releaseURL
        } else {
            lastError = "Release notes could not be loaded."
        }
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let name: String?
        let body: String?
        let html_url: URL
        let prerelease: Bool
    }

    private func fetchRelease(tag: String) async -> (body: String, htmlURL: URL)? {
        guard let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.github.com/repos/\(repository)/releases/tags/\(encoded)") else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Zest/0.1.2", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            return (normalizedBody(release), release.html_url)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func fetchMostRelevantRelease(version: String) async -> (body: String, htmlURL: URL)? {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=30") else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Zest/0.1.2", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            let needle = version.lowercased()
            guard let release = releases.first(where: {
                $0.tag_name.lowercased().contains(needle) ||
                ($0.name?.lowercased().contains(needle) ?? false)
            }) else { return nil }
            return (normalizedBody(release), release.html_url)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func normalizedBody(_ release: GitHubRelease) -> String {
        let body = release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !body.isEmpty { return body }
        return release.name ?? release.tag_name
    }

    private func githubTag(from url: URL) -> String? {
        let components = url.pathComponents
        guard let index = components.firstIndex(of: "tag"), components.indices.contains(index + 1) else {
            return nil
        }
        return components[index + 1]
    }
}
