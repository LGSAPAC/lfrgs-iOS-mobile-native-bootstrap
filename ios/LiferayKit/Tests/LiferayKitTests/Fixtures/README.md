# Liferay API fixtures

Real responses from Liferay DXP `2026.q1.14-lts` (Docker image tag),
recorded by [`liferay/scripts/record-fixtures.sh`](../../../../../liferay/scripts/record-fixtures.sh).
Do not edit by hand: re-record instead. Ids, dates and URLs come from a throwaway local instance.

| File | Request | Status | As |
|---|---|---|---|
| `my-user-account.json` | `GET /o/headless-admin-user/v1.0/my-user-account` | 200 | jane.doe |
| `user-account-patched.json` | `PATCH /o/headless-admin-user/v1.0/user-accounts/34267` | 200 | jane.doe |
| `postal-addresses-page.json` | `GET /o/headless-admin-user/v1.0/user-accounts/34267/postal-addresses` | 200 | jane.doe |
| `postal-address.json` | `GET /o/headless-admin-user/v1.0/postal-addresses/34944` | 200 | jane.doe |
| `postal-address-patched.json` | `PATCH /o/headless-admin-user/v1.0/postal-addresses/34944` | 200 | jane.doe |
| `countries-page.json` | `GET /o/headless-admin-address/v1.0/countries?pageSize=3&sort=name:asc` | 200 | jane.doe |
| `regions-page.json` | `GET /o/headless-admin-address/v1.0/countries/20377/regions?pageSize=3&sort=name:asc` | 200 | jane.doe |
| `service-request-created.json` | `POST /o/c/servicerequests` | 200 | jane.doe |
| `service-request.json` | `GET /o/c/servicerequests/34945` | 200 | jane.doe |
| `service-request-patched.json` | `PATCH /o/c/servicerequests/34945` | 200 | jane.doe |
| `service-requests-page.json` | `GET /o/c/servicerequests?page=1&pageSize=20&sort=dateCreated:desc` | 200 | jane.doe |
| `service-requests-page-filtered.json` | `GET /o/c/servicerequests?pageSize=20&filter=requestStatus%20eq%20%27inProgress%27&search=VPN` | 200 | jane.doe |
| `service-requests-page-empty.json` | `GET /o/c/servicerequests?pageSize=20` | 200 | john.roe |
| `error-400-missing-required-field.json` | `POST /o/c/servicerequests` | 400 | jane.doe |
| `error-403-invalid-picklist-key.json` | `POST /o/c/servicerequests` | 403 | jane.doe |
| *(no file: empty body)* error-401-invalid-bearer-token | `GET /o/headless-admin-user/v1.0/my-user-account` | 401 | bearer-invalid |
| `error-403-update-other-user.json` | `PATCH /o/headless-admin-user/v1.0/user-accounts/34267` | 403 | john.roe |
| `error-404-other-users-request.json` | `GET /o/c/servicerequests/34945` | 404 | john.roe |
| `oauth-token-error-invalid-authorization_code.json` | `POST /o/oauth2/token` (grant_type=authorization_code) | 400 | - |
| `oauth-token-error-invalid-refresh_token.json` | `POST /o/oauth2/token` (grant_type=refresh_token) | 400 | - |
| `oauth-token-response.json` | `POST /o/oauth2/token` (grant_type=authorization_code, PKCE) | 200 | jane.doe |
| `oauth-refresh-response.json` | `POST /o/oauth2/token` (grant_type=refresh_token) | 200 | jane.doe |

The two successful token responses need a browser sign-in, so they are captured separately with
`liferay/scripts/oauth-pkce-test.sh`. Token values are replaced with `REDACTED-<length>-chars`
(the originals were ~1 KB access tokens and 61-character refresh tokens).
