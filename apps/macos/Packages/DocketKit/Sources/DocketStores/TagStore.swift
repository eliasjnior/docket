import DocketCore
import Foundation

/// Local tags over `config.json` (FR-80–FR-85). Tags never leave the Mac.
@MainActor
public struct TagStore {
    private let configStore: ConfigStore
    private let now: () -> Date

    public init(configStore: ConfigStore, now: @escaping () -> Date = { Date() }) {
        self.configStore = configStore
        self.now = now
    }

    public func tags(of pullRequestID: String) -> [String] {
        configStore.config.tags[pullRequestID]?.tags ?? []
    }

    /// Adds `input` after normalization, or returns why it was rejected.
    @discardableResult
    public func add(_ input: String, to pullRequestID: String, ref: String) -> Result<String, Tags.Rejection> {
        let existing = tags(of: pullRequestID)
        let result = Tags.validate(input, existing: existing)
        if case .success(let tag) = result {
            set(existing + [tag], on: pullRequestID, ref: ref)
        }
        return result
    }

    public func remove(_ tag: String, from pullRequestID: String, ref: String) {
        set(tags(of: pullRequestID).filter { $0 != tag }, on: pullRequestID, ref: ref)
    }

    /// An entry with no tags is deleted, not stored empty (`docs/04-data.md` §2.1).
    private func set(_ tags: [String], on pullRequestID: String, ref: String) {
        let at = now()
        configStore.update { config in
            config.tags[pullRequestID] = tags.isEmpty ? nil : Config.TagEntry(ref: ref, tags: tags, updatedAt: at)
        }
    }

    public var inUse: [String] {
        Tags.inUse(configStore.config.tags.values.map(\.tags))
    }
}

/// Repositories and organizations to watch (FR-70–FR-74).
@MainActor
public struct SelectionStore {
    public enum Entry: Hashable, Sendable {
        case repository(String)
        case owner(String)

        /// `owner/name` is a repository; a bare login is an organization or user.
        public init?(typed text: String) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = value.split(separator: "/", omittingEmptySubsequences: false)
            let valid = parts.allSatisfy {
                !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || "-_.".contains($0) }
            }
            guard valid else { return nil }
            switch parts.count {
            case 1: self = .owner(value)
            case 2: self = .repository(value)
            default: return nil
            }
        }

        public var name: String {
            switch self {
            case .repository(let name), .owner(let name): name
            }
        }
    }

    private let configStore: ConfigStore

    public init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    public var mode: Selection.Mode { configStore.config.selection.mode }

    public func setMode(_ mode: Selection.Mode) {
        configStore.update { $0.selection.mode = mode }
    }

    /// The list the current mode reads.
    public var entries: [Entry] {
        let selection = configStore.config.selection
        switch selection.mode {
        case .all:
            return selection.excludedOwners.map(Entry.owner) + selection.excludedRepositories.map(Entry.repository)
        case .only:
            return selection.includedOwners.map(Entry.owner) + selection.includedRepositories.map(Entry.repository)
        }
    }

    public func add(_ entry: Entry) {
        configStore.update { config in
            func append(_ value: String, to list: inout [String]) {
                if !list.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) { list.append(value) }
            }
            switch (config.selection.mode, entry) {
            case (.all, .repository(let name)): append(name, to: &config.selection.excludedRepositories)
            case (.all, .owner(let name)): append(name, to: &config.selection.excludedOwners)
            case (.only, .repository(let name)): append(name, to: &config.selection.includedRepositories)
            case (.only, .owner(let name)): append(name, to: &config.selection.includedOwners)
            }
        }
    }

    public func remove(_ entry: Entry) {
        configStore.update { config in
            let name = entry.name
            func drop(_ list: inout [String]) { list.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame } }
            switch (config.selection.mode, entry) {
            case (.all, .repository): drop(&config.selection.excludedRepositories)
            case (.all, .owner): drop(&config.selection.excludedOwners)
            case (.only, .repository): drop(&config.selection.includedRepositories)
            case (.only, .owner): drop(&config.selection.includedOwners)
            }
        }
    }
}
