# Tutorial Outline — Native iOS Self-Service App on Liferay 2026.Q1

> Status: **DRAFT outline** — structure and scope for review before any code is written.
> Items marked **⚠ verify** must be checked against a running 2026.Q1 instance (`/o/api`)
> before the chapter is written, so the tutorial never documents an endpoint from memory.

## 1. Goal

Teach an iOS developer to build a **SwiftUI app that signs in a Liferay user** and lets that
user **manage their own data** through Liferay's headless REST APIs, with no Liferay SDK and no
third‑party dependencies.

By the end, the reader has:

1. A local Liferay DXP 2026.Q1 instance, configured reproducibly (no manual click-ops required).
2. A native app that signs in with **OAuth 2.0 Authorization Code + PKCE**.
3. **CRUD on an out-of-the-box system object** (the signed-in user and their postal addresses).
4. **CRUD on a custom Liferay Object** (`Service Request`), scoped to the signed-in user.
5. A tested, documented codebase they can fork as a starting point.

### Audience & prerequisites

- iOS developers who are comfortable with Swift and SwiftUI. No prior Liferay knowledge needed.
- Liferay developers who are new to iOS. Each chapter explains the iOS idioms it uses.
- Tools: macOS, a current Xcode, Docker Desktop, and roughly 8 GB of RAM free for Liferay.

### Non-goals (listed as "next steps" at the end)

Push notifications, offline sync, Android, Commerce, workflow approval UIs, and multi-tenant/virtual instances.

---

## 2. Architecture

```
┌──────────────────────── iOS app (SwiftUI) ────────────────────────┐
│  Features/                                                         │
│   ├─ Login           ──► AuthService (ASWebAuthenticationSession)  │
│   ├─ Profile         ──► UserAccountRepository     (system object) │
│   ├─ Addresses       ──► PostalAddressRepository   (system object) │
│   └─ ServiceRequests ──► ServiceRequestRepository  (custom object) │
│                                   │                                │
│  LiferayKit (local Swift package) ▼                                │
│   ├─ Auth:   PKCE, TokenStore (Keychain), refresh actor            │
│   ├─ HTTP:   APIClient (async/await, URLSession), error mapping    │
│   └─ Models: Page<T>, Picklist, Creator, ODataQuery builder        │
└───────────────────────────────────┬────────────────────────────────┘
                                    │ HTTPS + Bearer token
┌───────────────────────────────────▼────────────────────────────────┐
│ Liferay DXP 2026.Q1                                                │
│  /o/oauth2/authorize | /o/oauth2/token | /o/oauth2/revoke          │
│  /o/headless-admin-user/v1.0/...   (User, Postal Address)          │
│  /o/c/servicerequests/...          (custom object, auto-generated) │
└────────────────────────────────────────────────────────────────────┘
```

**Key design decisions** (each one gets a short "why" box in the tutorial):

| Decision | Choice | Why |
|---|---|---|
| UI | SwiftUI + the Observation framework (`@Observable`) | Modern, concise, and the default for new apps |
| Min iOS | iOS 17 | Needed for `@Observable`; covers the vast majority of devices |
| Concurrency | Swift 6 strict concurrency, `async/await`, `actor` for token refresh | Prevents parallel duplicate refreshes |
| Dependencies | **None** (URLSession, CryptoKit, Security, AuthenticationServices) | Easy to read, fork, and keep up to date |
| Auth | Authorization Code + PKCE (S256), public client, no secret | Correct flow for native apps (RFC 8252); never embed a client secret |
| Token storage | Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) | Not UserDefaults |
| Liferay setup | Client extensions + scripts, with a UI walkthrough as an alternative | Reproducible for readers and CI |
| Liferay API layer | Small hand-written client, not generated from OpenAPI | Teaches the API; generation is covered as an optional appendix |

---

## 3. Chapters

Each chapter maps to a git tag (`step-NN-…`). Readers can then `git checkout step-05-auth` to
start from a known state, and diff consecutive tags to see exactly what a chapter changed.

### 00 — Introduction
- What is being built (screenshots and a short GIF), the architecture diagram, and the decisions table.
- Why Liferay recommends Headless APIs over the retired Mobile SDK and Screens on 7.4+.

### 01 — Run Liferay 2026.Q1 locally
- `liferay/docker-compose.yml`: DXP 2026.Q1 image (**⚠ verify** exact tag, e.g. `2026.q1.N-lts`) with a volume for `deploy/`.
- DXP activation key: how to request a trial key and where to drop the `.xml` file (`liferay/deploy/`, git-ignored).
- `portal-ext.properties` for local dev (virtual host, disabling the setup wizard).
- Exploring `/o/api` (API Explorer) as the reader's "source of truth".

