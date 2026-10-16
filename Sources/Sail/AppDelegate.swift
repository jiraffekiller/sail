import AppKit
import SailCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True for the launchd-spawned copy: either our explicit flag or launchd's own marker.
    let isAgent = CommandLine.arguments.contains("--agent")
        || ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == SailIDs.agentLabel
    private var reconciler: Reconciler!
    private var statusMenu: StatusMenu!
    private var setup: SetupWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        enforceSingleInstance()
        NSApp.setActivationPolicy(.accessory)

        let store = Store()
        reconciler = Reconciler(monitor: BatteryMonitor(), controller: ChargeController(), store: store)
        statusMenu = StatusMenu(reconciler: reconciler, app: self)
        reconciler.onUpdate = { [weak self] in self?.statusMenu.refreshTitle() }
        Log.app.notice("\(SailIDs.appName) starting (agent: \(self.isAgent)) config in \(store.directory.path, privacy: .public)")
        reconciler.start()

        setup = SetupWindowController(reconciler: reconciler)
        let report = Compatibility.check(monitor: reconciler.monitor, controller: reconciler.controller)
        if !SetupModel.isCompleted || !report.supported || !reconciler.controller.helper.isInstalled {
            showSetup()
        }
    }

    func showSetup() { setup.show() }

    /// Exactly one Sail runs per user. The launchd-spawned copy (`--agent`) wins: it asks any
    /// other copy to quit and takes over. A manually launched copy yields to a running one.
    private func enforceSingleInstance() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard !others.isEmpty else { return }
        if isAgent {
            others.forEach { $0.terminate() }
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline, others.contains(where: { !$0.isTerminated }) {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
        } else {
            Log.app.notice("another instance is running, exiting")
            exit(0)
        }
    }

    func alert(_ title: String, _ message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
