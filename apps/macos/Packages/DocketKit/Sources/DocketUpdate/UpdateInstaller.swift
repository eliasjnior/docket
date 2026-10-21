import Foundation
import Security

/// Unpacks a verified archive, checks the bundle, and swaps it in place after the app quits.
public struct UpdateInstaller: Sendable {
    private let bundleIdentifier: String

    public init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    /// Returns the unpacked app, after checking its identifier, version and code signature.
    public func prepare(archive: URL, manifest: ReleaseManifest, runningApp: URL) throws -> URL {
        let directory = archive.deletingLastPathComponent().appending(path: "unpacked-\(UUID().uuidString)")
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path])
        guard
            let app = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" })
        else {
            throw UpdateError.invalidBundle("No app in archive")
        }
        try validateBundle(at: app, manifest: manifest)
        try CodeRequirement.check(candidate: app, matches: runningApp)
        return app
    }

    func validateBundle(at app: URL, manifest: ReleaseManifest) throws {
        guard let bundle = Bundle(url: app), let info = bundle.infoDictionary else {
            throw UpdateError.invalidBundle("Unreadable bundle")
        }
        guard info["CFBundleIdentifier"] as? String == bundleIdentifier else {
            throw UpdateError.invalidBundle("Unexpected bundle identifier")
        }
        guard (info["CFBundleShortVersionString"] as? String).flatMap(SemanticVersion.init) == manifest.version else {
            throw UpdateError.invalidBundle("Version does not match the release")
        }
    }

    /// Starts a detached helper that waits for `pid` to exit, replaces `target` with `source` and relaunches it.
    /// The previous app is restored if the copy fails.
    public func launchReplacement(source: URL, target: URL, pid: Int32) throws {
        let script = """
            while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
            backup="$3.previous"
            rm -rf "$backup"
            if mv "$3" "$backup" && /usr/bin/ditto "$2" "$3"; then
              /usr/bin/xattr -cr "$3"
              rm -rf "$backup"
            else
              rm -rf "$3"
              mv "$backup" "$3"
            fi
            /usr/bin/open "$3"
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "docket-update", String(pid), source.path, target.path]
        do {
            try process.run()
        } catch {
            throw UpdateError.installFailed(error.localizedDescription)
        }
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.invalidBundle("\(tool) exited with \(process.terminationStatus)")
        }
    }
}

enum CodeRequirement {
    /// The new app must satisfy the running app's designated requirement, i.e. be signed by the same identity.
    /// Ad-hoc development builds have no stable requirement, so the check is skipped for them.
    static func check(candidate: URL, matches running: URL) throws {
        guard let requirement = designatedRequirement(of: running), !isAdHoc(running) else { return }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(candidate as CFURL, [], &code) == errSecSuccess, let code else {
            throw UpdateError.requirementMismatch
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
            throw UpdateError.requirementMismatch
        }
    }

    static func designatedRequirement(of app: URL) -> SecRequirement? {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
            SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess
        else {
            return nil
        }
        return requirement
    }

    static func isAdHoc(_ app: URL) -> Bool {
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
            SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
            let dictionary = info as? [String: Any]
        else {
            return true
        }
        return dictionary[kSecCodeInfoCertificates as String] == nil
    }
}
