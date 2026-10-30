//
//  ZestConfiguredActionIcon.swift
//  Zest
//
//  0.1.2 — real target icon renderer for configured action tiles
//

import SwiftUI
import AppKit

struct ZestConfiguredActionIcon: View {
    @ObservedObject private var resolver = ZestActionIconResolver.shared

    let feature: ZestFeature
    var applicationTarget: ZestApplicationTarget?
    var urlTarget: ZestURLTarget?
    var size: CGFloat = 18

    var body: some View {
        Group {
            if feature == .openShortcut, let target = applicationTarget {
                Image(nsImage: resolver.applicationIcon(path: target.path))
                    .resizable()
                    .scaledToFit()
            } else if feature == .runShortcut, let image = resolver.shortcutFallbackIcon() {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else if feature == .url,
                      let target = urlTarget,
                      let image = resolver.cachedURLIcon(for: target.urlString) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .onAppear { resolver.loadURLIcon(for: target.urlString) }
            } else {
                Image(systemName: feature.systemImage)
                    .font(.system(size: size * 0.78, weight: .semibold))
                    .onAppear {
                        if feature == .url, let target = urlTarget {
                            resolver.loadURLIcon(for: target.urlString)
                        }
                    }
            }
        }
        .frame(width: size, height: size)
    }
}
