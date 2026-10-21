import DocketCore
import Foundation
import Observation
import os

/// `config.json` for the interface: every change is written at once; there is no Apply (`docs/05-design.md` §9).
@MainActor
@Observable
public final class ConfigStore {
    public private(set) var config: Config
    /// A newer Docket wrote `config.json`; settings are read-only until it is updated.
    public private(set) var isReadOnly = false
    /// Called after each saved change, so the poller can apply it.
    @ObservationIgnored public var onChange: (@MainActor (Config) -> Void)?

    @ObservationIgnored private let storage: ConfigStoring
    @ObservationIgnored private let log = Logger(subsystem: "com.eliasjnior.docket", category: "persistence")

    public init(storage: ConfigStoring, initial: Config = Config()) {
        self.storage = storage
        config = initial
    }

    public func load() async {
        do {
            config = try await storage.loadConfig()
        } catch {
            isReadOnly = true
        }
    }

    /// Import (FR-96): the whole file is replaced, as one change.
    public func replace(with imported: Config) {
        update { $0 = imported }
    }

    public func update(_ mutate: (inout Config) -> Void) {
        guard !isReadOnly else { return }
        var next = config
        mutate(&next)
        guard next != config else { return }
        config = next
        let storage = storage
        Task {
            do {
                try await storage.saveConfig(next)
            } catch {
                self.log.error("Could not save config: \(String(describing: error), privacy: .public)")
            }
        }
        onChange?(next)
    }
}
