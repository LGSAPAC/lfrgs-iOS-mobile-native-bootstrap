import Foundation
import Testing
@testable import LiferayKit

@Suite("PKCE")
struct PKCETests {
    @Test("Matches the RFC 7636 Appendix B example")
    func rfc7636Example() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(PKCE.method == "S256")
    }

    @Test("Generated verifiers are 43 base64url characters and unique")
    func generatedVerifier() {
        let a = PKCE.generate(), b = PKCE.generate()
        #expect(a.verifier.count == 43)
        #expect(a.verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(a.verifier != b.verifier)
        #expect(a.challenge == PKCE(verifier: a.verifier).challenge)
    }
}
