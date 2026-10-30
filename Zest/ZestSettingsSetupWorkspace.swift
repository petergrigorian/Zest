//
//  ZestSettingsSetupWorkspace.swift
//  Zest
//
//  Shared full-window setup host for every configurable Zest feature.
//

import SwiftUI

struct ZestSettingsSetupWorkspace<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accentColor: Color
    let onClose: () -> Void
    let onSave: (() -> Void)?
    let saveTitle: String
    let saveDisabled: Bool
    let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        accentColor: Color,
        onClose: @escaping () -> Void,
        onSave: (() -> Void)? = nil,
        saveTitle: String = "Save",
        saveDisabled: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accentColor = accentColor
        self.onClose = onClose
        self.onSave = onSave
        self.saveTitle = saveTitle
        self.saveDisabled = saveDisabled
        self.content = content()
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(AnyShapeStyle(.regularMaterial))
                .overlay {
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.18),
                            accentColor.opacity(0.075),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .overlay(Color.black.opacity(0.035))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: systemImage)
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .foregroundStyle(accentColor)
                        .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 21, weight: .bold, design: .rounded))

                        Text(subtitle)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let onSave {
                        Button(action: onSave) {
                            Label(saveTitle, systemImage: "checkmark")
                        }
                        .buttonStyle(
                            ZestPrimaryActionButtonStyle(
                                accent: accentColor
                            )
                        )
                        .focusable(false)
                        .keyboardShortcut(.defaultAction)
                        .disabled(saveDisabled)
                        .opacity(saveDisabled ? 0.52 : 1)
                    }

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 38, height: 38)
                            .background {
                                Circle()
                                    .fill(Color.white.opacity(0.11))
                                    .glassEffect(.regular, in: Circle())
                            }
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.20), lineWidth: 0.7)
                            }
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .keyboardShortcut(.cancelAction)
                }
                // Leave the native red/yellow traffic lights untouched above us.
                .padding(.top, 50)
                .padding(.horizontal, 38)
                .padding(.bottom, 20)

                Divider()
                    .opacity(0.22)

                ScrollView {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)

                        content
                            .frame(maxWidth: 980, alignment: .topLeading)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 46)
                    .padding(.top, 38)
                    .padding(.bottom, 46)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .scrollIndicators(.visible)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .transition(.opacity)
    }
}
