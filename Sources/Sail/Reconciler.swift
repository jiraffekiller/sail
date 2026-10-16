import Foundation
import SailCore

/// Desired-state loop. Every tick: sample the battery, ask the policy what powerd should
/// steer to, compare with what powerd actually enforces, write only on a difference.
/// Runs on the main thread; triggered by a timer, power events, wake, and config edits.
final class Reconciler {
    let monitor: BatteryMonitor
    let controller: ChargeController
    let store: Store

    private(set) var config: PolicyConfig
    private(set) var state: PolicyState?

    struct Snapshot {
        var sample: BatterySample?
        var details: BatteryMonitor.Details?
        var decision: Decision?
        var actual: ChargeController.Actual?
        var lastWrite: (limit: Int, backend: ChargeController.Backend, at: Date)?
        var lastError: String?
        var updatedAt: Date
    }
    private(set) var snapshot = Snapshot(updatedAt: .distantPast)

    var onUpdate: (() -> Void)?

    private var timer: Timer?
    private var debounce: Timer?
    private var nextWriteAllowed = Date.distantPast
    private var consecutiveFailures = 0
    static let interval: TimeInterval = 30

    init(monitor: BatteryMonitor, controller: ChargeController, store: Store) {
        self.monitor = monitor
        self.controller = controller
        self.store = store
        self.config = store.loadConfig()
        self.state = store.loadState()
    }

    func start() {
        monitor.onChange = { [weak self] in self?.scheduleTick(after: 2) }
        monitor.start()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 5
        tick()
    }

    func update(_ change: (inout PolicyConfig) -> Void) {
        var c = config
        change(&c)
        config = c.normalized
        store.save(config: config)
        Log.app.notice("config changed: upper \(self.config.upperLimit) lower \(self.config.lowerLimit) sailing \(self.config.sailingEnabled) heat \(self.config.heatEnabled) at \(self.config.heatMaxC)°C")
        nextWriteAllowed = .distantPast
        tick()
    }

    func scheduleTick(after seconds: TimeInterval) {
        debounce?.invalidate()
        debounce = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in self?.tick() }
    }

    func tick() {
        var snap = Snapshot(updatedAt: Date())
        snap.lastWrite = snapshot.lastWrite
        defer {
            snapshot = snap
            onUpdate?()
        }

        guard let sample = monitor.sample() else {
            snap.lastError = "battery not readable"
            Log.control.error("battery not readable")
            return
        }
        snap.sample = sample
        snap.details = monitor.details()

        let previous = state ?? Policy.initialState(config: config, sample: sample)
        let decision = Policy.step(state: previous, config: config, sample: sample)
        if decision.state != state {
            state = decision.state
            store.save(state: decision.state)
            Log.control.notice("state -> \(decision.state.phase.rawValue, privacy: .public) heatHold=\(decision.state.heatHold) (\(decision.reason, privacy: .public))")
        }
        snap.decision = decision

        let actual = controller.readActual()
        snap.actual = actual
        if actual == nil {
            snap.lastError = "PowerUI unavailable: cannot read the current limit"
        }

        let inSync = actual.map { $0.limit == decision.desiredLimit && $0.enabled } ?? false
        guard !inSync, Date() >= nextWriteAllowed else { return }

        switch controller.setLimit(decision.desiredLimit) {
        case .success(let backend):
            consecutiveFailures = 0
            nextWriteAllowed = Date().addingTimeInterval(5)
            snap.lastWrite = (decision.desiredLimit, backend, Date())
            snap.lastError = nil
            Log.control.notice("limit \(actual?.limit ?? -1) -> \(decision.desiredLimit) via \(backend.rawValue, privacy: .public): \(decision.reason, privacy: .public)")
        case .failure(let failure):
            let message = failure.description
            consecutiveFailures += 1
            // Back off: 30 s, 60 s, 120 s ... capped at 10 minutes.
            let delay = min(600, 30 * pow(2, Double(consecutiveFailures - 1)))
            nextWriteAllowed = Date().addingTimeInterval(delay)
            snap.lastError = message
            Log.control.error("could not set limit \(decision.desiredLimit): \(message, privacy: .public)")
        }
    }
}
