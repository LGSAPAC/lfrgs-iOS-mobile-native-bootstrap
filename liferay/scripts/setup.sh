#!/usr/bin/env bash
#
# Configures a local Liferay DXP 2026.Q1 instance for the iOS tutorial.
# Safe to run repeatedly: every step is an upsert keyed by external reference code.
#
#   1. Picklists:      Service Request Category / Status
#   2. Custom object:  Service Request (published, company scoped)
#   3. Permission:     "User" role may add Service Request entries
#   4. Users:          jane.doe@example.com and john.roe@example.com (default "User" role only)
#
# Uses the admin account with HTTP Basic auth. That is fine for local setup scripts; the
# iOS app itself never uses Basic auth or admin credentials.
#
# Requires: bash, curl, jq

set -euo pipefail
# Make "set -e" apply inside $(...) too, so a failed request stops the script.
shopt -s inherit_errexit 2>/dev/null || true  # Bash 4.4+; macOS ships Bash 3.2

# Never wait forever on a request: a Liferay that accepts connections but doesn't answer yet would
# otherwise hang the script (and CI) indefinitely. CURL_MAX_TIME overrides the per-request limit.
# Setup writes (creating and publishing the object) can take minutes on a freshly started Liferay.
CURL_MAX_TIME="${CURL_MAX_TIME:-600}"
curl() { command curl --connect-timeout 10 --max-time "$CURL_MAX_TIME" "$@"; }

LIFERAY_URL="${LIFERAY_URL:-http://localhost:8080}"
ADMIN_USER="${ADMIN_USER:-test@liferay.com}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-test}"
TUTORIAL_USER_PASSWORD="${TUTORIAL_USER_PASSWORD:-Tutorial-2026!}"
WAIT_MINUTES="${WAIT_MINUTES:-10}"

SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../setup" && pwd)"

for tool in curl jq; do
	command -v "$tool" >/dev/null || { echo "error: '$tool' is required" >&2; exit 1; }
done

log() { printf '\n==> %s\n' "$*"; }

# api METHOD PATH [JSON_BODY] -> prints the response body; exits on HTTP >= 400.
api() {
	local method="$1" path="$2" body="${3:-}" response status

	local args=(-sS -w '\n%{http_code}' -u "$ADMIN_USER:$ADMIN_PASSWORD" -X "$method" -H 'Accept: application/json')
	[[ -n "$body" ]] && args+=(-H 'Content-Type: application/json' --data-binary "$body")

	if ! response=$(curl "${args[@]}" "$LIFERAY_URL$path"); then
		echo "error: $method $path: no response within ${CURL_MAX_TIME}s (is Liferay overloaded or still starting?)" >&2
		exit 1
	fi

	status="${response##*$'\n'}"
	response="${response%$'\n'*}"

	if (( status >= 400 )); then
		echo "error: $method $path -> HTTP $status" >&2
		echo "$response" >&2
		exit 1
	fi

	printf '%s' "$response"
}

wait_for_liferay() {
	log "Waiting for Liferay at $LIFERAY_URL (first start can take several minutes)"

	local deadline=$((SECONDS + WAIT_MINUTES * 60)) next_report=$((SECONDS + 60))
	while (( SECONDS < deadline )); do
		# -s: the expected "connection refused/timed out" while starting isn't worth printing.
		if curl -fs -o /dev/null --max-time 15 -u "$ADMIN_USER:$ADMIN_PASSWORD" \
			"$LIFERAY_URL/o/headless-admin-user/v1.0/my-user-account"; then
			echo "Liferay is up after $((SECONDS / 60))m $((SECONDS % 60))s."
			return
		fi
		if (( SECONDS >= next_report )); then
			echo "  still waiting ($((SECONDS / 60)) min)…"
			next_report=$((next_report + 60))
		fi
		sleep 5
	done

	echo "error: Liferay did not become ready in $WAIT_MINUTES minutes" >&2
	exit 1
}

