//
//  ZestActionConfirmation.swift
//  Zest
//
//  0.1.1 — shared confirmation policy + lightweight confirmation alert
//

import Foundation
import AppKit

enum ZestActionKind: String, Codable {
    case application
    case shortcut
    case url
}

struct ZestActionConfirmationPolicy {
    static let shared = ZestActionConfirmationPolicy()

    private init() {}

    func requiresConfirmation(
        placementKey: String,
        kind: ZestActionKind
    ) -> Bool {
        UserDefaults.standard.bool(
            forKey: key(
                placementKey: placementKey,
                kind: kind
            )
        )
    }

    func setRequiresConfirmation(
        _ value: Bool,
        placementKey: String,
        kind: ZestActionKind
    ) {
        UserDefaults.standard.set(
            value,
            forKey: key(
                placementKey: placementKey,
                kind: kind
            )
        )
    }

    private func key(
        placementKey: String,
        kind: ZestActionKind
    ) -> String {
        "zest.actions.confirm.\(kind.rawValue).\(placementKey)"
    }
}

@MainActor
enum ZestActionConfirmation {
    static func ask(
        title: String,
        detail: String,
        icon: NSImage? = nil
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        alert.icon = icon

        return alert.runModal() == .alertFirstButtonReturn
    }
}
