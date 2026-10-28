//
//  ZestBatteryService.swift
//  Zest
//
//  0.1.1 — public IOKit battery layer
//

import Foundation
import IOKit.ps
import Combine

@MainActor
final class ZestBatteryService: ObservableObject {
    static let shared = ZestBatteryService()

    @Published private(set) var hasBattery = false
    @Published private(set) var percentage: Int?
    @Published private(set) var isCharging = false
    @Published private(set) var isOnACPower = false
    @Published private(set) var timeRemainingMinutes: Int?
    @Published private(set) var name: String?

    private var timer: Timer?

    private init() {
        refresh()

        timer = Timer.scheduledTimer(
            withTimeInterval: 30,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?
                .takeRetainedValue() as? [CFTypeRef] else {
            clear()
            return
        }

        for source in list {
            guard let unmanaged =
                    IOPSGetPowerSourceDescription(blob, source),
                  let description =
                    unmanaged.takeUnretainedValue()
                        as? [String: Any] else {
                continue
            }

            let type =
                description[kIOPSTypeKey as String] as? String

            guard type == (kIOPSInternalBatteryType as String) else {
                continue
            }

            hasBattery = true

            let current =
                description[kIOPSCurrentCapacityKey as String]
                    as? Int ?? 0

            let max =
                description[kIOPSMaxCapacityKey as String]
                    as? Int ?? 100

            percentage =
                max > 0
                ? Int(
                    (Double(current) /
                     Double(max) * 100).rounded()
                )
                : nil

            isCharging =
                description[kIOPSIsChargingKey as String]
                    as? Bool ?? false

            let state =
                description[kIOPSPowerSourceStateKey as String]
                    as? String

            isOnACPower =
                state == (kIOPSACPowerValue as String)

            name =
                description[kIOPSNameKey as String]
                    as? String

            let rawTime =
                description[kIOPSTimeToEmptyKey as String]
                    as? Int

            if let rawTime, rawTime > 0 {
                timeRemainingMinutes = rawTime
            } else {
                timeRemainingMinutes = nil
            }

            return
        }

        clear()
    }

    private func clear() {
        hasBattery = false
        percentage = nil
        isCharging = false
        isOnACPower = false
        timeRemainingMinutes = nil
        name = nil
    }
}
