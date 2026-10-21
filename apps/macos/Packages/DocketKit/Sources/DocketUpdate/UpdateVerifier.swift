import CryptoKit
import Foundation

public struct UpdateVerifier: Sendable {
    private let publicKey: Curve25519.Signing.PublicKey

    public init(publicKeyBase64: String) throws {
        guard let raw = Data(base64Encoded: publicKeyBase64) else { throw UpdateError.badSignature }
        publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }

    public func verifyArchive(at url: URL, manifest: ReleaseManifest) throws {
        let data = try Data(contentsOf: url)
        guard data.count == manifest.size else { throw UpdateError.sizeMismatch }
        guard let signature = Data(base64Encoded: manifest.signature),
            publicKey.isValidSignature(signature, for: data)
        else {
            throw UpdateError.badSignature
        }
    }

    public static func checkSystem(_ manifest: ReleaseManifest, running: OperatingSystemVersion) throws {
        let parts = manifest.minimumSystemVersion.split(separator: ".").compactMap { Int($0) }
        let required = OperatingSystemVersion(
            majorVersion: parts.first ?? 0,
            minorVersion: parts.dropFirst().first ?? 0,
            patchVersion: parts.dropFirst(2).first ?? 0
        )
        let runningTuple = (running.majorVersion, running.minorVersion, running.patchVersion)
        let requiredTuple = (required.majorVersion, required.minorVersion, required.patchVersion)
        guard runningTuple >= requiredTuple else { throw UpdateError.unsupportedSystem(manifest.minimumSystemVersion) }
    }
}
