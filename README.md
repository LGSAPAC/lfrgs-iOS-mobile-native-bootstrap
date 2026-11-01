# Liferay iOS Native Bootstrap

[![Liferay](https://github.com/LGSAPAC/lfrgs-iOS-mobile-native-bootstrap/actions/workflows/liferay.yml/badge.svg)](https://github.com/LGSAPAC/lfrgs-iOS-mobile-native-bootstrap/actions/workflows/liferay.yml)

A step-by-step tutorial and reference app for building a **native iOS (SwiftUI) app on
Liferay DXP 2026.Q1**, using only Liferay's headless REST APIs:

- Sign in a Liferay self-service user with **OAuth 2.0 Authorization Code + PKCE**.
- **CRUD on out-of-the-box system objects**: the user's own profile and postal addresses.
- **CRUD on a custom Liferay Object**: `Service Request`, with each user seeing only their own.
- **No third-party dependencies**: `URLSession`, `CryptoKit`, `AuthenticationServices` and the Keychain.

Liferay Screens and the Mobile SDK were retired in 7.4. Liferay's guidance is to build native apps on
the headless APIs, but there was no end-to-end example. This is one.

## Status

| Chapter | | Status |
|---|---|---|
| 00 | Introduction | Planned |
| [01](docs/tutorial/01-run-liferay.md) | Run Liferay DXP 2026.Q1 locally | ✅ Verified on 2026.q1.14-lts |
| [02](docs/tutorial/02-configure-liferay.md) | Configure Liferay for a self-service user | ✅ Verified on 2026.q1.14-lts |
| [03](docs/tutorial/03-create-ios-project.md) | Create the iOS project | ✅ Built by CI with Xcode 26.6; launches to the sign-in screen |
| [04](docs/tutorial/04-sign-in-oauth-pkce.md) | Sign in with OAuth 2 + PKCE | 🧪 OAuth/PKCE code unit-tested; sign-in against Liferay not yet run in the app |
| [05](docs/tutorial/05-api-client.md) | A small, correct API client | 🧪 Unit-tested against recorded Liferay responses |
| [06](docs/tutorial/06-my-profile.md) | My Profile (system object: User) | 🧪 API checked live in CI; screen built and screenshotted in demo mode |
| [07](docs/tutorial/07-my-addresses.md) | My Addresses (system object: Postal Address) | 🧪 API checked live in CI; screen built and screenshotted in demo mode |
| [08](docs/tutorial/08-service-requests.md) | Service Requests (custom object) | 🧪 API checked live in CI; screen built and screenshotted in demo mode |
| 09–11 | Testing, production hardening, next steps | Planned |

The full plan, architecture and decisions are in [`docs/TUTORIAL_OUTLINE.md`](docs/TUTORIAL_OUTLINE.md).

## Quick start (Liferay side)

Requirements: Docker (6 GB+ memory), `curl` and `jq`.

```bash
cd liferay
docker compose up -d        # Liferay DXP 2026.Q1 on http://localhost:8080 (admin: test@liferay.com / test)
./scripts/setup.sh          # Service Request object, permissions, users jane.doe and john.roe
./scripts/smoke-test.sh     # verifies every API call the app uses
```

Then create the OAuth 2 application as described in [chapter 02, step 3](docs/tutorial/02-configure-liferay.md#3-create-the-oauth-2-application).

## Things that will surprise you (all covered in the chapters)

- Regular users **can't authorize an OAuth 2 app** until their role has *View* and *Create Token* on it.
- There is **no POST for a user's postal address**: you PATCH the user account with the full list.
- An **unknown picklist key returns `403 Forbidden`**, not a validation error.
- **PATCH ignores `null`**, so clearing a field needs PUT; an empty Integer field comes back as `0`.
- Address endpoints only agree on the **English country name**; an empty country is saved as *Afghanistan*.
- Liferay 2026.Q1 has **no OAuth token revocation endpoint**, so sign-out is done on the device.
- The Docker image's pre-built database forces an admin password change, so the tutorial uses a fresh one.

## Repository layout

```
docs/                    Tutorial chapters and the outline
liferay/                 Local Liferay: Docker Compose, setup data, scripts
  scripts/setup.sh         Idempotent Liferay configuration
  scripts/smoke-test.sh    API checks as the self-service users
  scripts/oauth-pkce-test.sh   Manual OAuth 2 + PKCE walkthrough
  scripts/record-fixtures.sh   Records real API responses for the Swift tests
ios/
  LiferayKit/              Swift package: OAuth 2 + PKCE, token session, API client, models, tests
  LiferaySelfService/      SwiftUI app sources
  LiferaySelfService.xcodeproj   Generated from project.yml with XcodeGen (committed)
  Config/                  Shared.xcconfig + Local.xcconfig.example (your Client ID)
.github/                 CI, issue and pull request templates
```

## Contributing

Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Everything in this tutorial is
verified against a running Liferay. CI starts DXP 2026.Q1 and checks the API on every pull request.

Please read the [Code of Conduct](CODE_OF_CONDUCT.md), and report security issues privately as
described in [SECURITY.md](SECURITY.md).

## License

Licensed under the [Apache License, Version 2.0](LICENSE).
