import AppKit
import SailCore

/// The whole UI: a menu bar item whose menu is rebuilt each time it opens.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let menu = NSMenu()
    private let reconciler: Reconciler
    private unowned let app: AppDelegate
    private var upperRow: SliderRow!
    private var lowerRow: SliderRow!

    init(reconciler: Reconciler, app: AppDelegate) {
        self.reconciler = reconciler
        self.app = app
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.delegate = self
        item.menu = menu
        item.button?.imagePosition = .imageOnly
        refreshTitle()
    }

    func refreshTitle() {
        let snap = reconciler.snapshot
        let symbol: String
        if snap.lastError != nil {
            symbol = "exclamationmark.triangle.fill"
        } else if snap.decision?.state.heatHold == true {
            symbol = "flame.fill"
        } else {
            symbol = "sailboat.fill"
        }
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: SailIDs.appName)
        item.button?.title = ""
        item.button?.toolTip = tooltip()
    }

    private func tooltip() -> String {
        let snap = reconciler.snapshot
        var lines: [String] = []
        if let b = snap.sample { lines.append("\(b.percent)%" + (b.temperatureC.map { String(format: " · %.1f °C", $0) } ?? "")) }
        if let d = snap.decision { lines.append(d.reason) }
        if let a = snap.actual { lines.append("powerd limit: \(a.limit)%") }
        if let e = snap.lastError { lines.append("Problem: \(e)") }
        return lines.joined(separator: "\n")
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let cfg = reconciler.config
        let snap = reconciler.snapshot

        // Status block (disabled items).
        var status = snap.sample.map { s in
            var t = "\(s.percent)%"
            t += s.externalConnected ? (s.isCharging ? " · charging" : " · on power, not charging") : " · on battery"
            if let d = snap.details, d.amperageMA != 0 { t += String(format: " · %+.2f A", Double(d.amperageMA) / 1000) }
            return t
        } ?? "Battery not readable"
        if let t = snap.sample?.temperatureC { status += String(format: " · %.1f °C", t) }
        menu.addItem(disabled(status))
        if let d = snap.decision {
            var line = "Sail: \(d.reason)"
            if let a = snap.actual {
                line += a.limit == d.desiredLimit ? " · limit \(a.limit)%" : " · limit \(a.limit)% → \(d.desiredLimit)%"
            }
            menu.addItem(disabled(line))
        }
        if let e = snap.lastError { menu.addItem(disabled("⚠︎ \(e)")) }
        if reconciler.controller.optimizedChargingEnabled() == true {
            menu.addItem(disabled("⚠︎ Optimized Battery Charging is on in System Settings"))
        }
        menu.addItem(.separator())

        // Sailing.
        let sailing = NSMenuItem(title: "Sailing mode", action: #selector(toggleSailing), keyEquivalent: "")
        sailing.target = self
        sailing.state = cfg.sailingEnabled ? .on : .off
        menu.addItem(sailing)
        upperRow = SliderRow(title: "Charge to", min: 50, max: 100, step: 5, value: cfg.upperLimit) { "\($0)%" }
        lowerRow = SliderRow(title: "Recharge below", min: 20, max: 95, step: 5, value: cfg.lowerLimit) { "\($0)%" }
        upperRow.onCommit = { [weak self] v in self?.commitUpper(v) }
        lowerRow.onCommit = { [weak self] v in self?.commitLower(v) }
        upperRow.isEnabled = cfg.sailingEnabled
        lowerRow.isEnabled = cfg.sailingEnabled
        menu.addItem(viewItem(upperRow))
        menu.addItem(viewItem(lowerRow))
        menu.addItem(.separator())

        // Heat: same shape as Sailing, a checkmark item plus a slider row.
        let heat = NSMenuItem(title: "Heat protection", action: #selector(toggleHeat), keyEquivalent: "")
        heat.target = self
        heat.state = cfg.heatEnabled ? .on : .off
        menu.addItem(heat)
        let heatRow = SliderRow(title: "Pause above", min: 30, max: 45, step: 1, value: Int(cfg.heatMaxC)) { "\($0) °C" }
        heatRow.isEnabled = cfg.heatEnabled
        heatRow.onCommit = { [weak self] v in self?.reconciler.update { $0.heatMaxC = Double(v) } }
        menu.addItem(viewItem(heatRow))
        menu.addItem(.separator())

        // Pause.
        if cfg.isPaused(at: Date()), let until = cfg.pausedUntil {
            let f = DateFormatter(); f.timeStyle = .short
            let resume = NSMenuItem(title: "Resume Sailing (paused until \(f.string(from: until)))", action: #selector(resumeNow), keyEquivalent: "")
            resume.target = self
            menu.addItem(resume)
        } else {
            let pause = NSMenuItem(title: "Charge to 100% for 2 hours", action: #selector(pauseTwoHours), keyEquivalent: "")
            pause.target = self
            menu.addItem(pause)
        }
        menu.addItem(.separator())

        // Helper status + Setup.
        let helper = reconciler.controller.helper
        if helper.isInstalled {
            let v = helper.version()
            menu.addItem(disabled(v == nil ? "Helper installed, not responding" : "Helper installed (v\(v!))"))
        } else {
            menu.addItem(disabled("Helper not installed: limits below 80% unavailable"))
        }
        let setup = NSMenuItem(title: "Setup…", action: #selector(openSetup), keyEquivalent: "")
        setup.target = self
        menu.addItem(setup)
        let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        login.isEnabled = LoginItem.isInstalledInApplications || LoginItem.isEnabled
        if !login.isEnabled { login.toolTip = "Move \(SailIDs.appName).app to /Applications first" }
        menu.addItem(login)
        menu.addItem(.separator())

        let about = NSMenuItem(title: "About \(SailIDs.appName)", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "Quit (limit stays in powerd)", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        let quitFull = NSMenuItem(title: "Quit and charge to 100%", action: #selector(quitAndRelease), keyEquivalent: "")
        quitFull.target = self
        menu.addItem(quitFull)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func viewItem(_ view: NSView) -> NSMenuItem {
        let i = NSMenuItem()
        i.view = view
        return i
    }

    // MARK: Actions

    @objc private func toggleSailing() { reconciler.update { $0.sailingEnabled.toggle() } }
    @objc private func toggleHeat() { reconciler.update { $0.heatEnabled.toggle() } }

    private func commitUpper(_ v: Int) {
        reconciler.update { $0.upperLimit = v; if $0.lowerLimit >= v { $0.lowerLimit = v - 5 } }
        lowerRow?.set(reconciler.config.lowerLimit)
    }

    private func commitLower(_ v: Int) {
        reconciler.update { $0.lowerLimit = v }
        lowerRow?.set(reconciler.config.lowerLimit)
    }

    @objc private func showAbout() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String ?? "0"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(
            string: "Developer: \(SailIDs.developer)",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor,
                         .paragraphStyle: paragraph])
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: SailIDs.appName,
            .applicationVersion: version,
            .version: build,
            .credits: credits,
        ])
    }

    @objc private func pauseTwoHours() { reconciler.update { $0.pausedUntil = Date().addingTimeInterval(2 * 3600) } }
    @objc private func resumeNow() { reconciler.update { $0.pausedUntil = nil } }

    @objc private func openSetup() { app.showSetup() }

    @objc private func toggleLogin() {
        if LoginItem.isEnabled {
            LoginItem.disable()
        } else {
            do { try LoginItem.enable() } catch { app.alert("Could not enable launch at login", error.localizedDescription) }
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func quitAndRelease() {
        switch reconciler.controller.setLimit(100) {
        case .success: NSApp.terminate(nil)
        case .failure(let m): app.alert("Could not release the limit", m.description)
        }
    }
}
