#!/usr/bin/env bash
#
# Records real Liferay API responses as JSON fixtures for the iOS unit tests, so the Swift models
# are tested against what Liferay actually returns, not against hand-written guesses.
#
#   ./scripts/record-fixtures.sh [output-dir]
#
# Run after setup.sh. Calls are made as the self-service users (Jane and John), exactly like the app.
# Temporary records created here are deleted at the end. Re-run whenever the Liferay version changes.
#
# Requires: bash, curl, jq

set -euo pipefail

LIFERAY_URL="${LIFERAY_URL:-http://localhost:8080}"
TUTORIAL_USER_PASSWORD="${TUTORIAL_USER_PASSWORD:-Tutorial-2026!}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:-$ROOT/ios/LiferayKit/Tests/LiferayKitTests/Fixtures}"
JANE="jane.doe@example.com"
JOHN="john.roe@example.com"
USER_API="/o/headless-admin-user/v1.0"
ADDRESS_API="/o/headless-admin-address/v1.0"
SR_API="/o/c/servicerequests"

mkdir -p "$OUT"
INDEX="$(mktemp)"

# record NAME EXPECTED_STATUS USER METHOD PATH [JSON_BODY]
# Saves the pretty-printed body to $OUT/NAME.json and prints the body on stdout.
record() {
	local name="$1" expected="$2" user="$3" method="$4" path="$5" body="${6:-}" args response status
	args=(-sS -w '\n%{http_code}' -X "$method" -H 'Accept: application/json' -H 'Accept-Language: en-US')
	case "$user" in
		bearer-invalid) args+=(-H 'Authorization: Bearer invalid-token') ;;
		*) args+=(-u "$user:$TUTORIAL_USER_PASSWORD") ;;
	esac
	[[ -n "$body" ]] && args+=(-H 'Content-Type: application/json' --data-binary "$body")

	response=$(curl "${args[@]}" "$LIFERAY_URL$path")
	status="${response##*$'\n'}"
	response="${response%$'\n'*}"

	if [[ "$status" != "$expected" ]]; then
		echo "error: $name: $method $path -> HTTP $status (expected $expected)" >&2
		echo "$response" >&2
		exit 1
	fi

	if [[ -n "$response" ]]; then
		jq . <<<"$response" >"$OUT/$name.json"
		echo "| \`$name.json\` | \`$method $path\` | $status | ${user%%@*} |" >>"$INDEX"
	else
		echo "| *(no file: empty body)* $name | \`$method $path\` | $status | ${user%%@*} |" >>"$INDEX"
	fi

	echo "  $name ($status)" >&2
	printf '%s' "$response"
}

as_jane() { curl -sS -u "$JANE:$TUTORIAL_USER_PASSWORD" -H 'Accept: application/json' "$@"; }

# Remove records left behind by an earlier, interrupted run (and on exit, by this run).
cleanup() {
	local id
	as_jane -o /dev/null -X DELETE "$LIFERAY_URL$SR_API/by-external-reference-code/fixture-sr-0001" || true
	for id in $(as_jane "$LIFERAY_URL$USER_API/my-user-account" | jq -r '.id' | xargs -I{} \
		curl -sS -u "$JANE:$TUTORIAL_USER_PASSWORD" "$LIFERAY_URL$USER_API/user-accounts/{}/postal-addresses" |
		jq -r '.items[] | select(.postalCode == "91765") | .id'); do
		as_jane -o /dev/null -X DELETE "$LIFERAY_URL$USER_API/postal-addresses/$id" || true
	done
}
cleanup
trap cleanup EXIT

echo "Recording fixtures into $OUT" >&2

# --- System object: user profile -----------------------------------------------------------------

me=$(record my-user-account 200 "$JANE" GET "$USER_API/my-user-account")
jane_id=$(jq -r '.id' <<<"$me")

record user-account-patched 200 "$JANE" PATCH "$USER_API/user-accounts/$jane_id" \
	'{"jobTitle": "Customer"}' >/dev/null

# --- System object: postal addresses -------------------------------------------------------------

existing=$(curl -fsS -u "$JANE:$TUTORIAL_USER_PASSWORD" "$LIFERAY_URL$USER_API/user-accounts/$jane_id/postal-addresses" |
	jq -c '[.items[] | {id}]')
new_address='{"addressCountry": "United States", "addressLocality": "Diamond Bar", "addressRegion": "California",
  "addressType": "personal", "postalCode": "91765", "primary": true, "streetAddressLine1": "1400 Montefino Ave",
  "name": "Home"}'
curl -fsS -o /dev/null -u "$JANE:$TUTORIAL_USER_PASSWORD" -X PATCH -H 'Content-Type: application/json' \
	--data-binary "$(jq -n --argjson e "$existing" --argjson n "$new_address" '{userAccountContactInformation: {postalAddresses: ($e + [$n])}}')" \
	"$LIFERAY_URL$USER_API/user-accounts/$jane_id"

addresses=$(record postal-addresses-page 200 "$JANE" GET "$USER_API/user-accounts/$jane_id/postal-addresses")
address_id=$(jq -r '[.items[] | select(.postalCode == "91765")][0].id' <<<"$addresses")

record postal-address 200 "$JANE" GET "$USER_API/postal-addresses/$address_id" >/dev/null
record postal-address-patched 200 "$JANE" PATCH "$USER_API/postal-addresses/$address_id" \
	'{"addressLocality": "Walnut"}' >/dev/null

