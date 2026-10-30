import SwiftUI

struct ZestPrimaryActionButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(
                .system(
                    size: 12,
                    weight: .bold,
                    design: .rounded
                )
            )
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background {
                Capsule()
                    .fill(
                        accent.opacity(
                            configuration.isPressed ? 0.68 : 0.86
                        )
                    )
                    .glassEffect(
                        .regular.tint(
                            accent.opacity(
                                configuration.isPressed ? 0.20 : 0.30
                            )
                        ),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                Color.white.opacity(
                                    configuration.isPressed ? 0.22 : 0.40
                                ),
                                lineWidth: 0.8
                            )
                    }
                    .shadow(
                        color: accent.opacity(
                            configuration.isPressed ? 0.14 : 0.32
                        ),
                        radius: configuration.isPressed ? 6 : 12,
                        y: 3
                    )
                    .shadow(
                        color: Color.black.opacity(
                            configuration.isPressed ? 0.07 : 0.13
                        ),
                        radius: 6,
                        y: 3
                    )
            }
            .scaleEffect(
                configuration.isPressed ? 0.97 : 1
            )
            .animation(
                .spring(
                    response: 0.18,
                    dampingFraction: 0.82
                ),
                value: configuration.isPressed
            )
    }
}


struct ZestSecondaryActionButtonStyle: ButtonStyle {
    @AppStorage("zest.settings.increaseVisibility")
    private var increaseVisibility = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(
                .system(
                    size: 12,
                    weight: .bold,
                    design: .rounded
                )
            )
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background {
                Capsule()
                    .fill(.regularMaterial)
                    .overlay {
                        Capsule()
                            .fill(
                                Color.primary.opacity(
                                    configuration.isPressed
                                    ? (increaseVisibility ? 0.18 : 0.12)
                                    : (increaseVisibility ? 0.13 : 0.075)
                                )
                            )
                    }
                    .overlay {
                        Capsule()
                            .stroke(
                                Color.white.opacity(
                                    configuration.isPressed ? 0.24 : 0.38
                                ),
                                lineWidth: 0.9
                            )
                    }
                    .shadow(
                        color: Color.black.opacity(
                            configuration.isPressed ? 0.06 : 0.13
                        ),
                        radius: configuration.isPressed ? 4 : 8,
                        y: 3
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(
                .spring(
                    response: 0.18,
                    dampingFraction: 0.82
                ),
                value: configuration.isPressed
            )
    }
}
