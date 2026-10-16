import Foundation
import SailCore
import CPowerUI

/// The one write primitive the app needs: steer powerd's manual charge limit to `n`.
/// Prefers the root helper (any value 1...100); falls back to PowerUI's XPC entry point,
/// which only accepts 80...100.
final class ChargeController {
    let helper = HelperClient()

    enum Backend: String { case helper, powerUI }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = d }
    }

    struct Actual {
        var limit: Int
        var enabled: Bool
        var uiState: Int?
    }

    var powerUIAvailable: Bool { cpui_available() }

    /// What PowerUIAgent currently enforces (reflects root's mclLimitValue).
    func readActual() -> Actual? {
        var limit: UInt8 = 0
        var enabled = false
        guard cpui_get_limit(&limit, &enabled) else { return nil }
        var state: UInt = 0
        let haveState = cpui_ui_state(&state)
        return Actual(limit: Int(limit), enabled: enabled, uiState: haveState ? Int(state) : nil)
    }

    func optimizedChargingEnabled() -> Bool? {
        var e = false
        return cpui_optimized_charging_enabled(&e) ? e : nil
    }

    func setLimit(_ n: Int) -> Result<Backend, Failure> {
        let n = min(max(n, 1), 100)
        switch helper.setChargeLimit(n) {
        case .success:
            return .success(.helper)
        case .failure(let err):
            if case .notInstalled = err {} else {
                Log.control.error("helper failed: \(err.description, privacy: .public)")
            }
            guard n >= 80 else {
                return .failure(Failure("\(err.description); limits below 80% need the helper"))
            }
            var buf = [CChar](repeating: 0, count: 256)
            let rc = cpui_set_limit(UInt8(n), &buf, buf.count)
            if rc == 0 { return .success(.powerUI) }
            return .failure(Failure("\(err.description); PowerUI: \(String(cString: buf))"))
        }
    }
}
