# 11 — Next steps

You now have a native iOS app that signs users in with OAuth 2 + PKCE and manages their own data in
Liferay: a system object (User, Postal Address) and a custom object (Service Request). Here are ideas
for taking it further, roughly from easiest to most involved.

## Extend what's there

- **Attachments on Service Requests.** Add an *Attachment* field to the object, then upload with
  `PhotosPicker`. Object attachment fields take a document reference, so expect an extra upload step.
- **Comments.** Turn on comments for the object and show the conversation on the detail screen.
- **More fields from the user's profile**: phone numbers, websites, avatar. The same
  `userAccountContactInformation` pattern as addresses applies (chapter 07), including "send the full
  list".
- **Localization.** Picklist names and error messages already follow `Accept-Language`. Add a String
  Catalog (`Localizable.xcstrings`) for the app's own text.

## Liferay features worth wiring in

- **Workflow on object entries.** Enable a workflow for Service Requests; new entries then start as
  *Pending* (`status.code` ≠ 0) until approved. Show that status in the list.
- **Object actions.** Run an action when an entry changes, for example a webhook that sends an Apple
  Push Notification through your notification service when a request is closed.
- **Account-restricted objects** for business-to-business self-service: entries belong to the user's
  *Account* (company), so colleagues share requests. The list then filters by account instead of
  owner.
- **Validations** on the object (for example, *due date must be in the future*). Their messages come
  back in the `title` of the `400` response, and the app already shows those.

## Engineering

- **Offline support.** Cache lists with SwiftData; queue creates by external reference code (already
  idempotent) and send them when the network returns.
- **Generated models.** Every Liferay headless API publishes an OpenAPI description (browse them in the
  API Explorer at `/o/api`). Apple's `swift-openapi-generator` can generate clients from it. This tutorial writes models by hand to keep it
  readable and dependency-free.
- **Android.** `LiferayKit`'s design (transport abstraction, single-flight refresh, drafts that encode
  only what Liferay accepts) maps directly to Kotlin with Ktor or OkHttp.
- **UI tests** with XCUITest for the forms, using `--demo` so they need no server.

## Contribute

Found something that didn't work as written? A Liferay behaviour that changed in a newer patch? Please
open an issue or a pull request: [CONTRIBUTING.md](../../CONTRIBUTING.md). Every change is checked
against a running Liferay in CI, so the tutorial stays true.
