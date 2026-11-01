# 03 — Create the iOS project

In this chapter you set up the Xcode project. It has two parts:

- **`LiferayKit`**, a local Swift package with everything that talks to Liferay: OAuth 2, tokens,
  the API client and the models. It has no UI and no third-party dependencies, so it is easy to test.
- **`LiferaySelfService`**, the SwiftUI app. It holds screens and app state, and uses `LiferayKit`.

Splitting them keeps networking code out of views, and lets the package's unit tests run without a
simulator. The CI even runs them on Linux.

**Time:** about 20 minutes. **You need:** a Mac with Xcode 16 or later, and Liferay set up as in
chapters 01–02, with the OAuth 2 application's **Client ID** to hand.

> **Status:** the `LiferayKit` package and its tests are verified (`swift test`, Swift 6.1). The app
> sources and these Xcode steps have not yet been built on a Mac; please report anything that
> doesn't match ([CONTRIBUTING.md](../../CONTRIBUTING.md)).

## 1. What is already in the repository

```
ios/
├── Config/
│   ├── Shared.xcconfig            # includes Local.xcconfig if present
│   └── Local.xcconfig.example     # copy to Local.xcconfig (git-ignored)
├── LiferayKit/                    # Swift package (chapters 04–05)
│   ├── Package.swift
│   ├── Sources/LiferayKit/{Auth,HTTP,Models}/
│   └── Tests/LiferayKitTests/     # unit tests + recorded Liferay responses
└── LiferaySelfService/            # app sources
    ├── App/                       # @main, AppModel, RootView
    ├── Features/{Login,Home}/
    └── Info.plist                 # Liferay settings + local HTTP exception
```

## 2. Configure your Liferay settings

```bash
cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig
```

Edit `ios/Config/Local.xcconfig` and paste your Client ID:

```
LIFERAY_BASE_URL = http:/$()/localhost:8080
OAUTH_CLIENT_ID = id-5ed879da-…
OAUTH_REDIRECT_URI = com.liferay.sample.selfservice:/$()/oauth2redirect
```

> **Gotcha: `//` in `.xcconfig` files.** In an `.xcconfig` file, `//` starts a comment, so
> `http://localhost:8080` silently becomes `http:`. The empty `$()` breaks up the two slashes and
> expands to nothing at build time.

`Local.xcconfig` is git-ignored: each developer has their own Client ID, and nothing
environment-specific is committed.

## 3. Create the Xcode project

1. In Xcode, choose **File → New → Project… → iOS → App**, then **Next**.
2. Fill in:

   | Field | Value |
   |---|---|
   | Product Name | `LiferaySelfService` |
   | Interface | SwiftUI |
   | Language | Swift |
   | Testing System | Swift Testing *(or None)* |
   | Storage | None |

3. Save it in a **temporary** folder, for example the Desktop, with *Create Git repository* **off**.
   (Saving straight into `ios/` would clash with the existing `ios/LiferaySelfService` folder.)
4. Close Xcode. Move the generated `LiferaySelfService.xcodeproj` into the repository's `ios/` folder,
   then delete the rest of the temporary folder.
5. Open `ios/LiferaySelfService.xcodeproj`. In the Project navigator, the template's
   `LiferaySelfService` group now appears in red because its files are gone. Select it and press
   **Delete**.
6. Drag the repository's `ios/LiferaySelfService` folder into the Project navigator. Choose
   **Reference files in place**, make sure the *LiferaySelfService* target is ticked, and click
   **Finish**.

## 4. Point the target at the settings and Info.plist

Select the project, then the **LiferaySelfService** target:

1. **Build Settings** → search *Info.plist File* → set it to `LiferaySelfService/Info.plist`.
   Leave *Generate Info.plist File* on: Xcode merges its generated keys with this file.
2. Select the **project** (not the target) → **Info** → **Configurations**. For both *Debug* and
   *Release*, set the *LiferaySelfService* target's configuration file to `Shared`
   (`ios/Config/Shared.xcconfig`; use **Add Files** first if it isn't listed).
3. **General** → *Minimum Deployments* → **iOS 17.0**.
4. **Build Settings** → *Swift Language Version* → **Swift 6**.

The custom keys in `Info.plist` (`LiferayBaseURL`, `OAuthClientID`, `OAuthRedirectURI`) take their
values from the xcconfig. `LiferayConfiguration(bundle:)` reads them at runtime.

You don't need to register the `com.liferay.sample.selfservice` URL scheme under *URL Types*:
`ASWebAuthenticationSession` catches the redirect itself (chapter 04).

## 5. Add the LiferayKit package

1. **File → Add Package Dependencies… → Add Local…** and choose `ios/LiferayKit`.
2. Add the **LiferayKit** library to the *LiferaySelfService* target.

## 6. Allow HTTP to localhost (local development only)

The local Liferay runs on plain `http://localhost:8080`. App Transport Security blocks plain HTTP by
default, so `Info.plist` sets **`NSAllowsLocalNetworking`**. That allows HTTP only to local
addresses such as `localhost`, never to internet hosts. A real Liferay must use HTTPS, and chapter 10
covers removing this exception.

## Checkpoint

- Select an iPhone simulator and press **⌘R**.
- The app shows **Liferay Self-Service** with a **Sign in** button.
- If you see **Not configured** instead, `Local.xcconfig` is missing, isn't set as the configuration
  file (step 4.2), or contains an unescaped `//`.
- Optionally, in Terminal: `cd ios/LiferayKit && swift test`. All tests should pass.

Next: [04 — Sign in with OAuth 2 + PKCE](04-sign-in-oauth-pkce.md).
