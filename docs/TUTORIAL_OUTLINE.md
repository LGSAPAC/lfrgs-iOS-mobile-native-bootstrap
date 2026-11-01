# Tutorial Outline — Native iOS Self-Service App on Liferay 2026.Q1

> Status: chapters 01–02 verified on a running Liferay; 03–05 written, with LiferayKit unit-tested
> (`swift test`) and the app sources awaiting a first build on a Mac (`docs/tutorial/`). API details are checked against the 2026.Q1
> source and a running instance (see section 6), so the tutorial never documents an endpoint from memory.

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
- `liferay/docker-compose.yml`: image `liferay/dxp:2026.q1.14-lts` (latest 2026.Q1 LTS patch, overridable), with a volume for `deploy/`.
- The image ships a pre-built database, so first-start properties are ignored; `portal-ext.properties` points Liferay at a fresh Hypersonic file.
- DXP activation key: how to request a trial key and where to drop the `.xml` file (`liferay/deploy/`, git-ignored).
- `portal-ext.properties` for local dev (virtual host, disabling the setup wizard).
- Exploring `/o/api` (API Explorer) as the reader's "source of truth".

### 02 — Configure Liferay for a self-service user
- **Self-service user**: create `jane.doe@example.com` with only the default *User* role (by script via
  `headless-admin-user`, or via the UI).
- **OAuth 2 application** (Control Panel → Security → OAuth 2 Administration):
  - Client profile **Native Application** (PKCE, no client secret).
  - Redirect URI `com.liferay.sample.selfservice://oauth2redirect`.
  - Scopes: `Liferay.Headless.Admin.User`, `Liferay.Headless.Admin.Address` (read), and `c_servicerequest` (the object's REST app name is its lower-cased internal name).
  - Explain *Trusted Application* (skips the consent screen) versus showing consent.
  - Grant the *User* role **View + Create Token** on the application (otherwise regular users cannot authorize it).
  - Created in the UI: only the *Native Application* profile offers Authorization Code (PKCE) **and** Refresh Token. Custom, non-IANA URL schemes are accepted as callback URIs.
- **Custom object `Service Request`** (company scope), provisioned by `scripts/setup.sh` (idempotent `PUT …/by-external-reference-code/…` calls, so readers need only `curl` and `jq`):
  - Fields: `title` (text, required), `description` (long text), `category` (picklist),
    `requestStatus` (picklist: open / in-progress / closed), `priority` (integer 1–3), `dueDate` (date).
  - Relationship: none in v1. A relationship to *User* or *Account* is an optional advanced section.
  - Permissions: the script grants the *User* role `ADD_OBJECT_ENTRY` on resource `com.liferay.object#<id>` (additive `PATCH /roles/{id}`).
    Entry-level VIEW/UPDATE/DELETE come from ownership, so users see only their own requests without any client-side filtering.
- Verify everything with `curl` before touching Xcode: `scripts/smoke-test.sh` (CRUD + isolation, as Jane and John) and
  `scripts/oauth-pkce-test.sh` (PKCE, token exchange, refresh, revoke).

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
- **Sign out**: Liferay 2026.Q1 has no revocation endpoint, so delete the tokens from the Keychain, reset state, and use
  `prefersEphemeralWebBrowserSession` so the next sign-in doesn't silently reuse the web session.

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
- Edit given name, family name, and job title via `PATCH /user-accounts/{id}` (the avatar is optional).
- Explain why a self-service user can update their own account but cannot create or delete users. This is the
  permission model, and why the app must handle `403` gracefully.

### 07 — System object: My Addresses (full CRUD)
- List: `GET /user-accounts/{id}/postal-addresses`. Read, update, delete: `/postal-addresses/{id}`.
- **Create:** 2026.Q1 has no POST for user addresses. PATCH the user account with the full
  `userAccountContactInformation.postalAddresses` list (existing ids plus the new one); omitted addresses are deleted.
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
│   ├── configs/portal-ext.properties    # local-dev settings (fresh DB, no first-login screens)
│   ├── deploy/                          # DXP activation key goes here (git-ignored)
│   ├── setup/
│   │   ├── picklists.json               # Service Request Category / Status
│   │   └── service-request-object.json  # object definition
│   └── scripts/
│       ├── setup.sh                     # idempotent: picklists, object, permission, users
│       ├── smoke-test.sh                # CRUD + isolation checks as Jane and John
│       └── oauth-pkce-test.sh           # manual PKCE flow: token, refresh, revoke
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
| 3 | Repository name & visibility | Keep **`lfrgs-iOS-mobile-native-bootstrap`**; stays **private** until the owner decides it is ready |
| 4 | System object | **User profile** (read/update own account) + **Postal Addresses** (CRUD) |
| 5 | Custom object | **`Service Request`** |
| 6 | Minimum iOS / Xcode | iOS 17 with the current Xcode |

## 6. Verification checklist

Checked against the `2026.q1.0` source tag of `liferay/liferay-portal` and a running `liferay/dxp:2026.q1.14-lts`.

- [x] Docker image tag: `2026.q1.14-lts` (latest 2026.Q1 LTS patch on 2026-10-30). The image registers a development licence on start.
- [x] OAuth2 *Native Application* profile = Authorization Code PKCE + Refresh Token (+ JWT bearer, ROPC); custom URL schemes allowed.
- [x] Scope names: `Liferay.Headless.Admin.User`, `Liferay.Headless.Admin.Address`, `c_servicerequest`.
- [x] Object provisioning via `object-admin` and `headless-admin-list-type` upsert-by-ERC endpoints; object permission resource `com.liferay.object#<id>`.
- [x] User postal address endpoints (no POST, so create goes through PATCH user account).
- [x] Live run: `setup.sh` (twice, so it is safe to re-run) and `smoke-test.sh`: all 19 checks pass as Jane and John.
- [x] Live run: `oauth-pkce-test.sh` driven by a headless browser as Jane: PKCE, consent, token, API calls, refresh.

Findings from the live run, now reflected in chapters 01–02:

- The image's pre-built database forces an admin password change (API calls return 403), so the tutorial uses a fresh Hypersonic file.
- Users created by API must verify their email address unless `company.security.strangers.verify=false`.
- Regular users need **View + Create Token** on the OAuth 2 application, or they get "You do not have the required permissions".
- The consent button is **Authorize**. Access tokens last 600 s. Refresh tokens are not rotated by default.
- **There is no token revocation endpoint** (only `authorize`, `token`, `introspect`).

## 7. Before making the repository public

- [ ] Choose the Code of Conduct contact and replace the placeholder in `CODE_OF_CONDUCT.md`.
- [ ] Turn on **private vulnerability reporting** (Settings → Code security), which `SECURITY.md` relies on.
- [ ] Confirm the `Liferay` CI workflow is green on `main`.
- [ ] Re-check the README status table and that every chapter's checkpoint still passes.
- [ ] Decide whether a `NOTICE` file or copyright line is needed for Apache 2.0 under the publishing organisation.
- [ ] Get internal sign-off, then change visibility (Settings → Danger Zone).
