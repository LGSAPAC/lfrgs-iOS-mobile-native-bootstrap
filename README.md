# Liferay iOS Native Bootstrap

A step-by-step tutorial and reference app for building a **native iOS (SwiftUI) app on Liferay DXP 2026.Q1**:

- Sign in a Liferay self-service user with **OAuth 2.0 + PKCE**.
- **CRUD on an out-of-the-box system object**: the user's own profile and postal addresses.
- **CRUD on a custom Liferay Object**: `Service Request`.
- Zero third-party dependencies: only `URLSession`, `CryptoKit`, `AuthenticationServices`, and the Keychain.

> **Status:** planning. See [`docs/TUTORIAL_OUTLINE.md`](docs/TUTORIAL_OUTLINE.md) for the chapter plan,
> architecture, repository layout and decisions.

## Requirements

- macOS with a current Xcode (iOS 17+ deployment target)
- Docker Desktop
- A **Liferay DXP 2026.Q1** activation key (a trial key works)

## License

Licensed under the [Apache License, Version 2.0](LICENSE).
