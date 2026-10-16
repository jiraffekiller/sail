import Foundation
import IOKit
import IOKit.ps
import AppKit
import SailCore
import CSMC

/// Reads battery state from the IORegistry and temperature from the SMC, and fires
/// `onChange` on power-source events and on wake from sleep.
final class BatteryMonitor {
    var onChange: (() -> Void)?

    private var powerSource: CFRunLoopSource?
    private var wakeObserver: NSObjectProtocol?

    func start() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx = ctx else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue().onChange?()
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            powerSource = src
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onChange?()
        }
    }

    /// nil when the registry has no battery (should not happen on a MacBook).
    func sample() -> BatterySample? {
        guard let props = registryProperties(), let percent = props["CurrentCapacity"] as? Int else { return nil }
        return BatterySample(percent: percent,
                             externalConnected: props["ExternalConnected"] as? Bool ?? false,
                             isCharging: props["IsCharging"] as? Bool ?? false,
                             temperatureC: temperature())
    }

    /// Extra diagnostics for the menu and `--status`.
    struct Details {
        var amperageMA: Int
        var notChargingReason: Int
    }

    func details() -> Details? {
        guard let props = registryProperties() else { return nil }
        // IOKit hands Amperage over as a signed 64-bit CFNumber: negative while discharging.
        let amp = (props["Amperage"] as? Int) ?? 0
        let reason = (props["ChargerData"] as? [String: Any])?["NotChargingReason"] as? Int ?? 0
        return Details(amperageMA: amp, notChargingReason: reason)
    }

    /// Hottest of the three battery thermistors, °C.
    func temperature() -> Double? {
        var best: Float?
        for key in ["TB0T", "TB1T", "TB2T"] {
            var v: Float = 0
            if csmc_read_float(key, &v), v > -40, v < 120 {
                best = max(best ?? v, v)
            }
        }
        return best.map(Double.init)
    }

    private func registryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict
    }
}
