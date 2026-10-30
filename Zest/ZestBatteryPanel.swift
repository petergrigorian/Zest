//
//  ZestBatteryPanel.swift
//  Zest
//

import SwiftUI

struct ZestBatteryPanel: View {
    @ObservedObject private var battery = ZestBatteryService.shared
    let accentColor: Color
    @State private var showingSetup = false

    var body: some View {
        ZStack {
            if !battery.setupCompleted || showingSetup {
                ZestBatterySetupView(
                    accentColor: accentColor,
                    onFinished: {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                            showingSetup = false
                        }
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                batteryView
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: 345)
        .zestPopupSurface(accentColor: accentColor, cornerRadius: 22)
        .onAppear { battery.refresh() }
    }

    private var batteryView: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: battery.isCharging ? "bolt.fill" : "battery.100percent")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(battery.isCharging ? Color.green : accentColor)

                Text("Battery")
                    .font(.system(size: 14, weight: .bold, design: .rounded))

                Spacer()

                Button {
                    battery.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        showingSetup = true
                    }
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Battery setup")
            }

            if battery.devices.isEmpty {
                ContentUnavailableView(
                    "No Battery Data",
                    systemImage: "battery.0percent",
                    description: Text("No selected device is currently exposing battery information to macOS.")
                )
                .frame(minHeight: 180)
            } else if battery.devices.count <= 3 {
                VStack(spacing: 10) {
                    ForEach(battery.devices) { device in
                        deviceRow(device)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(battery.devices) { device in
                            deviceRow(device)
                        }
                    }
                }
                .frame(height: min(CGFloat(battery.devices.count) * 92, 320))
            }
        }
        .padding(16)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func deviceRow(_ device: ZestBatteryDevice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: device.isCharging ? "bolt.fill" : device.category.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(device.isCharging ? Color.green : accentColor)
                    .frame(width: 20)

                Text(device.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Text("\(device.percentage)%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }

            ProgressView(value: Double(device.percentage), total: 100)
                .tint(device.isCharging ? Color.green : accentColor)

            HStack {
                Text(device.isCharging ? "Charging" : device.category.title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(device.isCharging ? Color.green : .secondary)

                Spacer()

                if device.category != .thisMac {
                    Text("Bluetooth")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }
}

struct ZestBatterySetupView: View {
    @ObservedObject private var battery = ZestBatteryService.shared
    let accentColor: Color
    let onFinished: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Battery Setup", systemImage: "battery.100percent")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Text("Display")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Divider().opacity(0.35)

            Text("Choose which battery sources Zest should display. Accessory percentages appear whenever macOS exposes battery data for that device.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                batteryToggle(
                    battery.computerDisplayName,
                    subtitle: "This device",
                    symbol: "laptopcomputer",
                    isOn: $battery.includeThisMac
                )

                Divider().opacity(0.35)

                batteryToggle(
                    "Audio accessories",
                    subtitle: "Headphones, headsets, speakers and similar Bluetooth audio devices",
                    symbol: "headphones",
                    isOn: $battery.includeAudio
                )

                batteryToggle(
                    "Input accessories",
                    subtitle: "Keyboards, mice, trackpads and other Bluetooth input devices",
                    symbol: "keyboard",
                    isOn: $battery.includeInput
                )

                batteryToggle(
                    "Other accessories",
                    subtitle: "Other supported Bluetooth devices with battery data",
                    symbol: "dot.radiowaves.left.and.right",
                    isOn: $battery.includeOther
                )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )

            HStack {
                Text("Detected now: \(battery.devices.count)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Done") {
                    battery.completeSetup()
                    onFinished()
                }
                .buttonStyle(ZestPrimaryActionButtonStyle(accent: accentColor))
            }
        }
        .padding(18)
        .frame(minHeight: 310, alignment: .top)
        .onAppear { battery.refresh() }
    }

    private func batteryToggle(
        _ title: String,
        subtitle: String,
        symbol: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 8.8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
