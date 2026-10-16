import Foundation

/// User-facing settings. Persisted as JSON by the app.
public struct PolicyConfig: Codable, Equatable {
    /// Master switch for Sailing mode. Off means "let macOS charge to 100 %".
    public var sailingEnabled: Bool
    /// Charge up to this level, then stop.
    public var upperLimit: Int
    /// Do not charge again until the battery has drained to this level.
    public var lowerLimit: Int
    /// Stop charging while the battery is hot.
    public var heatEnabled: Bool
    /// Battery temperature (°C) at which charging is paused.
    public var heatMaxC: Double
    /// Charging resumes once the temperature is below `heatMaxC - heatHysteresisC`.
    public var heatHysteresisC: Double
    /// Below this level the app always allows charging, whatever else is going on.
    public var safetyFloor: Int
    /// While set and in the future, Sailing is suspended and the battery charges to 100 %.
    public var pausedUntil: Date?

    public init(sailingEnabled: Bool = true,
                upperLimit: Int = 80,
                lowerLimit: Int = 70,
                heatEnabled: Bool = true,
                heatMaxC: Double = 35,
                heatHysteresisC: Double = 3,
                safetyFloor: Int = 20,
                pausedUntil: Date? = nil) {
        self.sailingEnabled = sailingEnabled
        self.upperLimit = upperLimit
        self.lowerLimit = lowerLimit
        self.heatEnabled = heatEnabled
        self.heatMaxC = heatMaxC
        self.heatHysteresisC = heatHysteresisC
        self.safetyFloor = safetyFloor
        self.pausedUntil = pausedUntil
    }

    public static let `default` = PolicyConfig()

    /// Clamps every field into a sane range and keeps lower < upper.
    public var normalized: PolicyConfig {
        var c = self
        c.safetyFloor = min(max(c.safetyFloor, 5), 50)
        c.upperLimit = min(max(c.upperLimit, c.safetyFloor + 5), 100)
        c.lowerLimit = min(max(c.lowerLimit, c.safetyFloor), c.upperLimit - 1)
        c.heatMaxC = min(max(c.heatMaxC, 25), 50)
        c.heatHysteresisC = min(max(c.heatHysteresisC, 1), 10)
        return c
    }

    public func isPaused(at now: Date) -> Bool {
        guard let until = pausedUntil else { return false }
        return until > now
    }
}

public enum Phase: String, Codable {
    /// Heading up to `upperLimit`.
    case charging
    /// Sitting at or drifting down from `upperLimit`; no top-ups until `lowerLimit`.
    case holding
}

/// The only memory the policy needs between ticks. Persisted so a restart does not
/// turn a `holding` battery back into a `charging` one.
public struct PolicyState: Codable, Equatable {
    public var phase: Phase
    public var heatHold: Bool

    public init(phase: Phase, heatHold: Bool = false) {
        self.phase = phase
        self.heatHold = heatHold
    }
}

public struct BatterySample: Equatable {
    public var percent: Int
    public var externalConnected: Bool
    public var isCharging: Bool
    /// Battery temperature in °C, nil when the sensor could not be read.
    public var temperatureC: Double?

    public init(percent: Int, externalConnected: Bool, isCharging: Bool, temperatureC: Double?) {
        self.percent = percent
        self.externalConnected = externalConnected
        self.isCharging = isCharging
        self.temperatureC = temperatureC
    }
}

public struct Decision: Equatable {
    public var state: PolicyState
    /// What powerd should steer the battery to. Above it powerd discharges, below it
    /// charges, at it holds. Never below the current percent except on purpose.
    public var desiredLimit: Int
    /// Human-readable explanation for the menu and the log.
    public var reason: String
}

/// Pure decision logic. No I/O, fully unit-tested.
public enum Policy {
    public static func initialState(config: PolicyConfig, sample: BatterySample) -> PolicyState {
        let c = config.normalized
        return PolicyState(phase: sample.percent >= c.upperLimit ? .holding : .charging, heatHold: false)
    }

    public static func step(state: PolicyState,
                            config: PolicyConfig,
                            sample: BatterySample,
                            now: Date = Date()) -> Decision {
        let c = config.normalized
        var s = state
        let p = min(max(sample.percent, 0), 100)

        // Heat protection: hysteresis around heatMaxC.
        if c.heatEnabled, let t = sample.temperatureC {
            if t >= c.heatMaxC {
                s.heatHold = true
            } else if t <= c.heatMaxC - c.heatHysteresisC {
                s.heatHold = false
            }
        } else {
            s.heatHold = false
        }

        // Sailing phase transitions.
        if p >= c.upperLimit {
            s.phase = .holding
        } else if p <= c.lowerLimit {
            s.phase = .charging
        }

        // Safety first: a nearly empty battery always charges.
        if p < c.safetyFloor {
            return Decision(state: s, desiredLimit: c.sailingEnabled ? c.upperLimit : 100,
                            reason: "below safety floor, charging")
        }
        // Heat protection beats everything else, including pause and "sailing off".
        if s.heatHold {
            return Decision(state: s, desiredLimit: p, reason: "battery hot, holding")
        }
        if c.isPaused(at: now) {
            return Decision(state: s, desiredLimit: 100, reason: "paused, charging to full")
        }
        if !c.sailingEnabled {
            return Decision(state: s, desiredLimit: 100, reason: "sailing off")
        }
        switch s.phase {
        case .charging:
            return Decision(state: s, desiredLimit: c.upperLimit, reason: "charging to \(c.upperLimit)%")
        case .holding:
            // Follow the battery down so that re-plugging never tops it up.
            return Decision(state: s, desiredLimit: p, reason: "holding until \(c.lowerLimit)%")
        }
    }
}
