#!/usr/bin/env bash
#
# Verifies, as the self-service users (not the admin), every API call the iOS app relies on:
#
#   - System object: read and update my profile; create, read, update and delete my postal address
#   - Custom object: create, read, update and delete a Service Request
#   - Isolation: John cannot see or change Jane's Service Request
#
# Uses HTTP Basic auth only to keep the script short; the app uses OAuth 2 (see oauth-pkce-test.sh).
#
# Requires: bash, curl, jq

set -euo pipefail

LIFERAY_URL="${LIFERAY_URL:-http://localhost:8080}"
TUTORIAL_USER_PASSWORD="${TUTORIAL_USER_PASSWORD:-Tutorial-2026!}"
JANE="jane.doe@example.com"
JOHN="john.roe@example.com"
USER_API="/o/headless-admin-user/v1.0"
SR_API="/o/c/servicerequests"

failures=0
pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; failures=$((failures + 1)); }

# call USER METHOD PATH [JSON_BODY] -> sets $STATUS and $BODY
call() {
	local user="$1" method="$2" path="$3" body="${4:-}" args response
	args=(-sS -w '\n%{http_code}' -u "$user:$TUTORIAL_USER_PASSWORD" -X "$method" -H 'Accept: application/json')
	[[ -n "$body" ]] && args+=(-H 'Content-Type: application/json' --data-binary "$body")
	response=$(curl "${args[@]}" "$LIFERAY_URL$path")
	STATUS="${response##*$'\n'}"
	BODY="${response%$'\n'*}"
}

expect() { # expect EXPECTED_STATUS DESCRIPTION
	if [[ "$STATUS" == "$1" ]]; then pass "$2 (HTTP $STATUS)"; else fail "$2 (expected HTTP $1, got $STATUS) $BODY"; fi
}

echo "System object: User profile (as Jane)"
call "$JANE" GET "$USER_API/my-user-account"
expect 200 "GET my-user-account"
jane_id=$(jq -r '.id' <<<"$BODY")

call "$JANE" PATCH "$USER_API/user-accounts/$jane_id" '{"jobTitle": "Smoke Tester"}'
expect 200 "PATCH own user account (jobTitle)"
if [[ "$(jq -r '.jobTitle' <<<"$BODY")" == "Smoke Tester" ]]; then pass "jobTitle updated"; else fail "jobTitle not updated"; fi
call "$JANE" PATCH "$USER_API/user-accounts/$jane_id" '{"jobTitle": "Customer"}'

echo "System object: Postal addresses (as Jane)"
call "$JANE" GET "$USER_API/user-accounts/$jane_id/postal-addresses"
expect 200 "GET own postal addresses"
existing=$(jq -c '[.items[] | {id}]' <<<"$BODY")

# There is no POST for user addresses in 2026.Q1: create one by PATCHing the user account with the
# full address list (existing ids + the new address). Addresses left out of the list are removed.
new_address='{"addressCountry": "United States", "addressLocality": "Diamond Bar", "addressRegion": "California",
  "addressType": "personal", "postalCode": "91765", "primary": false, "streetAddressLine1": "1400 Montefino Ave"}'
call "$JANE" PATCH "$USER_API/user-accounts/$jane_id" "$(jq -n --argjson existing "$existing" --argjson new "$new_address" \
	'{userAccountContactInformation: {postalAddresses: ($existing + [$new])}}')"
expect 200 "Create postal address via PATCH user account"

call "$JANE" GET "$USER_API/user-accounts/$jane_id/postal-addresses"
address_id=$(jq -r '[.items[] | select(.postalCode == "91765")][0].id // empty' <<<"$BODY")
if [[ -n "$address_id" ]]; then pass "New address listed (id=$address_id)"; else fail "New address not found"; fi

if [[ -n "$address_id" ]]; then
	call "$JANE" PATCH "$USER_API/postal-addresses/$address_id" '{"addressLocality": "Walnut"}'
	expect 200 "PATCH postal address"

	call "$JANE" GET "$USER_API/postal-addresses/$address_id"
	expect 200 "GET postal address"

	call "$JANE" DELETE "$USER_API/postal-addresses/$address_id"
	expect 204 "DELETE postal address"
fi

call "$JANE" GET "/o/headless-admin-address/v1.0/countries?pageSize=5"
expect 200 "GET countries (for the address form)"

echo "Custom object: Service Request (as Jane)"
call "$JANE" POST "$SR_API" '{"title": "Smoke test request", "description": "Created by smoke-test.sh",
  "category": {"key": "technical"}, "requestStatus": {"key": "open"}, "priority": 2, "dueDate": "2026-12-31"}'
expect 200 "POST service request"
sr_id=$(jq -r '.id // empty' <<<"$BODY")
jq -c '{id, title, category, requestStatus, creator: .creator.name}' <<<"$BODY" 2>/dev/null || true

call "$JANE" GET "$SR_API?sort=dateCreated:desc&filter=requestStatus%20eq%20'open'&pageSize=5"
expect 200 "GET service requests (filter + sort)"
if jq -e --argjson id "${sr_id:-0}" '[.items[].id] | index($id) != null' <<<"$BODY" >/dev/null; then pass "Jane sees her request in the list"; else fail "Jane's request missing from list"; fi

call "$JANE" PATCH "$SR_API/$sr_id" '{"requestStatus": {"key": "inProgress"}}'
expect 200 "PATCH service request status"

echo "Isolation (as John)"
call "$JOHN" GET "$SR_API?pageSize=50"
expect 200 "GET service requests as John"
if jq -e --argjson id "${sr_id:-0}" '[.items[].id] | index($id) == null' <<<"$BODY" >/dev/null; then pass "John does not see Jane's request in the list"; else fail "John can see Jane's request"; fi

call "$JOHN" GET "$SR_API/$sr_id"
if [[ "$STATUS" == "403" || "$STATUS" == "404" ]]; then pass "John cannot read Jane's request (HTTP $STATUS)"; else fail "John read Jane's request (HTTP $STATUS)"; fi

call "$JOHN" DELETE "$SR_API/$sr_id"
if [[ "$STATUS" == "403" || "$STATUS" == "404" ]]; then pass "John cannot delete Jane's request (HTTP $STATUS)"; else fail "John deleted Jane's request (HTTP $STATUS)"; fi

echo "Cleanup (as Jane)"
call "$JANE" DELETE "$SR_API/$sr_id"
expect 204 "DELETE service request"

echo
if (( failures == 0 )); then echo "All checks passed."; else echo "$failures check(s) failed."; exit 1; fi
