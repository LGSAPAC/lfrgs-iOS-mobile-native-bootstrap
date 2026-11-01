# 02 — Configure Liferay for a self-service user

In this chapter you prepare everything the app needs on the Liferay side:

1. A **Service Request** custom object, with two picklists.
2. Permission for ordinary users to create service requests.
3. Two self-service users, **Jane** and **John**, with no admin rights.
4. An **OAuth 2 application** for the iOS app.

Steps 1–3 are scripted. Step 4 is done in the UI, so you see each OAuth 2 setting and why it matters.
Before writing any Swift, you prove every API call works with `curl`.

**Time:** about 20 minutes.

## 1. Run the setup script

With Liferay running (chapter 01):

```bash
cd liferay
./scripts/setup.sh
```

Expected output (ids will differ):

```
==> Upserting picklists
  SERVICE_REQUEST_CATEGORY: account, billing, technical, other
  SERVICE_REQUEST_STATUS: open, inProgress, closed

==> Upserting the Service Request object
  publishing object definition 34567
  id=34567 status=Approved REST=/o/c/servicerequests

==> Granting the 'User' role permission to add Service Requests
  role=20107 resource=com.liferay.object#34567 action=ADD_OBJECT_ENTRY

==> Upserting tutorial users (password: $TUTORIAL_USER_PASSWORD)
  jane.doe@example.com (id=34601)
  john.roe@example.com (id=34615)
```

The script is safe to run again: every step is an upsert keyed by an **external reference code**
(ERC), a stable id you choose. Re-running updates the same records instead of creating copies.
The tutorial users' password defaults to `Tutorial-2026!`; set `TUTORIAL_USER_PASSWORD` to change it.

### What the script creates

**Picklists** ([`setup/picklists.json`](../../liferay/setup/picklists.json)) via
`PUT /o/headless-admin-list-type/v1.0/list-type-definitions/by-external-reference-code/{erc}`:

| Picklist | Keys |
|---|---|
| Service Request Category | `account`, `billing`, `technical`, `other` |
| Service Request Status | `open`, `inProgress`, `closed` |

**The Service Request object** ([`setup/service-request-object.json`](../../liferay/setup/service-request-object.json))
via `PUT /o/object-admin/v1.0/object-definitions/by-external-reference-code/SERVICE_REQUEST`,
then `POST …/object-definitions/{id}/publish`:

| Field | Type | Required | Notes |
|---|---|---|---|
| `title` | Text | yes | Shown as the entry title |
| `description` | Long Text | no | |
| `category` | Picklist | yes | Service Request Category |
| `requestStatus` | Picklist | yes | Service Request Status. Named `requestStatus` because every object entry already has a workflow `status` |
| `priority` | Integer | no | 1 (high) – 3 (low) |
| `dueDate` | Date | no | |

The object is **company scoped**, so its entries are not tied to a site. Publishing it generates a
REST API at **`/o/c/servicerequests`**, plus an OAuth 2 scope named after the object
(`c_servicerequest`). Liferay also adds system fields to every entry: `id`, `externalReferenceCode`,
`creator`, `dateCreated`, `dateModified` and `status`.

> **Prefer clicking?** You can build the same object in **Control Panel → Objects**, and the
> picklists in **Control Panel → Picklists**. Use the field names above exactly, because the app
> depends on them.

**Permission** via `PATCH /o/headless-admin-user/v1.0/roles/{id}`: the built-in **User** role (every
signed-in user has it) gets `ADD_OBJECT_ENTRY` on the Service Request object. This PATCH only *adds*
permissions; it never removes existing ones.

There is no "view all" permission. A user who creates an entry becomes its **owner**, and Liferay's
default owner permissions let them view, update and delete their own entries. Nobody else can, apart
from admins. Each user therefore sees **only their own requests**, and the server enforces that:
the app never filters by user.

**Users** via `PUT /o/headless-admin-user/v1.0/user-accounts/by-external-reference-code/{erc}`:

| User | Email | Roles |
|---|---|---|
| Jane Doe | `jane.doe@example.com` | User (default) |
| John Roe | `john.roe@example.com` | User (default) |

## 2. Verify the APIs as a self-service user

[`scripts/smoke-test.sh`](../../liferay/scripts/smoke-test.sh) calls every endpoint the app uses,
**as Jane and John**, not as the admin:

```bash
./scripts/smoke-test.sh
```

```
System object: User profile (as Jane)
  PASS GET my-user-account (HTTP 200)
  PASS PATCH own user account (jobTitle) (HTTP 200)
  ...
Isolation (as John)
  PASS John does not see Jane's request in the list
  PASS John cannot read Jane's request (HTTP 404)
  ...
All checks passed.
```