upsert_picklists() {
	log "Upserting picklists"

	local count i definition erc
	count=$(jq 'length' "$SETUP_DIR/picklists.json")

	for (( i = 0; i < count; i++ )); do
		definition=$(jq -c ".[$i]" "$SETUP_DIR/picklists.json")
		erc=$(jq -r '.externalReferenceCode' <<<"$definition")

		api PUT "/o/headless-admin-list-type/v1.0/list-type-definitions/by-external-reference-code/$erc" \
			"$definition" | jq -r '"  \(.externalReferenceCode): \([.listTypeEntries[].key] | join(", "))"'
	done
}

upsert_object() {
	log "Upserting the Service Request object" >&2

	local definition erc result id status_code

	definition=$(cat "$SETUP_DIR/service-request-object.json")
	erc=$(jq -r '.externalReferenceCode' <<<"$definition")

	result=$(api PUT "/o/object-admin/v1.0/object-definitions/by-external-reference-code/$erc" "$definition")
	id=$(jq -r '.id' <<<"$result")
	status_code=$(jq -r '.status.code' <<<"$result")

	if [[ "$status_code" != "0" ]]; then
		echo "  publishing object definition $id" >&2
		result=$(api POST "/o/object-admin/v1.0/object-definitions/$id/publish")
	fi

	jq -r '"  id=\(.id) status=\(.status.label) REST=\(.restContextPath)"' <<<"$result" >&2

	printf '%s' "$id"
}

grant_add_entry_permission() {
	local object_definition_id="$1" company_id role_id

	log "Granting the 'User' role permission to add Service Requests"

	company_id=$(api GET "/o/headless-portal-instances/v1.0/portal-instances" |
		jq -r '[.items[] | select(.virtualHost == "localhost")][0].companyId // .items[0].companyId')

	role_id=$(api GET "/o/headless-admin-user/v1.0/roles?pageSize=-1" |
		jq -r '.items[] | select(.name == "User" and .roleType == "regular") | .id')

	# PATCH adds these permissions to the role; it does not remove existing ones.
	api PATCH "/o/headless-admin-user/v1.0/roles/$role_id" "$(jq -n \
		--arg resource "com.liferay.object#$object_definition_id" \
		--argjson companyId "$company_id" \
		'{rolePermissions: [{actionIds: ["ADD_OBJECT_ENTRY"], primaryKey: $companyId, resourceName: $resource, scope: 1}]}')" \
		>/dev/null

	echo "  role=$role_id resource=com.liferay.object#$object_definition_id action=ADD_OBJECT_ENTRY"
}

upsert_user() {
	local erc="$1" screen_name="$2" given="$3" family="$4" email="$5" path body

	path="/o/headless-admin-user/v1.0/user-accounts/by-external-reference-code/$erc"
	body=$(jq -n --arg erc "$erc" --arg screen "$screen_name" --arg given "$given" --arg family "$family" \
		--arg email "$email" \
		'{externalReferenceCode: $erc, alternateName: $screen, givenName: $given, familyName: $family,
		  emailAddress: $email, jobTitle: "Customer"}')

	# Set the password only when creating the user: Liferay rejects re-setting the current password.
	if [[ "$(curl -s -o /dev/null -w '%{http_code}' -u "$ADMIN_USER:$ADMIN_PASSWORD" "$LIFERAY_URL$path")" == "404" ]]; then
		body=$(jq --arg password "$TUTORIAL_USER_PASSWORD" '. + {password: $password}' <<<"$body")
	fi

	api PUT "$path" "$body" | jq -r '"  \(.emailAddress) (id=\(.id))"'
}

upsert_users() {
	log "Upserting tutorial users (password: \$TUTORIAL_USER_PASSWORD)"

	upsert_user TUTORIAL_USER_JANE jane.doe Jane Doe jane.doe@example.com
	upsert_user TUTORIAL_USER_JOHN john.roe John Roe john.roe@example.com
}

wait_for_liferay
upsert_picklists
object_definition_id=$(upsert_object)
grant_add_entry_permission "$object_definition_id"
upsert_users

log "Done. Next: create the OAuth 2 application (docs/tutorial/02-configure-liferay.md, step 4)."
