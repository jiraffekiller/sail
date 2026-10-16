import AppKit

// Command-line modes (no UI): `--status`, `--login-item on|off|status`.
let args = CommandLine.arguments
if args.contains("--status") {
    StatusCommand.run()
    exit(0)
}
if let i = args.firstIndex(of: "--login-item") {
    let mode = i + 1 < args.count ? args[i + 1] : "status"
    switch mode {
    case "on":
        do { try LoginItem.enable(); print("launch at login enabled") } catch { print("error: \(error.localizedDescription)"); exit(1) }
    case "off":
        LoginItem.disable(); print("launch at login disabled")
    default:
        print(LoginItem.isEnabled ? "enabled" : (LoginItem.requiresApproval ? "requires approval in System Settings" : "disabled"))
    }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
