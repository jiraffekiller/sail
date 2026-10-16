// SailHelper — privileged launchd daemon.
//
// One job: write the manual charge limit into PowerUIAgent's preferences (root's
// com.apple.smartcharging.topoffprotection domain) and post the Darwin notification
// that makes PowerUIAgent re-read them. powerd then enforces the limit itself, so this
// process is only needed for the few seconds a limit changes.
import Foundation
import SailCore
import os

let log = Logger(subsystem: SailIDs.logSubsystem, category: "helper")

final class HelperService: NSObject, SailHelperProtocol {
    private let domain = PowerUIDefaults.domain as CFString

    func setChargeLimit(_ percent: Int, withReply reply: @escaping (Bool, String) -> Void) {
        guard (1...100).contains(percent) else {
            reply(false, "limit \(percent) out of range 1...100")
            return
        }
        CFPreferencesSetValue(PowerUIDefaults.limitKey as CFString, NSNumber(value: percent),
                              domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSetValue(PowerUIDefaults.featureStateKey as CFString, NSNumber(value: 1),
                              domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            log.error("CFPreferencesSynchronize failed for \(PowerUIDefaults.domain, privacy: .public)")
            reply(false, "could not write preferences")
            return
        }
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(PowerUIDefaults.changedNotification as CFString),
                                             nil, nil, true)
        log.notice("charge limit set to \(percent, privacy: .public)")
        reply(true, "")
    }

    func getChargeLimit(withReply reply: @escaping (Int, Bool) -> Void) {
        let limit = CFPreferencesCopyValue(PowerUIDefaults.limitKey as CFString, domain,
                                           kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? NSNumber
        let state = CFPreferencesCopyValue(PowerUIDefaults.featureStateKey as CFString, domain,
                                           kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? NSNumber
        reply(limit?.intValue ?? 0, (state?.intValue ?? 0) != 0)
    }

    func getVersion(withReply reply: @escaping (Int) -> Void) {
        reply(SailIDs.helperVersion)
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Only the Sail app may talk to us. With an ad-hoc signature this pins the bundle
        // identifier; with a Developer ID certificate tighten it with `anchor apple generic`
        // and your team identifier.
        connection.setCodeSigningRequirement("identifier \"\(SailIDs.appBundleID)\"")
        connection.exportedInterface = NSXPCInterface(with: SailHelperProtocol.self)
        connection.exportedObject = HelperService()
        connection.resume()
        return true
    }
}

guard getuid() == 0 else {
    FileHandle.standardError.write("SailHelper must run as root (launchd daemon)\n".data(using: .utf8)!)
    exit(1)
}
log.notice("SailHelper v\(SailIDs.helperVersion, privacy: .public) starting")
let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: SailIDs.helperLabel)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
