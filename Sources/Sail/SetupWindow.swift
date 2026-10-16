import AppKit
import SwiftUI
import SailCore

/// First-run checklist: compatibility, helper, conflicting settings, autostart, self-test.
/// Also reachable from the menu ("Setup…"). Everything on it is re-checkable.
@MainActor
final class SetupModel: ObservableObject {
    enum SelfTest: Equatable {
        case idle, running
        case passed(String)
        case failed(String)
    }

    @Published var report: Compatibility.Report
    @Published var helperInstalled = false
    @Published var helperVersion: Int?
    @Published var loginEnabled = LoginItem.isEnabled
    @Published var selfTest: SelfTest = .idle
    @Published var message: String?

    let reconciler: Reconciler
    var onFinish: (() -> Void)?

    init(reconciler: Reconciler) {
        self.reconciler = reconciler
        report = Compatibility.check(monitor: reconciler.monitor, controller: reconciler.controller)
        refresh()
    }

    func refresh() {
        report = Compatibility.check(monitor: reconciler.monitor, controller: reconciler.controller)
        let helper = reconciler.controller.helper
        helperInstalled = helper.isInstalled
        helperVersion = helperInstalled ? helper.version() : nil
        loginEnabled = LoginItem.isEnabled
    }

    var helperUpToDate: Bool { helperVersion == SailIDs.helperVersion }

    func installHelper() {
        message = nil
        do {
            try HelperInstaller.install()
            refresh()
            reconciler.tick()
        } catch {
            message = String(describing: error)
        }
    }

    func setLogin(_ on: Bool) {
        message = nil
        if on {
            do { try LoginItem.enable() } catch { message = error.localizedDescription }
        } else {
            LoginItem.disable()
        }
        loginEnabled = LoginItem.isEnabled
    }

    /// Writes the current desired limit and waits for powerd to report it back.
    func runSelfTest() {
        selfTest = .running
        reconciler.tick()
        guard let desired = reconciler.snapshot.decision?.desiredLimit else {
            selfTest = .failed(reconciler.snapshot.lastError ?? "battery not readable")
            return
        }
        Task { @MainActor in
            for _ in 0..<12 {
                try? await Task.sleep(for: .seconds(1))
                if let a = reconciler.controller.readActual(), a.enabled, a.limit == desired {
                    selfTest = .passed("powerd enforces \(desired)% (\(reconciler.snapshot.decision?.reason ?? ""))")
                    return
                }
            }
            let actual = reconciler.controller.readActual().map { "\($0.limit)%" } ?? "nothing"
            let why = reconciler.snapshot.lastError.map { " — \($0)" } ?? ""
            selfTest = .failed("expected \(desired)%, powerd reports \(actual)\(why)")
        }
    }

    func finish() {
        UserDefaults.standard.set(true, forKey: "setupCompleted")
        onFinish?()
    }

    static var isCompleted: Bool { UserDefaults.standard.bool(forKey: "setupCompleted") }
}

