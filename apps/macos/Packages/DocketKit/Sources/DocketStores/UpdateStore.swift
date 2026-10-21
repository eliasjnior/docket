import DocketCore
import DocketUpdate
import Foundation
import Observation

/// Self-update from GitHub Releases, as in Lookout (FR-93, D-14): checks every 6 hours.
@MainActor
@Observable
public final class UpdateStore {
    public enum Phase: Equatable, Sendable {
        case idle
        case checking
        case upToDate
        case available(AvailableUpdate)
        case installing(AvailableUpdate)
        case failed(String)
    }

    /// Where `skippedVersion` and `lastUpdateCheckAt` live: `state.json`, through the poller.
    public struct Bookkeeping: Sendable {
        public var load: @Sendable () async -> (lastChecked: Date?, skipped: String?)
        public var save: @Sendable (_ lastChecked: Date?, _ skipped: String?) async -> Void

        public init(
            load: @escaping @Sendable () async -> (lastChecked: Date?, skipped: String?),
            save: @escaping @Sendable (_ lastChecked: Date?, _ skipped: String?) async -> Void
        ) {
            self.load = load
            self.save = save
        }
    }

    public private(set) var phase: Phase = .idle
    public private(set) var lastChecked: Date?

    public var availableUpdate: AvailableUpdate? {
        switch phase {
        case .available(let update), .installing(let update): update
        default: nil
        }
    }

    @ObservationIgnored private let current: SemanticVersion
    @ObservationIgnored private let source: any ReleaseSource
    @ObservationIgnored private let verifier: UpdateVerifier?
    @ObservationIgnored private let installer: UpdateInstaller
    @ObservationIgnored private let runningApp: URL
    @ObservationIgnored private let configStore: ConfigStore
    @ObservationIgnored private let bookkeeping: Bookkeeping
    @ObservationIgnored private let workDirectory: URL
    @ObservationIgnored private var skipped: String?
    @ObservationIgnored private var scheduleTask: Task<Void, Never>?
    @ObservationIgnored public var relaunch: @MainActor () -> Void = {}
    @ObservationIgnored public var beforeInstall: @MainActor () async -> Void = {}

    public static let interval: TimeInterval = 6 * 3600

    public init(
        current: SemanticVersion, source: any ReleaseSource, verifier: UpdateVerifier?, installer: UpdateInstaller,
        runningApp: URL, configStore: ConfigStore, bookkeeping: Bookkeeping,
        workDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "DocketUpdate")
    ) {
        self.current = current
        self.source = source
        self.verifier = verifier
        self.installer = installer
        self.runningApp = runningApp
        self.configStore = configStore
        self.bookkeeping = bookkeeping
        self.workDirectory = workDirectory
    }

    public func startAutomaticChecks() {
        scheduleTask?.cancel()
        scheduleTask = Task { [weak self] in
            if let saved = await self?.bookkeeping.load() {
                self?.lastChecked = saved.lastChecked
                self?.skipped = saved.skipped
            }
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                guard let self else { return }
                if configStore.config.updates.automaticChecks,
                    Date.now.timeIntervalSince(lastChecked ?? .distantPast) >= Self.interval
                {
                    await check(userInitiated: false)
                    if configStore.config.updates.automaticInstall, let update = availableUpdate {
                        await install(update)
                    }
                }
                try? await Task.sleep(for: .seconds(15 * 60))
            }
        }
    }

    public func check(userInitiated: Bool) async {
        guard phase != .checking else { return }
        phase = .checking
        do {
            let update = try await source.latest(after: current)
            lastChecked = .now
            await bookkeeping.save(lastChecked, skipped)
            if let update, userInitiated || update.version.description != skipped {
                phase = .available(update)
            } else {
                phase = .upToDate
            }
        } catch UpdateError.unauthorized {
            phase = .failed(
                String(localized: "GitHub refused the request. Check that gh is signed in.", comment: "Update error"))
        } catch {
            phase = .failed(
                String(localized: "Could not check for updates. \(error.localizedDescription)", comment: "Update error")
            )
        }
    }

    public func skip(_ update: AvailableUpdate) {
        skipped = update.version.description
        phase = .upToDate
        let lastChecked = lastChecked
        let skipped = skipped
        Task { await bookkeeping.save(lastChecked, skipped) }
    }

    public func dismiss() {
        if case .available = phase { phase = .idle }
    }

    public func install(_ update: AvailableUpdate) async {
        guard let verifier else {
            phase = .failed(
                String(
                    localized: "This build has no update key, so updates cannot be verified.", comment: "Update error"))
            return
        }
        phase = .installing(update)
        do {
            try UpdateVerifier.checkSystem(update.manifest, running: ProcessInfo.processInfo.operatingSystemVersion)
            let directory = workDirectory.appending(path: update.version.description)
            try? FileManager.default.removeItem(at: directory)
            let archive = try await source.downloadArchive(of: update, to: directory)
            try verifier.verifyArchive(at: archive, manifest: update.manifest)
            let app = try installer.prepare(archive: archive, manifest: update.manifest, runningApp: runningApp)
            await beforeInstall()
            try installer.launchReplacement(
                source: app, target: runningApp, pid: ProcessInfo.processInfo.processIdentifier)
            relaunch()
        } catch {
            phase = .failed(
                String(localized: "The update could not be installed: \(Self.describe(error))", comment: "Update error")
            )
        }
    }

    static func describe(_ error: any Error) -> String {
        switch error as? UpdateError {
        case .badSignature: String(localized: "the download's signature is invalid.", comment: "Update error reason")
        case .sizeMismatch: String(localized: "the download is incomplete.", comment: "Update error reason")
        case .requirementMismatch:
            String(localized: "the new app is not signed by Docket.", comment: "Update error reason")
        case .unsupportedSystem(let minimum):
            String(localized: "it needs macOS \(minimum) or later.", comment: "Update error reason")
        case .invalidBundle(let reason): reason
        case .missingAsset(let name): String(localized: "the release has no \(name).", comment: "Update error reason")
        case .installFailed(let reason): reason
        case .unauthorized: String(localized: "GitHub refused the download.", comment: "Update error reason")
        case nil: error.localizedDescription
        }
    }
}
