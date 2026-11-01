#!/usr/bin/env bash
#
# Walks through the OAuth 2 Authorization Code + PKCE flow by hand, exactly as the iOS app will,
# so you can confirm the OAuth 2 application works before writing any Swift.
#
#   OAUTH_CLIENT_ID=id-xxxxxxxx ./oauth-pkce-test.sh
#
# The script uses the dev-only redirect URI http://localhost:9999/callback. Your browser will show
# "can't connect" after you sign in; that is expected. Copy the full URL from the address bar.
#
# Requires: bash, curl, jq, openssl

set -euo pipefail
# Make "set -e" apply inside $(...) too, so a failed request stops the script.
shopt -s inherit_errexit 2>/dev/null || true  # Bash 4.4+; macOS ships Bash 3.2

# Never wait forever on a request: a Liferay that accepts connections but doesn't answer yet would
# otherwise hang the script (and CI) indefinitely. CURL_MAX_TIME overrides the per-request limit.
curl() { command curl --connect-timeout 10 --max-time "${CURL_MAX_TIME:-120}" "$@"; }

LIFERAY_URL="${LIFERAY_URL:-http://localhost:8080}"
REDIRECT_URI="${REDIRECT_URI:-http://localhost:9999/callback}"
: "${OAUTH_CLIENT_ID:?Set OAUTH_CLIENT_ID to the Client ID shown in OAuth 2 Administration}"

base64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
urlencode() { jq -rn --arg v "$1" '$v | @uri'; }

# 1. PKCE: a random code_verifier and its SHA-256 code_challenge (RFC 7636).
code_verifier=$(openssl rand 32 | base64url)
code_challenge=$(printf '%s' "$code_verifier" | openssl dgst -sha256 -binary | base64url)
state=$(openssl rand 16 | base64url)

authorize_url="$LIFERAY_URL/o/oauth2/authorize?response_type=code"
authorize_url+="&client_id=$(urlencode "$OAUTH_CLIENT_ID")"
authorize_url+="&redirect_uri=$(urlencode "$REDIRECT_URI")"
authorize_url+="&code_challenge=$code_challenge&code_challenge_method=S256&state=$state"

cat <<EOF

1) Open this URL in a browser and sign in as jane.doe@example.com:

$authorize_url

2) After signing in (and approving access, unless the app is Trusted), the browser is redirected to
   $REDIRECT_URI?code=...&state=...  Paste that full URL here:

EOF
read -r -p "> " callback_url

code=$(sed -n 's/.*[?&]code=\([^&]*\).*/\1/p' <<<"$callback_url")
returned_state=$(sed -n 's/.*[?&]state=\([^&]*\).*/\1/p' <<<"$callback_url")

[[ -n "$code" ]] || { echo "error: no code= in that URL" >&2; exit 1; }
[[ "$returned_state" == "$state" ]] || { echo "error: state mismatch (possible CSRF)" >&2; exit 1; }

# 2. Exchange the code + code_verifier for tokens. Public client: no client secret.
echo; echo "3) Exchanging the authorization code for tokens..."
tokens=$(curl -fsS "$LIFERAY_URL/o/oauth2/token" \
	--data-urlencode grant_type=authorization_code \
	--data-urlencode "client_id=$OAUTH_CLIENT_ID" \
	--data-urlencode "code=$code" \
	--data-urlencode "redirect_uri=$REDIRECT_URI" \
	--data-urlencode "code_verifier=$code_verifier")

jq '{token_type, expires_in, scope, has_refresh_token: (.refresh_token != null)}' <<<"$tokens"
access_token=$(jq -r '.access_token' <<<"$tokens")
refresh_token=$(jq -r '.refresh_token // empty' <<<"$tokens")

# 3. Call APIs as Jane with the Bearer token.
echo; echo "4) GET my-user-account with the access token:"
curl -fsS -H "Authorization: Bearer $access_token" \
	"$LIFERAY_URL/o/headless-admin-user/v1.0/my-user-account" | jq '{id, name, emailAddress}'

echo; echo "5) GET Jane's service requests with the access token:"
curl -fsS -H "Authorization: Bearer $access_token" \
	"$LIFERAY_URL/o/c/servicerequests?pageSize=5" | jq '{totalCount, titles: [.items[].title]}'

# 4. Refresh. By default Liferay returns the same refresh token; store whichever one the response holds.
#    Note: Liferay 2026.Q1 has no token revocation endpoint (RFC 7009). The app signs out by deleting
#    its tokens; an admin can revoke a user's authorization in OAuth 2 Administration.
if [[ -n "$refresh_token" ]]; then
	echo; echo "6) Refreshing the access token:"
	refreshed=$(curl -fsS "$LIFERAY_URL/o/oauth2/token" \
		--data-urlencode grant_type=refresh_token \
		--data-urlencode "client_id=$OAUTH_CLIENT_ID" \
		--data-urlencode "refresh_token=$refresh_token")
	jq '{expires_in, new_refresh_token_issued: (.refresh_token != null and .refresh_token != $old)}' \
		--arg old "$refresh_token" <<<"$refreshed"

	echo; echo "7) The new access token works:"
	curl -fsS -H "Authorization: Bearer $(jq -r '.access_token' <<<"$refreshed")" \
		"$LIFERAY_URL/o/headless-admin-user/v1.0/my-user-account" | jq '{name}'
else
	echo "warning: no refresh_token returned; enable the Refresh Token grant on the OAuth 2 application" >&2
fi

echo; echo "OAuth 2 + PKCE works. The iOS app will do exactly these steps."