Read the script alongside this section; it is the API contract for chapters 06–08.

### System objects: the user's profile and postal addresses

| Operation | Request |
|---|---|
| Read my profile | `GET /o/headless-admin-user/v1.0/my-user-account` |
| Update my profile | `PATCH /o/headless-admin-user/v1.0/user-accounts/{myId}` |
| List my addresses | `GET /o/headless-admin-user/v1.0/user-accounts/{myId}/postal-addresses` |
| **Create** an address | `PATCH /o/headless-admin-user/v1.0/user-accounts/{myId}` with `userAccountContactInformation.postalAddresses` |
| Read / update / delete an address | `GET` / `PATCH` / `DELETE /o/headless-admin-user/v1.0/postal-addresses/{id}` |
| Countries for the form | `GET /o/headless-admin-address/v1.0/countries` |

> **Gotcha: creating a user's address.** In 2026.Q1 there is no `POST` endpoint for a *user's*
> postal addresses; accounts and organizations have one, users do not. To add an address, `PATCH`
> the user account with the **complete** address list: every existing address (by `id`) plus the new
> one. Any address you leave out is **deleted**. Chapter 07 wraps this in a small repository method
> so the rest of the app never sees it.

### Custom object: Service Requests

| Operation | Request |
|---|---|
| List (paged, filtered, sorted, searched) | `GET /o/c/servicerequests?page=1&pageSize=20&sort=dateCreated:desc&filter=requestStatus eq 'open'&search=printer` |
| Read | `GET /o/c/servicerequests/{id}` |
| Create | `POST /o/c/servicerequests` |
| Update (partial) | `PATCH /o/c/servicerequests/{id}` |
| Delete | `DELETE /o/c/servicerequests/{id}` |
| Idempotent create/update | `PUT /o/c/servicerequests/by-external-reference-code/{erc}` |

Picklist values are **sent** as `{"key": "open"}` and **returned** as `{"key": "open", "name": "Open"}`.
`name` is localized to the request's `Accept-Language`.

> **Gotcha: unknown picklist keys return `403 Forbidden`.** Sending a key that isn't in the picklist
> (for example `{"key": "nope"}`) does not return a validation error. Liferay answers with a generic
> `403 Forbidden`. The app therefore only ever sends keys from the picklist, and a 403 on create does
> not necessarily mean "permission denied".

Other details of the responses that the Swift models must handle:

- Dates come in two formats: `dateCreated` is `2026-11-01T03:40:37Z`, but a Date field such as `dueDate`
  (sent as `2026-12-31`) comes back as `2026-12-31T00:00:00.000Z`, with fractional seconds.
- Lists are pages: `items`, `page`, `pageSize`, `totalCount`, `lastPage` (plus `actions` and `facets`).
- Errors have a JSON body `{"status": "BAD_REQUEST", "title": "No value was provided for required object field \"title\""}`,
  **except `401`**, whose body is empty.

### Recorded responses

[`scripts/record-fixtures.sh`](../../liferay/scripts/record-fixtures.sh) saves the real response to
every call above as JSON, in `ios/LiferayKit/Tests/LiferayKitTests/Fixtures/`. The Swift unit tests
(chapter 09) decode these files, so the app is tested against what Liferay 2026.Q1 actually returns.
Re-run it when you upgrade Liferay:

```bash
OAUTH_CLIENT_ID=id-xxxxxxxx ./scripts/record-fixtures.sh   # OAUTH_CLIENT_ID is optional
```

## 3. Create the OAuth 2 application

The app signs users in with **OAuth 2 Authorization Code + PKCE**, the flow recommended for native
apps (RFC 8252). In this flow the app holds **no client secret**: PKCE proves that the app which
started sign-in is the same one redeeming the code.

Sign in at <http://localhost:8080> as the admin. On the first admin sign-in, DXP may show a
*Liferay Enterprise Search* terms dialog; click **Done**.

### 3a. Credentials

