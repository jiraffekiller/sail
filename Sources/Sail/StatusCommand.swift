import Foundation
import SailCore

/// `Sail --status`: print everything the app knows, then exit. For debugging and for the
/// README's "is it working?" check.
enum StatusCommand {
    static func run() {
        let monitor = BatteryMonitor()
        let controller = ChargeController()
        let store = Store()
        let config = store.loadConfig()
        let state = store.loadState()

        print("\(SailIDs.appName) status")
        print("  config file:   \(store.directory.path)/config.json")
        print("  sailing:       \(config.sailingEnabled ? "on" : "off"), charge to \(config.upperLimit)%, recharge below \(config.lowerLimit)%")
        print("  heat:          \(config.heatEnabled ? "on" : "off"), pause above \(config.heatMaxC) °C, hysteresis \(config.heatHysteresisC) °C")
        if let s = state { print("  state:         \(s.phase.rawValue)\(s.heatHold ? " + heat hold" : "")") }
        if let s = monitor.sample() {
            print("  battery:       \(s.percent)% ext=\(s.externalConnected) charging=\(s.isCharging) temp=\(s.temperatureC.map { String(format: "%.1f °C", $0) } ?? "n/a")")
            if let d = monitor.details() { print("  amperage:      \(d.amperageMA) mA, notChargingReason=0x\(String(d.notChargingReason, radix: 16))") }
            let decision = Policy.step(state: state ?? Policy.initialState(config: config, sample: s), config: config, sample: s)
            print("  decision:      limit \(decision.desiredLimit)% (\(decision.reason))")
        } else {
            print("  battery:       not readable")
        }
        print("  PowerUI:       \(controller.powerUIAvailable ? "available" : "UNAVAILABLE")")
        if let a = controller.readActual() {
            print("  powerd limit:  \(a.limit)% enabled=\(a.enabled) uiState=\(a.uiState.map(String.init) ?? "n/a")")
        }
        if let obc = controller.optimizedChargingEnabled() { print("  optimized charging: \(obc ? "ON (turn it off)" : "off")") }
        let helper = controller.helper
        if helper.isInstalled {
            print("  helper:        installed, version \(helper.version().map(String.init) ?? "not responding")")
            if let st = helper.storedLimit() { print("  helper stored: mclLimitValue=\(st.limit) MCLFeatureState=\(st.enabled)") }
        } else {
            print("  helper:        not installed (limits below 80% unavailable)")
        }
        print("  login item:    \(LoginItem.isEnabled ? "enabled" : "disabled")")
    }
}
