// Fixture only: Apple's CryptoKit generates an ephemeral seed, never touches Keychain.
import Foundation
import CryptoKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let key = Curve25519.Signing.PrivateKey()
try key.rawRepresentation.base64EncodedString().write(to: directory.appendingPathComponent("fixture-private-key"), atomically: true, encoding: .utf8)
try key.publicKey.rawRepresentation.base64EncodedString().write(to: directory.appendingPathComponent("fixture-public-key"), atomically: true, encoding: .utf8)
