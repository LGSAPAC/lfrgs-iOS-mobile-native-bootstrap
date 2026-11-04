# 04 — Sign in with OAuth 2 + PKCE

> **Unofficial reference.** This tutorial is an unofficial reference, not official Liferay
> documentation, and is not supported by Liferay. See [learn.liferay.com](https://learn.liferay.com)
> for official documentation.

In this chapter the app signs a user in with Liferay's own sign-in page and gets tokens, without ever
seeing the user's password. It is the same flow you ran by hand with `oauth-pkce-test.sh` in
chapter 02, now in Swift.

**Time:** about 30 minutes, mostly reading. The code is already in the repository; this chapter
explains it.

> **Status:** `OAuthClient`, `PKCE` and `AuthSession` are unit-tested against recorded Liferay
> responses. The sign-in sheet (`LoginView`) has not yet been run on a device or simulator.

```
 App                                    Liferay
  │ 1. new PKCE verifier + state          │
  │ 2. open /o/oauth2/authorize ─────────►│  user signs in, taps Authorize
  │◄──────── 3. redirect com.liferay.sample.selfservice://oauth2redirect?code=…&state=…
  │ 4. check state                        │
  │ 5. POST /o/oauth2/token  code + verifier ►│
  │◄──────── 6. access_token (10 min) + refresh_token
  │ 7. save tokens in the Keychain        │
  │ 8. GET my-user-account (Bearer token) ►│
```

## 1. PKCE: no client secret needed

A native app can't keep a secret, because anyone can unpack the app binary. PKCE (RFC 7636) replaces
the secret with a one-time proof:

- Before signing in, the app creates a random **verifier** and sends only its SHA-256 hash, the
  **challenge**.
- When redeeming the code, it sends the verifier. Liferay hashes it and compares.

A stolen authorization code is useless without the verifier, which never left the device.

[`PKCE.swift`](../../ios/LiferayKit/Sources/LiferayKit/Auth/PKCE.swift):

```swift
public static func generate() -> PKCE {
    PKCE(verifier: Data.random(count: 32).base64URLEncodedString())   // 43 characters
}

public init(verifier: String) {
    self.verifier = verifier
    self.challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
}
```

(Simplified: the real file calls CryptoKit through a small helper, with a plain-Swift fallback that is
compiled only on Linux so CI can run the tests.) `Data.random(count:)` uses
`SystemRandomNumberGenerator`, which is cryptographically secure. The unit
test `PKCETests` checks the result against the worked example in RFC 7636, Appendix B.

## 2. Build the authorize URL

[`OAuthClient.makeAuthorizationRequest()`](../../ios/LiferayKit/Sources/LiferayKit/Auth/OAuthClient.swift)
returns the URL plus the PKCE values and a random **`state`**:

```
http://localhost:8080/o/oauth2/authorize
  ?response_type=code
  &client_id=id-xxxxxxxx-…
  &redirect_uri=com.liferay.sample.selfservice://oauth2redirect
  &code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM
  &code_challenge_method=S256
  &state=Zr1Q…
```

`state` protects against cross-site request forgery: the app accepts a callback only if it carries
back the same `state` it sent. No `scope` parameter is needed, because Liferay grants the scopes
configured on the application (chapter 02, step 3b).

## 3. Open the sign-in page

[`LoginView.swift`](../../ios/LiferaySelfService/Features/Login/LoginView.swift) uses SwiftUI's
`webAuthenticationSession`, a wrapper around `ASWebAuthenticationSession`:

```swift
@Environment(\.webAuthenticationSession) private var webAuthenticationSession

private func authenticate(url: URL, callbackURLScheme: String) async throws -> URL {
    try await webAuthenticationSession.authenticate(
        using: url,
        callbackURLScheme: callbackURLScheme,     // "com.liferay.sample.selfservice"
        preferredBrowserSession: .ephemeral
    )
}
```

- It shows a secure browser sheet. The app can't read what the user types into it.
- When Liferay redirects to `com.liferay.sample.selfservice://…`, the sheet closes and returns that
  URL. No *URL Types* entry is needed.
- **`.ephemeral`** doesn't share cookies with Safari. The user signs in every time, but **Sign out**
  really signs them out. That matters because Liferay 2026.Q1 has no token revocation endpoint (see
  section 6). With `.shared`, users who are already signed in to Liferay in Safari skip the password
  prompt, but the next sign-in after **Sign out** goes straight back in.

The user sees Liferay's **Authorize iOS Self-Service Tutorial** screen (unless the application is
*Trusted*) and taps **Authorize**. If instead they see "You do not have the required permissions", the
User role is missing **View** + **Create Token** on the application (chapter 02, step 3c).

