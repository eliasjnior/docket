// Prints a new Ed25519 key pair for signing updates.
// Line 1: private key (base64) for the UPDATE_SIGNING_KEY secret. Line 2: public key (base64) for the app.
import CryptoKit
import Foundation

let key = Curve25519.Signing.PrivateKey()
print(key.rawRepresentation.base64EncodedString())
print(key.publicKey.rawRepresentation.base64EncodedString())
