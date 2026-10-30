//
//  ZestBatteryService.swift
//  Zest
//
//  0.1.2 — internal + best-effort Bluetooth/HID battery layer
//

import Foundation
import IOKit
import IOKit.ps
import Combine

enum ZestBatteryDeviceCategory: String, Codable, CaseIterable, Identifiable {
    case thisMac
    case audio
    case input
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thisMac: return "This Mac"
        case .audio: return "Audio"
        case .input: return "Input"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .thisMac: return "laptopcomputer"
        case .audio: return "headphones"
        case .input: return "keyboard"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }
}

struct ZestBatteryDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let percentage: Int
    let isCharging: Bool
    let category: ZestBatteryDeviceCategory
}

@MainActor
final class ZestBatteryService: ObservableObject {
    static let shared = ZestBatteryService()

    var computerDisplayName: String {
        if let localized = Host.current().localizedName, !localized.isEmpty {
            return localized
        }

        let host = ProcessInfo.processInfo.hostName
            .replacingOccurrences(of: ".local", with: "")
        return host.isEmpty ? "This Mac" : host
    }

    @Published private(set) var hasBattery = false
    @Published private(set) var percentage: Int?
    @Published private(set) var isCharging = false
    @Published private(set) var isOnACPower = false
    @Published private(set) var timeRemainingMinutes: Int?
    @Published private(set) var name: String?
    @Published private(set) var devices: [ZestBatteryDevice] = []

    @Published var setupCompleted: Bool {
        didSet { defaults.set(setupCompleted, forKey: Key.setupCompleted) }
    }
    @Published var includeThisMac: Bool {
        didSet { defaults.set(includeThisMac, forKey: Key.includeThisMac); refresh() }
    }
    @Published var includeAudio: Bool {
        didSet { defaults.set(includeAudio, forKey: Key.includeAudio); refresh() }
    }
    @Published var includeInput: Bool {
        didSet { defaults.set(includeInput, forKey: Key.includeInput); refresh() }
    }
    @Published var includeOther: Bool {
        didSet { defaults.set(includeOther, forKey: Key.includeOther); refresh() }
    }

    private enum Key {
        static let setupCompleted = "zest.battery.setupCompleted"
        static let includeThisMac = "zest.battery.includeThisMac"
        static let includeAudio = "zest.battery.includeAudio"
        static let includeInput = "zest.battery.includeInput"
        static let includeOther = "zest.battery.includeOther"
    }

    private let defaults = UserDefaults.standard
    private var timer: Timer?

    private init() {
        setupCompleted = defaults.bool(forKey: Key.setupCompleted)
        includeThisMac = defaults.object(forKey: Key.includeThisMac) == nil ? true : defaults.bool(forKey: Key.includeThisMac)
        includeAudio = defaults.bool(forKey: Key.includeAudio)
        includeInput = defaults.bool(forKey: Key.includeInput)
        includeOther = defaults.bool(forKey: Key.includeOther)

        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    func completeSetup() {
        setupCompleted = true
        refresh()
    }

    func refresh() {
        readInternalBattery()

        var next: [ZestBatteryDevice] = []
        if includeThisMac, let percentage {
            next.append(
                ZestBatteryDevice(
                    id: "this-mac",
                    name: computerDisplayName,
                    percentage: percentage,
                    isCharging: isCharging,
                    category: .thisMac
                )
            )
        }

        next.append(contentsOf: readBluetoothHIDDevices().filter { device in
            switch device.category {
            case .thisMac: return false
            case .audio: return includeAudio
            case .input: return includeInput
            case .other: return includeOther
            }
        })

        var seen = Set<String>()
        devices = next.filter { seen.insert($0.id).inserted }
    }

    private func readInternalBattery() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            clearInternal()
            return
        }

        for source in list {
            guard let unmanaged = IOPSGetPowerSourceDescription(blob, source),
                  let description = unmanaged.takeUnretainedValue() as? [String: Any] else { continue }

            let type = description[kIOPSTypeKey as String] as? String
            guard type == (kIOPSInternalBatteryType as String) else { continue }

            hasBattery = true
            let current = description[kIOPSCurrentCapacityKey as String] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey as String] as? Int ?? 100
            percentage = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : nil
            isCharging = description[kIOPSIsChargingKey as String] as? Bool ?? false
            let state = description[kIOPSPowerSourceStateKey as String] as? String
            isOnACPower = state == (kIOPSACPowerValue as String)
            name = computerDisplayName
            let rawTime = description[kIOPSTimeToEmptyKey as String] as? Int
            timeRemainingMinutes = (rawTime ?? 0) > 0 ? rawTime : nil
            return
        }

        clearInternal()
    }

    private func readBluetoothHIDDevices() -> [ZestBatteryDevice] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var results: [ZestBatteryDevice] = []
        var service = IOIteratorNext(iterator)

        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var propertiesRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propertiesRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let properties = propertiesRef?.takeRetainedValue() as? [String: Any] else { continue }

            let transport = (properties["Transport"] as? String)?.lowercased() ?? ""
            guard transport.contains("bluetooth") else { continue }

            let rawBattery = properties["BatteryPercent"] ?? properties["BatteryLevel"] ?? properties["Battery"]
            let batteryValue: Int?
            if let number = rawBattery as? NSNumber { batteryValue = number.intValue }
            else if let value = rawBattery as? Int { batteryValue = value }
            else { batteryValue = nil }

            guard let percent = batteryValue, (0...100).contains(percent) else { continue }

            let product = (properties["Product"] as? String)
                ?? (properties["ProductName"] as? String)
                ?? "Bluetooth Device"
            let address = (properties["DeviceAddress"] as? String)
                ?? (properties["SerialNumber"] as? String)
                ?? product

            let lower = product.lowercased()
            let category: ZestBatteryDeviceCategory
            if ["airpod", "headphone", "headset", "earbud", "speaker"].contains(where: lower.contains) {
                category = .audio
            } else if ["keyboard", "mouse", "trackpad", "pointer"].contains(where: lower.contains) {
                category = .input
            } else {
                category = .other
            }

            results.append(
                ZestBatteryDevice(
                    id: "hid-\(address)",
                    name: product,
                    percentage: percent,
                    isCharging: false,
                    category: category
                )
            )
        }

        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func clearInternal() {
        hasBattery = false
        percentage = nil
        isCharging = false
        isOnACPower = false
        timeRemainingMinutes = nil
        name = nil
    }
}