struct SetupView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            compatibilityCard
            helperCard
            settingsCard
            loginCard
            selfTestCard
            if let m = model.message {
                Text(m).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(24)
        .frame(width: 520)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("Set up \(SailIDs.appName)").font(.title2.weight(.semibold))
                Text("Sailing mode and heat protection for your battery.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private var compatibilityCard: some View {
        let r = model.report
        return Card {
            Row(ok: r.appleSilicon, title: "Apple Silicon", detail: r.appleSilicon ? "Yes" : "Intel Macs are not supported")
            Row(ok: r.osSupported, title: "macOS \(r.osVersionString)",
                detail: r.osSupported ? "Supported" : "Requires macOS 26.4 or newer")
            Row(ok: r.chargeLimitSupported, title: "Charge limit control",
                detail: r.chargeLimitSupported ? "Available (powerd manual charge limit)" : "Not available on this Mac")
            Row(ok: r.batteryPresent, title: "Battery", detail: r.batteryPresent ? "Detected" : "No battery found")
        }
    }

    private var helperCard: some View {
        Card {
            Row(ok: model.helperInstalled && model.helperUpToDate,
                title: "Privileged helper",
                detail: model.helperInstalled
                    ? (model.helperUpToDate ? "Installed (v\(model.helperVersion ?? 0))" : "Installed, needs update")
                    : "Required for limits below 80%. Asks for your administrator password once.") {
                if !(model.helperInstalled && model.helperUpToDate) {
                    Button(model.helperInstalled ? "Update…" : "Install…") { model.installHelper() }
                }
            }
        }
    }

    private var settingsCard: some View {
        let r = model.report
        return Card {
            Row(ok: r.optimizedChargingOn == false, title: "Optimized Battery Charging",
                detail: r.optimizedChargingOn == true ? "Turn it off in System Settings, it fights the limit" : "Off") {
                if r.optimizedChargingOn != false {
                    Button("Open Battery Settings") { Compatibility.openBatterySettings() }
                }
            }
            Row(ok: r.competingLimiters.isEmpty, title: "Other charge limiters",
                detail: r.competingLimiters.isEmpty ? "None running" : "Quit \(r.competingLimiters.joined(separator: ", ")) — two limiters fight each other")
        }
    }

    private var loginCard: some View {
        Card {
            Row(ok: model.loginEnabled ? true : (LoginItem.requiresApproval ? false : nil), title: "Launch at login",
                detail: LoginItem.requiresApproval
                    ? "Allow \(SailIDs.appName) under System Settings → Login Items"
                    : (LoginItem.isInstalledInApplications || model.loginEnabled
                        ? "Kept alive by launchd, restarted after a crash"
                        : "Move \(SailIDs.appName).app to /Applications to enable")) {
                if LoginItem.requiresApproval {
                    Button("Open Login Items") { LoginItem.openSystemSettings() }
                } else {
                    Toggle("", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                        .toggleStyle(.switch).labelsHidden()
                        .disabled(!(LoginItem.isInstalledInApplications || model.loginEnabled))
                }
            }
        }
    }

    private var selfTestCard: some View {
        Card {
            Row(ok: {
                    switch model.selfTest {
                    case .passed: return true
                    case .failed: return false
                    default: return nil
                    }
                }(),
                title: "Self-test",
                detail: {
                    switch model.selfTest {
                    case .idle: return "Writes the limit and checks that macOS enforces it"
                    case .running: return "Checking…"
                    case .passed(let s), .failed(let s): return s
                    }
                }()) {
                Button("Run") { model.runSelfTest() }.disabled(model.selfTest == .running)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Re-check") { model.refresh() }
            Spacer()
            Button("Done") { model.finish() }.keyboardShortcut(.defaultAction)
        }
        .padding(.top, 4)
    }
}

/// A translucent card. Uses Liquid Glass where the system offers it.
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}

private struct Row<Trailing: View>: View {
    var ok: Bool?
    var title: String
    var detail: String
    @ViewBuilder var trailing: Trailing

    init(ok: Bool?, title: String, detail: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.ok = ok
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: ok == true ? "checkmark.circle.fill" : (ok == false ? "exclamationmark.circle.fill" : "circle"))
                .foregroundStyle(ok == true ? .green : (ok == false ? .orange : .secondary))
                .font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

/// Owns the single Setup window.
@MainActor
final class SetupWindowController {
    private var window: NSWindow?
    private var model: SetupModel?
    private let reconciler: Reconciler

    init(reconciler: Reconciler) { self.reconciler = reconciler }

    func show() {
        if window == nil {
            let model = SetupModel(reconciler: reconciler)
            model.onFinish = { [weak self] in self?.window?.close() }
            let hosting = NSHostingController(rootView: SetupView(model: model))
            let w = NSWindow(contentViewController: hosting)
            w.title = "Set up \(SailIDs.appName)"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.isMovableByWindowBackground = true
            w.center()
            self.window = w
            self.model = model
        } else {
            model?.refresh()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
