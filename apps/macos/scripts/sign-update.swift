// Usage: UPDATE_SIGNING_KEY=<base64> swift sign-update.swift <file>
// Prints the base64 Ed25519 signature of the file.
import CryptoKit
import Foundation

guard CommandLine.arguments.count == 2,
    let encoded = ProcessInfo.processInfo.environment["UPDATE_SIGNING_KEY"],
    let raw = Data(base64Encoded: encoded)
else {
    FileHandle.standardError.write(Data("usage: UPDATE_SIGNING_KEY=<base64> sign-update.swift <file>\n".utf8))
    exit(64)
}

let key = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
print(try key.signature(for: data).base64EncodedString())