record countries-page 200 "$JANE" GET "$ADDRESS_API/countries?pageSize=3&sort=name:asc" >/dev/null
us_id=$(curl -fsS -u "$JANE:$TUTORIAL_USER_PASSWORD" "$LIFERAY_URL$ADDRESS_API/countries/by-a2/US" | jq -r '.id')
record regions-page 200 "$JANE" GET "$ADDRESS_API/countries/$us_id/regions?pageSize=3&sort=name:asc" >/dev/null

# --- Custom object: service requests ------------------------------------------------------------

created=$(record service-request-created 200 "$JANE" POST "$SR_API" '{"title": "Fixture: VPN keeps disconnecting",
  "description": "Recorded by record-fixtures.sh", "category": {"key": "technical"},
  "requestStatus": {"key": "open"}, "priority": 1, "dueDate": "2026-12-31",
  "externalReferenceCode": "fixture-sr-0001"}')
sr_id=$(jq -r '.id' <<<"$created")

record service-request 200 "$JANE" GET "$SR_API/$sr_id" >/dev/null
record service-request-patched 200 "$JANE" PATCH "$SR_API/$sr_id" '{"requestStatus": {"key": "inProgress"}}' >/dev/null
record service-requests-page 200 "$JANE" GET "$SR_API?page=1&pageSize=20&sort=dateCreated:desc" >/dev/null
record service-requests-page-filtered 200 "$JANE" GET \
	"$SR_API?pageSize=20&filter=requestStatus%20eq%20%27inProgress%27&search=VPN" >/dev/null
record service-requests-page-empty 200 "$JOHN" GET "$SR_API?pageSize=20" >/dev/null

# --- Errors the app must handle -------------------------------------------------------------------

record error-400-missing-required-field 400 "$JANE" POST "$SR_API" \
	'{"category": {"key": "technical"}, "requestStatus": {"key": "open"}}' >/dev/null
# Note: an unknown picklist key returns a generic 403 Forbidden, not a 400 validation error.
record error-403-invalid-picklist-key 403 "$JANE" POST "$SR_API" \
	'{"title": "Bad", "category": {"key": "nope"}, "requestStatus": {"key": "open"}}' >/dev/null
record error-401-invalid-bearer-token 401 bearer-invalid GET "$USER_API/my-user-account" >/dev/null
record error-403-update-other-user 403 "$JOHN" PATCH "$USER_API/user-accounts/$jane_id" '{"jobTitle": "Hacker"}' >/dev/null
record error-404-other-users-request 404 "$JOHN" GET "$SR_API/$sr_id" >/dev/null

# --- OAuth 2 token endpoint errors (no browser needed) ----------------------------------------------

client_id="${OAUTH_CLIENT_ID:-}"
if [[ -n "$client_id" ]]; then
	for grant in authorization_code refresh_token; do
		response=$(curl -sS -w '\n%{http_code}' "$LIFERAY_URL/o/oauth2/token" \
			--data-urlencode "grant_type=$grant" --data-urlencode "client_id=$client_id" \
			--data-urlencode "code=invalid" --data-urlencode "refresh_token=invalid" \
			--data-urlencode "redirect_uri=com.liferay.sample.selfservice://oauth2redirect" \
			--data-urlencode "code_verifier=$(printf 'x%.0s' {1..43})")
		jq . <<<"${response%$'\n'*}" >"$OUT/oauth-token-error-invalid-$grant.json"
		echo "| \`oauth-token-error-invalid-$grant.json\` | \`POST /o/oauth2/token\` (grant_type=$grant) | ${response##*$'\n'} | - |" >>"$INDEX"
		echo "  oauth-token-error-invalid-$grant (${response##*$'\n'})" >&2
	done
else
	echo "  (skipping OAuth token errors: set OAUTH_CLIENT_ID to record them)" >&2
fi

{
	echo "# Liferay API fixtures"
	echo
	echo "Real responses from Liferay DXP \`${LIFERAY_DXP_TAG:-2026.q1.14-lts}\` (Docker image tag),"
	echo "recorded by [\`liferay/scripts/record-fixtures.sh\`](../../../../../liferay/scripts/record-fixtures.sh)."
	echo "Do not edit by hand: re-record instead. Ids, dates and URLs come from a throwaway local instance."
	echo
	echo "| File | Request | Status | As |"
	echo "|---|---|---|---|"
	cat "$INDEX"
	if [[ -f "$OUT/oauth-token-response.json" ]]; then
		echo "| \`oauth-token-response.json\` | \`POST /o/oauth2/token\` (grant_type=authorization_code, PKCE) | 200 | jane.doe |"
		echo "| \`oauth-refresh-response.json\` | \`POST /o/oauth2/token\` (grant_type=refresh_token) | 200 | jane.doe |"
		echo
		echo "The two successful token responses need a browser sign-in, so they are captured separately with"
		echo "\`liferay/scripts/oauth-pkce-test.sh\`. Token values are replaced with \`REDACTED-<length>-chars\`"
		echo "(the originals were ~1 KB access tokens and 61-character refresh tokens)."
	fi
} >"$OUT/README.md"
rm -f "$INDEX"

echo "Done: $(ls "$OUT"/*.json | wc -l) fixtures." >&2
