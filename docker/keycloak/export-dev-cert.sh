#!/usr/bin/env bash
# Exports the trusted ASP.NET Core HTTPS dev certificate as PEM for the
# Keycloak container to serve on https://localhost:8082 when running the
# backing services via the repo-root compose file. Run once before `up`.
set -euo pipefail

# Resolve the repo root regardless of where this script is invoked from.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cert_dir="${script_dir}/certs"

mkdir -p "${cert_dir}"

# Ensure the dev cert exists and is trusted by the OS (and browser).
dotnet dev-certs https --trust

# PEM export produces keycloak.crt + keycloak.key (key unencrypted via --no-password).
dotnet dev-certs https --format PEM --no-password -ep "${cert_dir}/keycloak.crt"

# The key is written 0600, but inside the container Keycloak runs as uid 1000 —
# and under ROOTLESS Podman that maps to one of your subuids, which cannot read
# a host file that only your own user can read. This is a localhost-only dev
# certificate, so opening it up is fine. (SELinux access is handled separately,
# by the `:Z` label on the bind mount in compose.yaml.)
chmod 0644 "${cert_dir}/keycloak.crt" "${cert_dir}/keycloak.key"

echo "Exported dev certificate to ${cert_dir}/keycloak.crt and keycloak.key"
