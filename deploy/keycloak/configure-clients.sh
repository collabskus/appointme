#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# Configure the realm's OIDC clients for this deployment.
#
# THE PROBLEM THIS SOLVES
# Keycloak refuses any `redirect_uri` that a client hasn't explicitly allow-
# listed — that allow-list is the entire point of the redirect-URI check (it
# stops an attacker from bouncing a victim's authorization code to a site they
# control). The realm export (appointme-realm.json) ships with localhost URLs,
# which are right for local development but wrong for a server reachable at,
# say, https://app.example.com. Rather than fork the 86 KB realm file for every
# deployment, we add the public URL here, once, right after import.
#
# Two clients need it:
#   • appointme-frontend → used by the API's OIDC login redirect
#       (browser → Keycloak → back to APP_PUBLIC_URL/signin-oidc)
#   • appointme-api      → used as the client for the "verify email / set
#       password" link, whose redirect lands on APP_PUBLIC_URL/auth/login
#
# It ALSO sets the appointme-api client secret to $KC_API_CLIENT_SECRET (when
# provided), so the value in deploy/.env is authoritative and can be rotated
# without ever editing the realm export. (appointme-frontend is a PUBLIC
# client — it has no secret to set.)
#
# This script is idempotent: it SETS the full desired state every time, so
# re-running it (every `up`) just reasserts the same state.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

KCADM=/opt/keycloak/bin/kcadm.sh
SERVER=http://keycloak:8080      # internal address on the Podman network
REALM=appointme

# Optional: when set, applied as the appointme-api client secret.
KC_API_CLIENT_SECRET="${KC_API_CLIENT_SECRET:-}"

echo "keycloak-config: waiting for Keycloak to accept admin logins..."
# Keycloak takes a little while to import the realm and open its admin API.
# Poll until login succeeds rather than depending on healthcheck timing.
until "$KCADM" config credentials \
        --server "$SERVER" --realm master \
        --user "$KC_ADMIN_USER" --password "$KC_ADMIN_PASSWORD" >/dev/null 2>&1; do
  sleep 3
done
echo "keycloak-config: connected."

# Look up a client's internal UUID by its clientId. Prints nothing if absent.
client_uuid() {
  "$KCADM" get clients -r "$REALM" -q "clientId=$1" \
      --fields id --format csv --noquotes | tr -d '\r\n'
}

configure_redirects() {
  local client_id="$1"
  local uuid
  uuid="$(client_uuid "$client_id")"

  if [ -z "$uuid" ]; then
    echo "keycloak-config: WARNING — client '$client_id' not found, skipping."
    return
  fi

  "$KCADM" update "clients/$uuid" -r "$REALM" \
    -s "redirectUris=[\"https://localhost:5173/*\",\"${APP_PUBLIC_URL}/*\"]" \
    -s "webOrigins=[\"https://localhost:5173\",\"${APP_PUBLIC_URL}\"]"

  echo "keycloak-config: '$client_id' now accepts redirects to ${APP_PUBLIC_URL}"
}

set_api_client_secret() {
  local client_id="appointme-api"

  if [ -z "$KC_API_CLIENT_SECRET" ]; then
    echo "keycloak-config: KC_API_CLIENT_SECRET not set — leaving the realm's baked-in secret."
    return
  fi

  local uuid
  uuid="$(client_uuid "$client_id")"

  if [ -z "$uuid" ]; then
    echo "keycloak-config: WARNING — client '$client_id' not found, cannot set secret."
    return
  fi

  "$KCADM" update "clients/$uuid" -r "$REALM" -s "secret=${KC_API_CLIENT_SECRET}"
  echo "keycloak-config: '$client_id' secret set from environment."
}

configure_redirects appointme-frontend
configure_redirects appointme-api
set_api_client_secret

echo "keycloak-config: done."
