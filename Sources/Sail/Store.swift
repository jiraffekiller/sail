import Foundation
import SailCore

/// JSON persistence for the config and the policy state.
final class Store {
    let directory: URL
    private var configURL: URL { directory.appendingPathComponent("config.json") }
    private var stateURL: URL { directory.appendingPathComponent("state.json") }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = base.appendingPathComponent(SailIDs.appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func loadConfig() -> PolicyConfig {
        guard let data = try? Data(contentsOf: configURL),
              let cfg = try? decoder.decode(PolicyConfig.self, from: data) else { return .default }
        return cfg.normalized
    }

    func save(config: PolicyConfig) {
        write(config, to: configURL)
    }

    func loadState() -> PolicyState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? decoder.decode(PolicyState.self, from: data)
    }

    func save(state: PolicyState) {
        write(state, to: stateURL)
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func write<T: Encodable>(_ value: T, to url: URL) {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(value) else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            Log.app.error("could not write \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
