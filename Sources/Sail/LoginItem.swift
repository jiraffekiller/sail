import Foundation
import SailCore

/// Launch-at-login via a per-user LaunchAgent that launchd supervises: RunAtLoad starts
/// the app at login, KeepAlive/SuccessfulExit=false restarts it after a crash but not
/// after a normal Quit. The agent passes `--agent`, which makes that instance the
/// authoritative one (see AppDelegate.enforceSingleInstance).
enum LoginItem {
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(SailIDs.agentLabel).plist")
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    /// The agent must point at a stable location, so this is only offered once the app
    /// lives in /Applications.
    static var isInstalledInApplications: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/") && Bundle.main.bundleIdentifier != nil
    }

    static func enable() throws {
        guard isInstalledInApplications, let exe = Bundle.main.executableURL else {
            throw NSError(domain: SailIDs.appBundleID, code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Move \(SailIDs.appName).app to /Applications first."])
        }
        let plist: [String: Any] = [
            "Label": SailIDs.agentLabel,
            "ProgramArguments": [exe.path, "--agent"],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            // Lets System Settings > Login Items show this job as "Sail" with the app icon.
            "AssociatedBundleIdentifiers": [SailIDs.appBundleID],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: plistURL, options: .atomic)
        reload()
    }

    /// (Re)loads the agent so launchd picks up the plist. Runs detached, because when the
    /// caller is the agent instance itself, `bootout` kills it before `bootstrap` could run.
    private static func reload() {
        let uid = getuid()
        let script = "sleep 1; /bin/launchctl bootout gui/\(uid)/\(SailIDs.agentLabel) 2>/dev/null; /bin/launchctl bootstrap gui/\(uid) '\(plistURL.path)'"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// Removing the plist is enough: nothing loads at next login, and a normal Quit is not
    /// restarted. The currently loaded job is left alone so the running app survives.
    static func disable() {
        try? FileManager.default.removeItem(at: plistURL)
    }

    @discardableResult
    static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