1. Open **Control Panel → Security → OAuth 2 Administration** and click **Add** (+).
2. Fill in the form:

   | Field | Value |
   |---|---|
   | Name | `iOS Self-Service Tutorial` |
   | Callback URIs | `com.liferay.sample.selfservice://oauth2redirect` <br> `http://localhost:9999/callback` *(dev only, for the curl test below; remove it later)* |
   | Client Authentication Method | **None** (a public client: no secret) |
   | Client Profile | **Native Application** |
   | Allowed Authorization Types | ✅ **PKCE Extended Authorization Code**, ✅ **Refresh Token**; untick `JWT_BEARER` and *Resource Owner Password Credentials* |
   | Trusted Application | Optional (see below) |

   Why *Native Application*: it is the only Liferay client profile that offers both
   **PKCE Extended Authorization Code** and **Refresh Token**. With refresh tokens, users stay signed
   in after the access token expires. Access tokens last **10 minutes** by default.

   Liferay accepts custom URL schemes as callback URIs, as long as they are not IANA-registered
   schemes. Use a reverse-domain scheme you control, as RFC 8252 recommends.

   **Trusted Application** skips the *Authorize* consent screen. That suits a first-party company app;
   leave it off to show users what they are granting.

3. Click **Save**, then copy the generated **Client ID** (it looks like `id-5ed879da-…`). The
   *Client Secret* stays empty.

### 3b. Scopes

Open the **Scopes** tab, expand these three applications, tick one checkbox in each, and click **Save**:

| Application | Checkbox | Scope granted |
|---|---|---|
| `LIFERAY.HEADLESS.ADMIN.USER` | create/update/delete data on your behalf + read data on your behalf | `Liferay.Headless.Admin.User.everything` |
| `LIFERAY.HEADLESS.ADMIN.ADDRESS` | read data on your behalf | `Liferay.Headless.Admin.Address.everything.read` |
| `C_SERVICEREQUEST` | create/update/delete data on your behalf + read data on your behalf | `c_servicerequest.everything` |

Scopes cap what the **app** may call. They never grant the **user** extra rights: a call still
needs the signed-in user's own permissions. For example, Jane holding the
`Liferay.Headless.Admin.User` write scope still cannot edit John.

### 3c. Let ordinary users authorize the app

> **Easy to miss.** By default only admins can authorize an OAuth 2 application. A regular user who
> signs in gets **"You do not have the required permissions"** instead of the consent screen.

To authorize an app, a user needs **View** *and* **Create Token** on that application:

1. Go back to the **OAuth 2 Administration** list.
2. Open the actions menu (⋮) of *iOS Self-Service Tutorial* → **Permissions**.
3. In the **User** row (every signed-in user has this role), tick **View** and **Create Token**, then
   click **Save**.

These permissions apply to this one application only.

## 4. Test the OAuth 2 flow with curl

[`scripts/oauth-pkce-test.sh`](../../liferay/scripts/oauth-pkce-test.sh) performs exactly the steps
the iOS app will perform in chapter 04:

```bash
OAUTH_CLIENT_ID=id-xxxxxxxx ./scripts/oauth-pkce-test.sh
```

1. It generates a PKCE `code_verifier` and `code_challenge`, plus a random `state`.
2. It prints an authorize URL. Open it, sign in as **jane.doe@example.com**, and click **Authorize**
   on the consent screen (unless the app is Trusted).
3. The browser is redirected to `http://localhost:9999/callback?code=…&state=…` and shows
   "can't connect". That is expected: copy the URL from the address bar and paste it into the script.
4. The script exchanges the code for tokens, calls `my-user-account` and `/o/c/servicerequests` with
   the access token, then refreshes the token and calls the API again.

Expected output (abridged):

```json
{
  "token_type": "Bearer",
  "expires_in": 600,
  "scope": "c_servicerequest.everything Liferay.Headless.Admin.User.everything Liferay.Headless.Admin.Address.everything.read",
  "has_refresh_token": true
}
{ "id": 34267, "name": "Jane Doe", "emailAddress": "jane.doe@example.com" }
```

Two behaviours to design the app around:

- **Refresh tokens are not rotated by default.** The refresh response may return the same refresh
  token. The app still stores whatever token the response holds, so it keeps working if rotation is
  ever turned on.
- **There is no token revocation endpoint** in 2026.Q1; Liferay serves only `authorize`, `token` and
  `introspect`. The app signs out by deleting its tokens from the Keychain and not reusing the
  browser session (chapter 04). An admin can revoke a user's authorization in the application's
  **Authorizations** tab in OAuth 2 Administration.

## Checkpoint

- `./scripts/setup.sh` completes, and re-running it changes nothing.
- `./scripts/smoke-test.sh` prints **All checks passed**.
- `oauth-pkce-test.sh` shows Jane's profile via a Bearer token, and the refresh succeeds.
- Jane reaches the **Authorize** screen, not a permissions error (step 3c).
- You have noted the **Client ID**. Chapter 03 puts it in `ios/Config/Local.xcconfig`.

Next: [03 — Create the iOS project](03-create-ios-project.md).