### 02 — Configure Liferay for a self-service user
- **Self-service user**: create `jane.doe@example.com` with only the default *User* role (by script via
  `headless-admin-user`, or via the UI).
- **OAuth 2 application** (Control Panel → Security → OAuth 2 Administration):
  - Client profile **Native Application** (PKCE, no client secret).
  - Redirect URI `com.liferay.sample.selfservice://oauth2redirect`.
  - Scopes: minimum needed for the user's own account, addresses, and the custom object (**⚠ verify** scope names).
  - Explain *Trusted Application* (skips the consent screen) versus showing consent.
  - Alternative: `oAuthApplicationUserAgent` client extension (**⚠ verify** whether it supports custom-scheme redirect URIs).
- **Custom object `Service Request`** (company scope), provisioned by a **batch client extension**:
  - Fields: `title` (text, required), `description` (long text), `category` (picklist),
    `requestStatus` (picklist: open / in-progress / closed), `priority` (integer 1–3), `dueDate` (date).
  - Relationship: none in v1. A relationship to *User* or *Account* is an optional advanced section.
  - Permissions: grant the *User* role **Add Object Entry**. Entry-level VIEW/UPDATE/DELETE come from
    the **Owner** role, so users see only their own requests without any client-side filtering.
- Verify everything with `curl` before touching Xcode. Chapter checkpoint: the reader gets a token in
  the browser and lists `/o/c/servicerequests`.

### 03 — Create the iOS project
- Xcode project plus a local Swift package `LiferayKit`. Explain why the split helps (testability, reuse).
- `Config/Local.xcconfig` (git-ignored) holding `LIFERAY_BASE_URL`, `OAUTH_CLIENT_ID`, and `OAUTH_REDIRECT_URI`, read via `Info.plist`.
- ATS: `NSAllowsLocalNetworking` for `http://localhost` in **Debug only**, plus why production must use HTTPS.

### 04 — Sign in with OAuth 2 + PKCE
- Generate `code_verifier`/`code_challenge` with CryptoKit, plus a `state` value for CSRF protection.
- Run `ASWebAuthenticationSession` and handle the callback, including the `prefersEphemeralWebBrowserSession` trade-off (SSO cookie versus a clean logout).
- Exchange the code at `/o/oauth2/token` and decode `access_token`, `refresh_token`, and `expires_in`.
- Persist tokens in a Keychain-backed `TokenStore`.
- App states: `signedOut → signingIn → signedIn(UserAccount)`; restore the session on launch.
- **Sign out**: revoke at `/o/oauth2/revoke`, clear the Keychain, and reset state.

### 05 — A small, correct API client
- An `APIClient` with a generic `send<T: Decodable>(_ endpoint:)`.
- Automatic refresh in an `actor TokenRefresher`: a single in-flight refresh, a retry once on 401, and a forced sign-out if refresh fails.
- Liferay conventions encoded once:
  - `Page<T>` (`items`, `page`, `pageSize`, `totalCount`, `lastPage`)
  - Query builder for `page`, `pageSize`, `sort`, `search`, `filter` (OData), `fields`, and `restrictFields`
  - Error body → `LiferayError` (status, title, type) mapped to user-facing messages
  - `Accept-Language` / `Content-Language` headers for localized picklists and messages
  - Date decoding (ISO-8601 with and without fractional seconds)

### 06 — System object: My Profile (Read / Update)
- `GET /o/headless-admin-user/v1.0/my-user-account`
- Edit given name, family name, job title, and (optionally) the avatar, via **⚠ verify** `PATCH /user-accounts/{id}`.
- Explain why a self-service user can update their own account but cannot create or delete users. This is the
  permission model, and why the app must handle `403` gracefully.

### 07 — System object: My Addresses (full CRUD)
- List, create, update, and delete the user's postal addresses (**⚠ verify** the exact 2026.Q1 paths under
  `headless-admin-user`; fall back to *Account* addresses if user-level create is not exposed).
- Country and region pickers from `headless-admin-address` (`/countries`, `/countries/{id}/regions`).
- Pattern: a form view model with validation, optimistic UI, and rollback on error.

### 08 — Custom object: Service Requests (full CRUD)
- List view: infinite scroll (pagination), pull-to-refresh, `.searchable` → `search=`, and a filter chip → OData
  `filter=requestStatus eq 'open'`, sorted by `dateCreated:desc`.
- Detail, create, and edit forms. Picklist encoding: send `{"key": "open"}` and read `{key, name}` back.
- Delete with swipe-to-delete and a confirmation dialog.
- `externalReferenceCode`: why to use it and how it makes create calls idempotent from a mobile client
  (`PUT /by-external-reference-code/{erc}`).
