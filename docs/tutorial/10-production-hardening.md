# 10 — Production hardening

> **Unofficial reference.** This tutorial is an unofficial reference, not official Liferay
> documentation, and is not supported by Liferay. See [learn.liferay.com](https://learn.liferay.com)
> for official documentation.

The tutorial setup is deliberately relaxed so it is quick to follow. This chapter is the checklist for
moving the app and Liferay to a real environment. Items marked **(app)** change the iOS project;
**(Liferay)** items are server configuration.

**Time:** about 30 minutes to read; the work depends on your environment.

## 1. HTTPS everywhere (app + Liferay)

- Serve Liferay over **HTTPS only**, with a certificate from a public CA. App Transport Security then
  needs no exceptions.
- **(app)** Set `LIFERAY_BASE_URL` in your release configuration to the `https://` address.
- **(app)** `Info.plist` contains `NSAllowsLocalNetworking`. It permits plain HTTP **only** to local
  addresses (such as `localhost`), never to internet hosts, so it doesn't weaken connections to a real
  server. Remove it anyway once you no longer develop against a local Liferay, so a reviewer doesn't
  have to reason about it.

### Certificate pinning?

Usually not worth it: it breaks the app whenever the certificate is renewed unexpectedly. If your
security policy requires it, use App Transport Security's `NSPinnedDomains` in `Info.plist` (no code),
pin the CA's or intermediate's public key rather than the leaf certificate, and include a backup pin.

## 2. The OAuth 2 application (Liferay)

- **Remove the dev callback URI** `http://localhost:9999/callback` (chapter 02). Keep only the app's
  redirect URI.
- Keep the profile **Native Application** and client authentication **None**. A secret in a mobile
  app is not secret.
- Keep the allowed grants to **PKCE Extended Authorization Code** and **Refresh Token**.
- Grant only the **scopes** the app uses (chapter 02, step 3b). For a read-only app, use the `.read`
  scopes.
- **Trusted Application**: turn it on for a first-party company app (no consent screen); leave it off
  if users should see what they grant.
- Review which **roles** have *View* + *Create Token* on the application (chapter 02, step 3c). Only
  users with those permissions can sign in to the app.

### Custom URL scheme or Universal Link?

Any app can register the custom scheme `com.liferay.sample.selfservice://`. PKCE makes an intercepted
authorization code useless, but on iOS 17.4 and later you can go further and redirect to an **HTTPS
Universal Link** that only your app can claim:

1. Host an `apple-app-site-association` file on your domain and add the *Associated Domains*
   capability (`applinks:auth.example.com`).
2. Register `https://auth.example.com/oauth2/callback` as the OAuth 2 application's callback URI.
3. In `LoginView`, use `ASWebAuthenticationSession`'s HTTPS callback (`.https(host:path:)`) instead of
   `callbackURLScheme`.

## 3. Token lifetimes (Liferay)

The defaults, read from the 2026.Q1 source and confirmed by the token responses:

| Setting (*System Settings → OAuth 2*, configuration `DefaultBearerTokenProviderConfiguration`) | Key | Default |
|---|---|---|
| Access token duration | `access.token.expires.in` | **600** s (10 minutes) |
| Refresh token duration | `refresh.token.expires.in` | **604800** s (7 days) |

With these defaults, **a user who doesn't open the app for a week must sign in again**, because the
refresh token has expired. The app handles that: the refresh fails with `invalid_grant`, `AuthSession`
signs out, and the sign-in screen appears. Choose the refresh duration as a trade-off between
convenience and how long a lost phone stays useful.

Liferay 2026.Q1 has **no token revocation endpoint**. To cut off a lost device, an administrator revokes
the user's authorization in **OAuth 2 Administration → *the application* → Authorizations**.

## 4. Tokens and data on the device (app)

- Tokens are in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: not in backups
  restored to another device, not synced to iCloud.
- For higher assurance, add a `SecAccessControl` with `.userPresence` to `KeychainTokenStore`. Face ID
  or the passcode is then needed to read the tokens; expect a prompt when the app starts.
- **Never log tokens.** The app doesn't log requests. If you add logging, use `os.Logger` and mark
  values `privacy: .private`.
- The app caches nothing on disk; every screen reloads from Liferay. If you add an offline cache
  (chapter 11), protect it with Data Protection (`.completeUntilFirstUserAuthentication` or stronger).

## 5. Networking (app)

- `URLSession.shared` waits up to 60 s for a response. For a snappier failure on bad networks, give
  `APIClient` its own `URLSession` with `timeoutIntervalForRequest = 30`.
- Creating a Service Request is already **safe to retry** (PUT by external reference code, chapter 08).
  Keep that pattern for anything else the user creates.

## 6. Liferay server configuration

Undo the local-development shortcuts from `liferay/configs/portal-ext.properties` (see also
[SECURITY.md](../../SECURITY.md)):

| Tutorial setting | In production |
|---|---|
| Embedded Hypersonic database | A supported database (for example PostgreSQL or MySQL) |
| `setup.wizard.enabled=false`, admin `test@liferay.com` / `test` | A strong, unique admin password; no default accounts |
| `passwords.default.policy.change.required=false` | Liferay's default (`true`), or your password policy |
| `company.security.strangers.verify=false` | `true`: users verify their email address |
| `terms.of.use.required=false` | As your legal team requires |
| Basic auth used by the setup scripts | Turn off Basic auth for headless APIs if nothing else needs it |

Users must still have the **User** role's `ADD_OBJECT_ENTRY` on Service Requests, and *View* + *Create
Token* on the OAuth 2 application.

## 7. App Store submission (app)

- **Privacy manifest:** [`PrivacyInfo.xcprivacy`](../../ios/LiferaySelfService/PrivacyInfo.xcprivacy)
  declares no tracking and no required-reason APIs, and lists the data the app sends to Liferay for app
  functionality: name, physical address, and the service requests themselves. **Review it for your
  deployment** and match your App Store privacy answers.
- **Encryption export compliance:** the app only uses HTTPS and the Keychain. If that's still true for
  your build, add `ITSAppUsesNonExemptEncryption` = `NO` to `Info.plist` to skip the question on each
  upload.
- **Demo mode** (`--demo`) is only active when that launch argument is passed. Remove `DemoBackend` from
  release builds if your review process prefers it.
- Set your **Team** under *Signing & Capabilities*, and replace `com.liferay.sample.selfservice` with
  your own bundle identifier **and** URL scheme (both in `project.yml`/`Local.xcconfig` and the OAuth 2
  application's callback URI).

## Checklist

- [ ] Liferay on HTTPS; `LIFERAY_BASE_URL` uses `https://`
- [ ] Dev callback URI removed from the OAuth 2 application
- [ ] Scopes, roles and *Trusted Application* reviewed
- [ ] Token lifetimes chosen deliberately
- [ ] `portal-ext.properties` shortcuts reverted; real database
- [ ] Privacy manifest reviewed; export compliance key set
- [ ] Own bundle identifier, URL scheme and signing team
- [ ] Tested on a real device against the production-like server

Next: [11 — Next steps](11-next-steps.md).
