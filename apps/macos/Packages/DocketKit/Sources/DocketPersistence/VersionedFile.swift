import DocketCore
import Foundation
import os

/// One JSON file with a top-level `version` (`docs/04-data.md` §1): atomic writes, `0600` in a `0700`
/// directory, an unreadable file set aside, and a file from a newer Docket left untouched.
struct VersionedFile<Value: Codable & Sendable>: Sendable {
    let url: URL
    let currentVersion: Int
    let now: @Sendable () -> Date

    private static var log: Logger { Logger(subsystem: "com.eliasjnior.docket", category: "persistence") }

    enum Loaded {
        case missing
        case value(Value)
        /// Unreadable; it was moved aside.
        case corrupt
        case newer(Int)
    }

    func load() -> Loaded {
        guard let data = try? Data(contentsOf: url) else { return .missing }
        if let header = try? JSONDecoder().decode(Header.self, from: data), header.version > currentVersion {
            return .newer(header.version)
        }
        do {
            return .value(try Self.decoder.decode(Value.self, from: data))
        } catch {
            setAside()
            return .corrupt
        }
    }

    func save(_ value: Value) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try manager.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        do {
            try Self.encoder.encode(value).write(to: url, options: [.atomic])
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw PersistenceError.unwritable(file: url.lastPathComponent)
        }
    }

    /// `state.json` becomes `state.corrupt-<timestamp>.json` (`docs/02-activity-detection.md` §9).
    private func setAside() {
        let stamp = Self.stampFormatter.string(from: now())
        let name = url.deletingPathExtension().lastPathComponent
        let target = url.deletingLastPathComponent().appending(path: "\(name).corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: target)
        Self.log.error("Set aside an unreadable \(url.lastPathComponent, privacy: .public)")
    }

    private struct Header: Decodable {
        var version: Int
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static var stampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }
}
