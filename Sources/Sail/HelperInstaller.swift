import Foundation
import AppKit
import SailCore

/// Installs the privileged helper from inside the app bundle using the system's
/// administrator prompt (osascript "with administrator privileges"). Equivalent to
/// `make install-helper` from a terminal.
enum HelperInstaller {
    enum Failure: Error, CustomStringConvertible {
        case notBundled
        case failed(String)
        var description: String {
            switch self {
            case .notBundled: return "Run the installed \(SailIDs.appName).app bundle; the helper files are inside it."
            case .failed(let m): return m
            }
        }
    }

    static var scriptURL: URL? { Bundle.main.url(forResource: "install-helper", withExtension: "sh") }
    static var uninstallScriptURL: URL? { Bundle.main.url(forResource: "uninstall-helper", withExtension: "sh") }
    static var plistURL: URL? { Bundle.main.url(forResource: SailIDs.helperLabel, withExtension: "plist") }
    static var helperURL: URL? { Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("SailHelper") }

    static func install() throws {
        guard let script = scriptURL, let plist = plistURL, let helper = helperURL,
              FileManager.default.fileExists(atPath: helper.path) else { throw Failure.notBundled }
        try runAsAdmin("/bin/sh \(q(script.path)) \(q(plist.path)) \(q(helper.path))")
    }

    static func uninstall() throws {
        guard let script = uninstallScriptURL else { throw Failure.notBundled }
        try runAsAdmin("/bin/sh \(q(script.path))")
    }

    private static func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    private static func runAsAdmin(_ shell: String) throws {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw Failure.failed("could not build install script") }
        script.executeAndReturnError(&error)
        if let error = error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -128 { throw Failure.failed("cancelled") }
            throw Failure.failed((error[NSAppleScript.errorMessage] as? String) ?? "osascript failed (\(code))")
        }
    }
}
