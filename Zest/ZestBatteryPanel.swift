//
//  ZestBatteryPanel.swift
//  Zest
//

import SwiftUI

struct ZestBatteryPanel: View {
    @ObservedObject private var battery =
        ZestBatteryService.shared

    let accentColor: Color

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: batterySymbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accentColor)

                Text("Battery")
                    .font(
                        .system(
                            size: 14,
                            weight: .bold,
                            design: .rounded
                        )
                    )

                Spacer()

                Button {
                    battery.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }

            if battery.hasBattery {
                VStack(spacing: 8) {
                    Text(
                        battery.percentage.map { "\($0)%" } ?? "—"
                    )
                    .font(
                        .system(
                            size: 34,
                            weight: .bold,
                            design: .rounded
                        )
                    )

                    ProgressView(
                        value: Double(battery.percentage ?? 0),
                        total: 100
                    )
                    .tint(accentColor)

                    Text(statusText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView(
                    "No Internal Battery",
                    systemImage: "desktopcomputer",
                    description: Text(
                        "Battery information is available on portable Macs."
                    )
                )
            }
        }
        .padding(16)
        .frame(width: 300)
        .frame(minHeight: 180)
        .background(.regularMaterial)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    private var batterySymbol: String {
        if battery.isCharging {
            return "battery.100percent.bolt"
        }

        switch battery.percentage ?? 0 {
        case 75...100: return "battery.100percent"
        case 50..<75: return "battery.75percent"
        case 25..<50: return "battery.50percent"
        case 10..<25: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private var statusText: String {
        if battery.isCharging {
            return "Charging"
        }

        if battery.isOnACPower {
            return "Power Adapter"
        }

        if let minutes = battery.timeRemainingMinutes {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours) hr \(mins) min remaining"
        }

        return "Battery Power"
    }
}
