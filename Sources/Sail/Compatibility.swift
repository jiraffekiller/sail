import Foundation
import AppKit
import SailCore
import CPowerUI

/// Everything Sail needs to check before it can promise to work on this Mac, plus the
/// things that fight with it. Pure reads; used by the Setup window and the menu.
enum Compatibility {
    struct Report {
        var appleSilicon: Bool
        var osVersion: OperatingSystemVersion
        var osSupported: Bool
        var chargeLimitSupported: Bool
        var batteryPresent: Bool
        var optimizedChargingOn: Bool?
        var competingLimiters: [String]

        var supported: Bool { appleSilicon && osSupported && chargeLimitSupported && batteryPresent }

        var osVersionString: String {
            "\(osVersion.majorVersion).\(osVersion.minorVersion)" + (osVersion.patchVersion > 0 ? ".\(osVersion.patchVersion)" : "")
        }
    }

    static let minimumOS = OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)

    static func check(monitor: BatteryMonitor, controller: ChargeController) -> Report {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return Report(
            appleSilicon: isAppleSilicon,
            osVersion: os,
            osSupported: ProcessInfo.processInfo.isOperatingSystemAtLeast(minimumOS),
            chargeLimitSupported: controller.powerUIAvailable,
            batteryPresent: monitor.sample() != nil,
            optimizedChargingOn: controller.optimizedChargingEnabled(),
            competingLimiters: competingLimiters()
        )
    }

    static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    /// Other tools that write the same charge limit. Two writers fight each other.
    static func competingLimiters() -> [String] {
        var found: [String] = []
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        if running.contains(where: { $0.hasPrefix("com.apphousekitchen.aldente") }) { found.append("AlDente") }
        if FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/cc.chlc.batt.plist")
            || FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/homebrew.mxcl.batt.plist") {
            found.append("batt")
        }
        return found
    }

    /// Deep link to System Settings > Battery, where Optimized Battery Charging lives.
    static func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
