# Security

## Reporting a vulnerability

Please **do not open a public issue** for a security problem in this repository's code or scripts.
Report it privately via GitHub: the repository's **Security** tab → **Report a vulnerability**.

Vulnerabilities in **Liferay DXP itself** are not handled here; report them through Liferay's official
security reporting process.

## Known, intentional weaknesses of the local setup

This repository is a tutorial. To keep it easy to follow, the local Liferay setup is deliberately
**not** secure. Never expose it to a network or reuse it for real environments:

| Weakness | Where | In a real environment |
|---|---|---|
| Default admin `test@liferay.com` / `test` | `liferay/configs/portal-ext.properties` | Strong unique admin password; setup wizard or managed provisioning |
| Tutorial users' password is in the repository | `liferay/scripts/setup.sh` (`TUTORIAL_USER_PASSWORD`) | Real users set their own passwords |
| First-login checks disabled (terms of use, password change, email verification) | `portal-ext.properties` | Keep Liferay's defaults |
| HTTP Basic auth used by the setup and test scripts | `liferay/scripts/` | OAuth 2 only; disable Basic auth for headless APIs if unused |
| Plain HTTP and a dev-only `http://localhost:9999/callback` redirect URI | Chapter 02 | HTTPS only; remove the dev callback URI |
| Embedded Hypersonic database | `portal-ext.properties` | A supported production database |

The iOS app itself follows production practice: OAuth 2 Authorization Code with PKCE, no client
secret, tokens in the Keychain, and HTTP allowed for `localhost` in Debug builds only.
