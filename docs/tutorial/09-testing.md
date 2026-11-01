# 09 — Testing

This tutorial is tested at four levels. Each level catches a different kind of mistake, and all four
run in CI on every push.

| Level | What | Where it runs | Catches |
|---|---|---|---|
| 1. Liferay API | `liferay/scripts/smoke-test.sh` | Linux, against a real DXP 2026.Q1 in Docker | Liferay behaving differently from what the app expects (permissions, quirks, a new patch release) |
| 2. Recorded responses | `record-fixtures.sh` + shape check | Linux, same Liferay | A response gaining or losing fields |
| 3. LiferayKit unit tests | `ios/LiferayKit/Tests` (30 tests) | Linux and macOS | Bugs in OAuth, PKCE, token refresh, the API client and the models |
| 4. App tests | `ios/LiferaySelfServiceTests` | iOS Simulator on a GitHub-hosted Mac | Bugs in what each screen does with the data |

Plus a **build and screenshot** of every tab in the iOS Simulator, which catches compile errors and
broken layouts.

**Time:** about 20 minutes.

## 1. Test against the real Liferay, not your memory of it

The most valuable tests here aren't Swift at all. `smoke-test.sh` signs in as **Jane and John**, with no
admin rights, and calls every endpoint the app uses. It also checks the surprising behaviours the app is
built around, so a future Liferay patch that changes one of them fails CI instead of the app:

```
PASS PUT postal address with English country name + region code (HTTP 200)
PASS PUT postal address with a country code is rejected (known quirk) (HTTP 400)
PASS PUT postal address without a region is rejected when the country has regions (HTTP 400)
PASS PUT cleared priority (returned as 0) and due date
PASS John does not see Jane's request in the list
PASS John cannot read Jane's request (HTTP 404)
```

Run it locally after `setup.sh` (chapter 02):

```bash
cd liferay && ./scripts/smoke-test.sh
```

## 2. Recorded responses as test data

Hand-written JSON in tests drifts from reality. `record-fixtures.sh` saves Liferay's real responses into
`ios/LiferayKit/Tests/LiferayKitTests/Fixtures/`, and the Swift tests decode those files:

```swift
let request = try decoder.decode(ServiceRequest.self, from: fixture("service-request"))
#expect(request.category == PicklistValue(key: "technical", name: "Technical"))
```

CI re-records the fixtures from a fresh Liferay on every run and compares their *structure* (key paths,
not values). Two fields are expected to differ and are ignored: `lastLoginDate` and `loginDate` exist
only after a browser sign-in.

## 3. LiferayKit: fast unit tests with a fake transport

Everything that talks HTTP takes an `HTTPTransport` (chapter 05), so tests replace the network with
`MockTransport`, which replies with fixtures and records what was sent. The tests that matter most:

- **PKCE** matches the worked example in RFC 7636, Appendix B.
- **Ten concurrent calls with an expired token cause exactly one refresh.**
- **A 401 refreshes once and retries; a second 401 signs the user out.**
- Every recorded Liferay error maps to the right `APIError`.
- Drafts encode exactly what Liferay accepts: picklist `{"key"}`, `2026-12-24`, explicit `null`s for PUT,
  the English country name.

```bash
cd ios/LiferayKit && swift test
```

The package has no UI and no Apple-only dependencies in its tested paths, so CI also runs these tests on
Linux in a `swift:6.1` container. PKCE uses CryptoKit on Apple platforms and a small portable SHA-256
elsewhere; the RFC test proves both give the same answer.

## 4. App tests: the screen models, against the demo backend

The views are thin; the logic lives in `@Observable` models (`ServiceRequestListModel`,
`AddressListModel`, `AppModel`). [`ScreenModelTests`](../../ios/LiferaySelfServiceTests/ScreenModelTests.swift)
drives them against [`DemoBackend`](../../ios/LiferaySelfService/App/DemoBackend.swift), an in-memory
stand-in for the Liferay endpoints that keeps state, so create → list → delete really round-trips:

```swift
@Test("The list loads, filters by status and searches")
func listFilterAndSearch() async {
    let model = ServiceRequestListModel(api: makeAPI())
    await model.reload()
    #expect(model.items.count == 4)

    model.statusFilter = "open"
    await model.reload()
    #expect(model.items.map(\.requestStatus.key) == ["open", "open"])
}
```

Run them in Xcode with **⌘U**, or:

```bash
cd ios
xcodebuild test -project LiferaySelfService.xcodeproj -scheme LiferaySelfService \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

(Use any simulator from `xcrun simctl list devices available`.)

## 5. Demo mode

Launching the app with `--demo` makes it use `DemoBackend` and start signed in as Jane. It is useful
beyond tests:

- **SwiftUI previews and screenshots** without a server. CI launches `--demo --tab requests`,
  `--tab addresses` and `--tab profile` to produce the screenshots in chapters 06–08.
- **UI work** without Docker running.

In Xcode: **Product → Scheme → Edit Scheme… → Run → Arguments**, add `--demo`.

It's off unless the argument is passed. The real app never ships with it switched on.

## 6. What isn't automated

- **Signing in through the real browser sheet.** `ASWebAuthenticationSession` shows a system sheet
  that UI tests can't fully drive, and GitHub's macOS runners can't run Liferay in Docker. Chapter 04's
  checkpoint covers it by hand, and `oauth-pkce-test.sh` covers the same HTTP flow from the terminal.
- **A real device.** Run on an iPhone at least once before release (Keychain, networking, performance).

## Checkpoint

- `cd ios/LiferayKit && swift test`: all tests pass.
- **⌘U** in Xcode: the app tests pass.
- `cd liferay && ./scripts/smoke-test.sh`: **All checks passed.**

Next: [10 — Production hardening](10-production-hardening.md).
