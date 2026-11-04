# 01 — Run Liferay DXP 2026.Q1 locally

> **Unofficial reference.** This tutorial is an unofficial reference, not official Liferay
> documentation, and is not supported by Liferay. See [learn.liferay.com](https://learn.liferay.com)
> for official documentation.

In this chapter you start a local Liferay DXP 2026.Q1 instance in Docker and explore the headless
APIs the iOS app will use.

**Time:** about 15 minutes, mostly waiting for the first start.

## What you need

| Tool | Notes |
|---|---|
| Docker Desktop (or another Docker engine with Compose v2) | Give Docker at least **6 GB of memory** |
| A Liferay DXP activation key *(maybe)* | See step 1 |
| `curl` and `jq` | Used by the setup scripts (`brew install jq` on macOS) |

## 1. Add your activation key (if needed)

When tested, the `2026.q1.14-lts` image registered a built-in **DXP Development** licence on startup,
so it ran locally with no key. If your container logs ask for activation instead, request a trial key
from Liferay and copy the `.xml` file into `liferay/deploy/`:

```bash
cp ~/Downloads/activation-key-*.xml liferay/deploy/
```

`liferay/deploy/*.xml` is git-ignored, so the key is never committed.

## 2. Start Liferay

```bash
cd liferay
docker compose up -d
docker compose logs -f liferay
```

Wait for this line (the first start takes a few minutes):

```
INFO  [main][Server:...] Server startup in [...] milliseconds
```

Then open <http://localhost:8080> and sign in as **`test@liferay.com`** with the password **`test`**.

### What the compose file does

[`liferay/docker-compose.yml`](../../liferay/docker-compose.yml):

- Runs the image `liferay/dxp:2026.q1.14-lts`, the latest 2026.Q1 LTS patch when this was written.
  Override it with `LIFERAY_DXP_TAG=2026.q1.<n>-lts docker compose up -d`.
- Copies [`configs/portal-ext.properties`](../../liferay/configs/portal-ext.properties) into
  Liferay. It turns off the setup wizard and the first-login screens (terms of use, password reminder,
  forced password change, email verification), so the tutorial users can sign in from the app straight away.
- **Uses a fresh database.** The image ships a pre-built Hypersonic database, created with Liferay's
  default settings. Those defaults force the admin to change their password on first sign-in, and
  until then every API call returns `403`. The properties file therefore points Liferay at a new
  database file (`data/hypersonic-tutorial`), so the settings above apply from the first start.
- Mounts `deploy/` for the activation key, and stores data in the `liferay-data` volume so it
  survives restarts.

> **Local development only.** This setup uses the embedded Hypersonic database and relaxed
> first-login settings. A real environment needs a supported database, HTTPS, and the defaults
> restored.

Useful commands:

```bash
docker compose stop          # stop, keep data
docker compose down -v       # stop and delete all data (start fresh)
```

## 3. Explore the APIs

Liferay documents every headless API in the **API Explorer**: open <http://localhost:8080/o/api>.
This is the reference for the rest of the tutorial. The APIs the app uses are:

| API | Base path | Used for |
|---|---|---|
| Headless Admin User | `/o/headless-admin-user/v1.0` | The signed-in user's profile and postal addresses (system objects) |
| Headless Admin Address | `/o/headless-admin-address/v1.0` | Countries and regions for the address form |
| Service Request (custom object) | `/o/c/servicerequests` | Created in chapter 02 |
| OAuth 2 | `/o/oauth2/authorize`, `/o/oauth2/token`, `/o/oauth2/revoke` | Sign-in, token refresh, sign-out |

Try one from the terminal:

```bash
curl -s -u test@liferay.com:test \
  http://localhost:8080/o/headless-admin-user/v1.0/my-user-account | jq '{id, name, emailAddress}'
```

> The scripts in this tutorial use HTTP Basic auth with the admin account **only to set up
> Liferay**. The iOS app never does: it signs users in with OAuth 2 (chapter 04).

## Checkpoint

- <http://localhost:8080> loads and you can sign in as the admin.
- `curl` to `my-user-account` returns the admin's details.

Next: [02 — Configure Liferay for a self-service user](02-configure-liferay.md).
