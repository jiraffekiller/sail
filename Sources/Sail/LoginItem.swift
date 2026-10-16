import Foundation
import ServiceManagement
import SailCore

/// Launch-at-login via `SMAppService.agent`: the LaunchAgent plist ships inside the app
/// bundle (Contents/Library/LaunchAgents), so System Settings lists the job under the app
/// with its icon, and launchd supervises it (RunAtLoad, restart after a crash but not
/// after a normal Quit). The agent runs with `--agent`, which makes that instance the
/// authoritative one (see AppDelegate.enforceSingleInstance).
enum LoginItem {
    private static let plistName = "\(SailIDs.agentLabel).plist"
    private static var service: SMAppService { .agent(plistName: plistName) }

    /// Plist location used by versions before SMAppService; removed on first enable.
    private static var legacyPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(plistName)")
    }

    static var status: SMAppService.Status { service.status }
    static var isEnabled: Bool { status == .enabled }
    static var requiresApproval: Bool { status == .requiresApproval }

    /// The agent must point at a stable location, so this is only offered once the app
    /// lives in /Applications.
    static var isInstalledInApplications: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/") && Bundle.main.bundleIdentifier != nil
    }

    static func enable() throws {
        guard isInstalledInApplications else {
            throw NSError(domain: SailIDs.appBundleID, code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Move \(SailIDs.appName).app to /Applications first."])
        }
        removeLegacyAgent()
        try service.register()
    }

    static func disable() {
        removeLegacyAgent()
        try? service.unregister()
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Unloads and deletes a ~/Library/LaunchAgents plist left by older builds, before the
    /// SMAppService job with the same label is registered. Synchronous on purpose: a
    /// detached unload would race the new registration and remove it too.
    private static func removeLegacyAgent() {
        guard FileManager.default.fileExists(atPath: legacyPlistURL.path) else { return }
        try? FileManager.default.removeItem(at: legacyPlistURL)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", "gui/\(getuid())/\(SailIDs.agentLabel)"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}