- Show that a second user cannot see Jane's requests, enforced by the server rather than the app.

### 09 — Testing
- Unit tests with Swift Testing: PKCE, query building, JSON decoding from recorded fixtures, and the refresh logic.
- `URLProtocol` stub for API client tests, with no network access.
- Optional UI test smoke run against a local Liferay instance.
- CI: GitHub Actions on `macos-latest` (build plus unit tests); a Liferay-backed job is optional.

### 10 — Production hardening checklist
- HTTPS only, and Universal Links (associated domains) versus a custom URL scheme for the redirect.
- Token lifetimes, configuring refresh-token rotation in Liferay, and the Keychain access group if extensions are added.
- Certificate pinning: when it is worth it and when it is not.
- Logging without leaking tokens or PII; privacy manifest (`PrivacyInfo.xcprivacy`).
- Accessibility (Dynamic Type, VoiceOver labels) and localization (`Accept-Language`).
- Rate limits, timeouts, and retry with backoff.

### 11 — Next steps
- Generating Swift models from the OpenAPI spec, attachments on objects, workflow on object entries,
  object actions that trigger push notifications, offline caching with SwiftData, and an Android companion.

---

## 4. Repository layout (proposed)

```
.
├── README.md                     # What, why, quick start (5 commands), links to chapters
├── LICENSE                       # Apache License 2.0
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── SECURITY.md
├── docs/
│   ├── TUTORIAL_OUTLINE.md       # this file
│   ├── tutorial/
│   │   ├── 00-introduction.md
│   │   ├── 01-run-liferay.md
│   │   ├── …
│   │   └── 11-next-steps.md
│   └── images/
├── liferay/
│   ├── docker-compose.yml
│   ├── configs/local/portal-ext.properties
│   ├── client-extensions/
│   │   ├── service-request-object/      # batch CX: picklists + object definition
│   │   └── ios-oauth-app/               # OAuth2 app as CX (if supported for native redirect)
│   └── scripts/
│       ├── seed-users.sh                # creates jane.doe + john.roe via headless-admin-user
│       └── smoke-test.sh                # curl checks used in chapter 02 and CI
├── ios/
│   ├── LiferaySelfService.xcodeproj
│   ├── LiferaySelfService/
│   │   ├── App/                         # @main, AppState, root navigation
│   │   ├── Features/
│   │   │   ├── Login/
│   │   │   ├── Profile/
│   │   │   ├── Addresses/
│   │   │   └── ServiceRequests/
│   │   ├── Shared/                      # reusable views, formatters
│   │   └── Resources/                   # Assets, Localizable.xcstrings, PrivacyInfo.xcprivacy
│   ├── LiferayKit/                      # local Swift package
│   │   ├── Package.swift
│   │   ├── Sources/LiferayKit/{Auth,HTTP,Models,Repositories}/
│   │   └── Tests/LiferayKitTests/{Fixtures,…}
│   └── Config/
│       ├── Base.xcconfig
│       └── Local.xcconfig.example       # copied to Local.xcconfig (git-ignored)
└── .github/
    ├── workflows/ios-ci.yml
    ├── ISSUE_TEMPLATE/
    └── pull_request_template.md
```

---

## 5. Decisions

| # | Topic | Decision |
|---|---|---|
| 1 | Liferay edition | **Liferay DXP 2026.Q1** only. Chapter 01 explains how to get a trial activation key. |
| 2 | Licence | **Apache License 2.0** (`LICENSE`) |
| 3 | Public name | **`liferay-ios-native-bootstrap`** (drops the internal `lfrgs-` prefix) |
| 4 | System object | **User profile** (read/update own account) + **Postal Addresses** (CRUD) |
| 5 | Custom object | **`Service Request`** |
| 6 | Minimum iOS / Xcode | iOS 17 with the current Xcode |

## 6. Verification checklist (before writing chapters 02, 06, 07, 08)

- [ ] Exact Docker image tag for 2026.Q1, and the licence/activation steps.
- [ ] OAuth2 *Native Application* profile: PKCE enforcement, refresh-token behaviour, revoke endpoint.
- [ ] Scope names for `headless-admin-user`, `headless-admin-address`, and the custom object's REST app.
- [ ] Whether `oAuthApplicationUserAgent` client extensions accept custom-scheme redirect URIs.
- [ ] Batch client extension format for object definitions and picklists in 2026.Q1.
- [ ] User postal address CRUD paths, and what a default *User* role may do on them.
- [ ] `PATCH` on own `user-accounts/{id}` with only the default *User* role.
- [ ] Default object entry permissions (Owner) giving per-user isolation, tested with two users.
