#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# Register this deployment's public URL as a valid OIDC redirect target.
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
# This script is idempotent: it SETS the full desired list every time, so
# re-running it (every `up`) just reasserts the same state.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

KCADM=/opt/keycloak/bin/kcadm.sh
SERVER=http://keycloak:8080      # internal address on the Podman network
REALM=appointme

echo "keycloak-config: waiting for Keycloak to accept admin logins..."
# Keycloak takes a little while to import the realm and open its admin API.
# Poll until login succeeds rather than depending on healthcheck timing.
until "$KCADM" config credentials \
        --server "$SERVER" --realm master \
        --user "$KC_ADMIN_USER" --password "$KC_ADMIN_PASSWORD" >/dev/null 2>&1; do
  sleep 3
done
echo "keycloak-config: connected."

configure_client() {
  local client_id="$1"
  local uuid
  uuid="$("$KCADM" get clients -r "$REALM" -q "clientId=$client_id" \
            --fields id --format csv --noquotes | tr -d '\r\n')"

  if [ -z "$uuid" ]; then
    echo "keycloak-config: WARNING — client '$client_id' not found, skipping."
    return
  fi

  "$KCADM" update "clients/$uuid" -r "$REALM" \
    -s "redirectUris=[\"https://localhost:5173/*\",\"${APP_PUBLIC_URL}/*\"]" \
    -s "webOrigins=[\"https://localhost:5173\",\"${APP_PUBLIC_URL}\"]"

  echo "keycloak-config: '$client_id' now accepts redirects to ${APP_PUBLIC_URL}"
}

configure_client appointme-frontend
configure_client appointme-api

echo "keycloak-config: done."
