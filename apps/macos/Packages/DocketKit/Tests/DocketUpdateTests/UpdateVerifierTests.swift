import CryptoKit
import DocketCore
import Foundation
import Testing

@testable import DocketUpdate

struct UpdateVerifierTests {
    private let key = Curve25519.Signing.PrivateKey()
    private let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    private func archive(_ contents: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "Docket.zip")
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func manifest(signing contents: String, size: Int? = nil) throws -> ReleaseManifest {
        let signature = try key.signature(for: Data(contents.utf8)).base64EncodedString()
        let json = """
            {"version":"1.0.0","build":"1","asset":"Docket.zip","signature":"\(signature)",\
            "size":\(size ?? contents.utf8.count),"minimumSystemVersion":"15.0"}
            """
        return try JSONDecoder().decode(ReleaseManifest.self, from: Data(json.utf8))
    }

    private var verifier: UpdateVerifier {
        get throws { try UpdateVerifier(publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString()) }
    }

    @Test func acceptsValidSignature() throws {
        try verifier.verifyArchive(at: archive("payload"), manifest: manifest(signing: "payload"))
    }

    @Test func rejectsTamperedArchive() throws {
        let url = try archive("pAyload")
        #expect(throws: UpdateError.badSignature) {
            try verifier.verifyArchive(at: url, manifest: manifest(signing: "payload"))
        }
    }

    @Test func rejectsSignatureFromAnotherKey() throws {
        let other = try UpdateVerifier(
            publicKeyBase64: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        )
        let url = try archive("payload")
        #expect(throws: UpdateError.badSignature) {
            try other.verifyArchive(at: url, manifest: manifest(signing: "payload"))
        }
    }

    @Test func rejectsSizeMismatch() throws {
        let url = try archive("payload")
        #expect(throws: UpdateError.sizeMismatch) {
            try verifier.verifyArchive(at: url, manifest: manifest(signing: "payload", size: 99))
        }
    }

    @Test func checksMinimumSystem() throws {
        let manifest = try manifest(signing: "x")
        try UpdateVerifier.checkSystem(
            manifest, running: OperatingSystemVersion(majorVersion: 15, minorVersion: 1, patchVersion: 0))
        #expect(throws: UpdateError.unsupportedSystem("15.0")) {
            try UpdateVerifier.checkSystem(
                manifest, running: OperatingSystemVersion(majorVersion: 14, minorVersion: 7, patchVersion: 0))
        }
    }

    @Test func validatesBundleIdentityAndVersion() throws {
        let app = directory.appending(path: "Docket.app/Contents")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "com.example.app", "CFBundleShortVersionString": "1.0.0"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appending(path: "Info.plist"))
        let manifest = try manifest(signing: "x")

        try UpdateInstaller(bundleIdentifier: "com.example.app")
            .validateBundle(at: directory.appending(path: "Docket.app"), manifest: manifest)
        #expect(throws: UpdateError.self) {
            try UpdateInstaller(bundleIdentifier: "com.example.other")
                .validateBundle(at: directory.appending(path: "Docket.app"), manifest: manifest)
        }
    }
}
