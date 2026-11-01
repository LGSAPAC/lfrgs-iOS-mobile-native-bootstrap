import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

/// Proof Key for Code Exchange (RFC 7636).
///
/// The app creates a random `verifier`, sends only its SHA-256 hash (`challenge`) when the user signs
/// in, and reveals the `verifier` when it exchanges the authorization code for tokens. A stolen code
/// is useless without the verifier, which never left the device. This is why the app needs no client
/// secret.
public struct PKCE: Sendable, Equatable {
    /// The secret: 43 characters of base64url-encoded random bytes.
    public let verifier: String
    /// `BASE64URL(SHA256(verifier))`, sent with the authorize request.
    public let challenge: String
    /// The only method Liferay should be asked to use.
    public static let method = "S256"

    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = Data(Self.sha256(Data(verifier.utf8))).base64URLEncodedString()
    }

    /// Creates a new verifier from 32 cryptographically secure random bytes.
    public static func generate() -> PKCE {
        PKCE(verifier: Data.random(count: 32).base64URLEncodedString())
    }

    static func sha256(_ data: Data) -> [UInt8] {
        #if canImport(CryptoKit)
        Array(SHA256.hash(data: data))
        #else
        PortableSHA256.hash(data)
        #endif
    }
}

extension Data {
    /// Base64url without padding (RFC 4648 §5), as OAuth 2 and PKCE require.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Random bytes from the system's cryptographically secure generator.
    static func random(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}