## 4. Check the callback and exchange the code

```swift
let request = oauth.makeAuthorizationRequest()
let callbackURL = try await authenticate(request.url, oauth.configuration.callbackURLScheme)
let code = try oauth.authorizationCode(from: callbackURL, for: request)   // checks state first
let tokens = try await oauth.exchange(code: code, for: request)          // sends the verifier
try await session.signIn(with: tokens)                                    // Keychain
```

(from [`AppModel.signIn(using:)`](../../ios/LiferaySelfService/App/AppModel.swift))

`authorizationCode(from:for:)` throws `stateMismatch` if `state` differs, and
`authorizationFailed("access_denied")` if the user tapped **Cancel** on the consent screen.

`exchange` sends a form-encoded `POST /o/oauth2/token`:

```
grant_type=authorization_code&client_id=…&code=…&redirect_uri=…&code_verifier=…
```

The response, which `OAuthClientTests` decodes from the real recorded file:

```json
{
  "access_token": "…",
  "token_type": "Bearer",
  "expires_in": 600,
  "scope": "c_servicerequest.everything Liferay.Headless.Admin.User.everything Liferay.Headless.Admin.Address.everything.read",
  "refresh_token": "…"
}
```

`expires_in` is relative, so `OAuthTokens` stores an absolute `expiresAt` (issue time + 600 s).

## 5. Store tokens in the Keychain

[`KeychainTokenStore`](../../ios/LiferayKit/Sources/LiferayKit/Auth/TokenStore.swift) saves the tokens
as one Keychain item with **`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`**:

- readable after the first unlock since boot, so a refresh in the background still works;
- `ThisDeviceOnly`: never synced to iCloud or restored to another device.

Never put tokens in `UserDefaults`, which is a plain file inside the app's container.

On the next launch, [`AuthSession`](../../ios/LiferayKit/Sources/LiferayKit/Auth/AuthSession.swift)
loads them from the Keychain, and `AppModel.start()` goes straight to the signed-in screen.

## 6. Sign out

```swift
func signOut() async {
    await session?.signOut()     // deletes the tokens from the Keychain
    state = .signedOut
}
```

Liferay 2026.Q1 has **no token revocation endpoint** (it serves only `authorize`, `token` and
`introspect`), so the app can't tell Liferay to invalidate the tokens. Signing out therefore means:

- deleting the tokens on the device, so nothing in the app can use them;
- using an `.ephemeral` browser session, so no Liferay web session lingers either.

Access tokens expire after 10 minutes anyway. To cut off a lost device, an admin can revoke the
user's authorization in **OAuth 2 Administration → iOS Self-Service Tutorial → Authorizations**.

## Checkpoint

1. Run the app (⌘R) and tap **Sign in**.
2. Sign in as `jane.doe@example.com` / `Tutorial-2026!` and tap **Authorize**.
3. The app shows **Hi, Jane** with her name and email.
4. Stop and re-run the app: it opens signed in, with no browser sheet (tokens restored from the Keychain).
5. Tap **Sign out**, then **Sign in**: Liferay asks for the password again (`.ephemeral`).

Next: [05 — A small, correct API client](05-api-client.md).
