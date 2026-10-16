import XCTest
@testable import SailCore

final class PolicyTests: XCTestCase {
    let cfg = PolicyConfig(sailingEnabled: true, upperLimit: 80, lowerLimit: 70,
                           heatEnabled: true, heatMaxC: 35, heatHysteresisC: 3, safetyFloor: 20)

    func sample(_ p: Int, temp: Double? = 28, plugged: Bool = true) -> BatterySample {
        BatterySample(percent: p, externalConnected: plugged, isCharging: plugged, temperatureC: temp)
    }

    func testInitialStateDependsOnLevel() {
        XCTAssertEqual(Policy.initialState(config: cfg, sample: sample(50)).phase, .charging)
        XCTAssertEqual(Policy.initialState(config: cfg, sample: sample(80)).phase, .holding)
        XCTAssertEqual(Policy.initialState(config: cfg, sample: sample(95)).phase, .holding)
    }

    func testChargesToUpperThenHolds() {
        var s = PolicyState(phase: .charging)
        var d = Policy.step(state: s, config: cfg, sample: sample(50))
        XCTAssertEqual(d.desiredLimit, 80)
        s = d.state
        d = Policy.step(state: s, config: cfg, sample: sample(79))
        XCTAssertEqual(d.desiredLimit, 80)
        XCTAssertEqual(d.state.phase, .charging)
        d = Policy.step(state: d.state, config: cfg, sample: sample(80))
        XCTAssertEqual(d.state.phase, .holding)
        XCTAssertEqual(d.desiredLimit, 80)
    }

    func testHoldingFollowsBatteryDownAndNeverTopsUp() {
        var s = PolicyState(phase: .holding)
        for p in [79, 76, 73, 71] {
            let d = Policy.step(state: s, config: cfg, sample: sample(p, plugged: false))
            XCTAssertEqual(d.desiredLimit, p, "hold must track the current level at \(p)")
            XCTAssertEqual(d.state.phase, .holding)
            s = d.state
        }
        // Re-plugged at 71: still holding, no top-up.
        let d = Policy.step(state: s, config: cfg, sample: sample(71))
        XCTAssertEqual(d.desiredLimit, 71)
    }

    func testResumesChargingAtLowerLimit() {
        let s = PolicyState(phase: .holding)
        let d = Policy.step(state: s, config: cfg, sample: sample(70))
        XCTAssertEqual(d.state.phase, .charging)
        XCTAssertEqual(d.desiredLimit, 80)
    }

    func testHoldingAboveUpperDoesNotDischarge() {
        // Apple's own calibration can push the battery to 100; we hold, we do not drain.
        let d = Policy.step(state: PolicyState(phase: .holding), config: cfg, sample: sample(100))
        XCTAssertEqual(d.desiredLimit, 100)
        XCTAssertEqual(d.state.phase, .holding)
    }

    func testDesiredNeverBelowCurrentPercentInNormalOperation() {
        var s = PolicyState(phase: .charging)
        for p in stride(from: 20, through: 100, by: 1) {
            let d = Policy.step(state: s, config: cfg, sample: sample(p))
            XCTAssertGreaterThanOrEqual(d.desiredLimit, p, "at \(p)% desired \(d.desiredLimit) would discharge")
            s = d.state
        }
    }

    func testHeatHoldWithHysteresis() {
        var s = PolicyState(phase: .charging)
        var d = Policy.step(state: s, config: cfg, sample: sample(50, temp: 36))
        XCTAssertTrue(d.state.heatHold)
        XCTAssertEqual(d.desiredLimit, 50)
        s = d.state
        // 33 °C is inside the hysteresis band: still holding.
        d = Policy.step(state: s, config: cfg, sample: sample(51, temp: 33))
        XCTAssertTrue(d.state.heatHold)
        XCTAssertEqual(d.desiredLimit, 51)
        // 32 °C releases.
        d = Policy.step(state: d.state, config: cfg, sample: sample(51, temp: 32))
        XCTAssertFalse(d.state.heatHold)
        XCTAssertEqual(d.desiredLimit, 80)
    }

    func testHeatBeatsPauseAndOff() {
        var c = cfg
        c.sailingEnabled = false
        let d = Policy.step(state: PolicyState(phase: .charging), config: c, sample: sample(60, temp: 40))
        XCTAssertEqual(d.desiredLimit, 60)
        c.sailingEnabled = true
        c.pausedUntil = Date().addingTimeInterval(3600)
        let d2 = Policy.step(state: PolicyState(phase: .charging), config: c, sample: sample(60, temp: 40))
        XCTAssertEqual(d2.desiredLimit, 60)
    }

    func testHeatDisabledIgnoresTemperature() {
        var c = cfg
        c.heatEnabled = false
        let d = Policy.step(state: PolicyState(phase: .charging), config: c, sample: sample(60, temp: 45))
        XCTAssertFalse(d.state.heatHold)
        XCTAssertEqual(d.desiredLimit, 80)
    }

    func testMissingTemperatureNeverHolds() {
        let d = Policy.step(state: PolicyState(phase: .charging, heatHold: true), config: cfg, sample: sample(60, temp: nil))
        XCTAssertFalse(d.state.heatHold)
    }

    func testPauseChargesToFullAndExpires() {
        var c = cfg
        let now = Date()
        c.pausedUntil = now.addingTimeInterval(60)
        XCTAssertEqual(Policy.step(state: PolicyState(phase: .holding), config: c, sample: sample(75), now: now).desiredLimit, 100)
        XCTAssertEqual(Policy.step(state: PolicyState(phase: .holding), config: c, sample: sample(75), now: now.addingTimeInterval(61)).desiredLimit, 75)
    }

    func testSailingOffChargesToFull() {
        var c = cfg
        c.sailingEnabled = false
        XCTAssertEqual(Policy.step(state: PolicyState(phase: .holding), config: c, sample: sample(75)).desiredLimit, 100)
    }

    func testSafetyFloorAlwaysCharges() {
        let d = Policy.step(state: PolicyState(phase: .holding, heatHold: true), config: cfg, sample: sample(10, temp: 45))
        XCTAssertEqual(d.desiredLimit, 80)
    }

    func testNormalizationKeepsLowerBelowUpper() {
        var c = cfg
        c.upperLimit = 60
        c.lowerLimit = 75
        let n = c.normalized
        XCTAssertEqual(n.upperLimit, 60)
        XCTAssertEqual(n.lowerLimit, 59)
        c.upperLimit = 10
        XCTAssertEqual(c.normalized.upperLimit, 25)
    }
}
