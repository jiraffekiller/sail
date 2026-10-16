import Foundation
import SailCore

enum HelperError: Error, CustomStringConvertible {
    case notInstalled
    case unreachable
    case rejected(String)

    var description: String {
        switch self {
        case .notInstalled: return "helper not installed"
        case .unreachable: return "helper not responding"
        case .rejected(let m): return "helper refused: \(m)"
        }
    }
}

/// Synchronous façade over the XPC connection to SailHelper. Calls block the caller for
/// at most `timeout` seconds; replies arrive on a background queue so this is safe on main.
final class HelperClient {
    private var connection: NSXPCConnection?
    private let timeout: TimeInterval = 4

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: SailIDs.helperPlistPath)
            && FileManager.default.fileExists(atPath: SailIDs.helperBinaryPath)
    }

    func version() -> Int? {
        guard isInstalled else { return nil }
        return call { proxy, done in proxy.getVersion(withReply: done) }
    }

    func setChargeLimit(_ percent: Int) -> Result<Void, HelperError> {
        guard isInstalled else { return .failure(.notInstalled) }
        guard let (ok, message): (Bool, String) = call({ proxy, done in
            proxy.setChargeLimit(percent) { ok, msg in done((ok, msg)) }
        }) else { return .failure(.unreachable) }
        return ok ? .success(()) : .failure(.rejected(message))
    }

    func storedLimit() -> (limit: Int, enabled: Bool)? {
        guard isInstalled else { return nil }
        return call { proxy, done in proxy.getChargeLimit { l, e in done((l, e)) } }
    }

    private func connect() -> NSXPCConnection {
        if let c = connection { return c }
        let c = NSXPCConnection(machServiceName: SailIDs.helperLabel, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: SailHelperProtocol.self)
        c.invalidationHandler = { [weak self] in self?.connection = nil }
        c.interruptionHandler = { [weak self] in self?.connection = nil }
        c.resume()
        connection = c
        return c
    }

    private func call<T>(_ body: (SailHelperProtocol, @escaping (T) -> Void) -> Void) -> T? {
        let box = ResultBox<T>()
        let sem = DispatchSemaphore(value: 0)
        guard let proxy = connect().remoteObjectProxyWithErrorHandler({ error in
            Log.control.error("helper XPC error: \(String(describing: error), privacy: .public)")
            sem.signal()
        }) as? SailHelperProtocol else { return nil }
        body(proxy) { value in
            box.value = value
            sem.signal()
        }
        if sem.wait(timeout: .now() + timeout) == .timedOut {
            Log.control.error("helper XPC call timed out")
            connection?.invalidate()
            connection = nil
        }
        return box.value
    }
}

private final class ResultBox<T> {
    var value: T?
}
