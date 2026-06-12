# Podman / Fedora readiness — review changes

A full review of the repository against its own documentation (README "Deploy
on a Fedora server", CLAUDE.md) found the container deployment in a
half-refactored state: the deploy stack's files referenced a `deploy/`
directory that did not exist, the deployment compose file had overwritten the
local-development compose file at the repo root, and the deployment's
`.env.example` was sitting in the frontend folder. This change set restores
the intended layout, fixes the Podman/Fedora-specific issues found along the
way, and closes one security hole.

## Restored repository layout

| File | What happened |
|---|---|
| `deploy/compose.yaml` | **Moved here from the repo root.** Its build contexts (`context: ..`), its `dockerfile: deploy/keycloak/Containerfile` reference, and its own header comment all assumed it lived in `deploy/`. It now does, so every path inside it is true. |
| `deploy/.env.example` | **Moved here from `src/AppointMe.Frontend/env.example`**, where it was misplaced (its header literally says "Read deploy/compose.yaml"). README step 2 (`cd deploy && cp .env.example .env`) now works. |
| `deploy/keycloak/Containerfile` | **Moved here from `docker/keycloak/`.** It COPYs `deploy/keycloak/configure-clients.sh` and documents the repo-root build context — both statements are now accurate. |
| `deploy/keycloak/configure-clients.sh` | **Moved here from `docker/keycloak/`** (see also "Functional changes" below). |
| `compose.yaml` (repo root) | **Recreated as the local-dev backing-services file** the README's "Option B" describes: SQL Server on `localhost,60740` (sa / Password1), Keycloak on `https://localhost:8082` (admin / admin, dev cert, realm imported), Mailpit UI on `:8026` / SMTP on `:1026` — mirroring the Aspire host and `appsettings.Development.json` exactly. |
| `docker/keycloak/` | Now contains only the **dev-cert assets** (`export-dev-cert.sh`, `certs/`), which is all the dev compose needs from it. |

## Podman / Fedora fixes

- **`src/AppointMe.Api/Dockerfile`** — `FROM node:22-alpine` is now fully
  qualified as `docker.io/library/node:22-alpine`. Podman on Fedora enforces
  short-name resolution; an unqualified name can fail (or try to prompt) in a
  non-interactive `podman-compose build`. The BuildKit `# syntax=` pin was
  removed — the file is plain multi-stage Dockerfile syntax that Buildah and
  BuildKit build identically (the GitHub Actions image build is unaffected).
- **Root `compose.yaml` SELinux labels** — the two bind mounts the dev stack
  needs (the dev TLS cert directory and the realm export) carry `:Z` so
  SELinux on Fedora permits the container to read them. The deploy stack still
  has zero bind mounts by design.
- **`docker/keycloak/export-dev-cert.sh`** — now `chmod 0644`s the exported
  key. `dotnet dev-certs` writes it `0600`, which the in-container Keycloak
  user (uid 1000 — under rootless Podman, one of your subuids) cannot read.
  It is a localhost-only development certificate.
- **`deploy/compose.yaml` restart policies** — long-running services changed
  from `unless-stopped` to `always`, because Podman's boot-time
  `podman-restart.service` only restarts containers whose policy is exactly
  `always`. The README's deploy section gained a "Surviving a reboot"
  subsection (rootful unit, or rootless unit + `loginctl enable-linger`).
  Session behaviour is unchanged: `down`/`stop` still keeps containers down.
- **Mailpit image pinned to an explicit tag** (`docker.io/axllent/mailpit:latest`)
  rather than an implicit one.

## Functional fixes

- **Data Protection keys now persist** (`deploy/compose.yaml`): a new `dp-keys`
  named volume is mounted at `/home/app/.aspnet/DataProtection-Keys:U`. These
  keys encrypt the auth cookie and the OIDC state/correlation cookies; without
  persistence, every rebuild/re-create rotated them — logging all users out
  and failing any login that was mid-flight with a correlation error.
- **`deploy/keycloak/configure-clients.sh` now also sets the `appointme-api`
  client secret** from `KC_API_CLIENT_SECRET`. Previously the value in `.env`
  had to match the secret baked into the realm export; now `.env` is
  authoritative and the secret can be rotated without touching the realm file.
  (`appointme-frontend` is a public client — no secret exists to set; the
  `KC_FRONTEND_CLIENT_SECRET` variable remains only because the API's options
  validation requires a non-empty string.) `deploy/.env.example` documents
  both points.

## Security fix

- **Hangfire dashboard was unauthenticated.** `/admin/jobs` was configured
  with an empty authorization filter list — and the Podman deployment publishes
  the API to the internet through the Cloudflare Tunnel, so the job dashboard
  (trigger/delete jobs) was world-reachable. New
  `src/AppointMe.Api/Hangfire/AuthenticatedUserDashboardFilter.cs` requires an
  authenticated user; `HangfireExtensions.cs` applies it. Log in to the app
  first, then open the dashboard.

## Documentation fixes

- `README.md`: broken `docs/ARCHITECTURE.md` link → `ARCHITECTURE.md`
  (the file lives at the repo root); "Option B" uses the export script and
  notes `podman compose` / `docker compose` / `podman-compose` parity; new
  "Surviving a reboot" subsection; note that the job dashboard requires login.
- `CLAUDE.md`: dev-setup commands updated to use the export script.

## Verified in this review

- Both compose files parse; every `${VAR}` in `deploy/compose.yaml` is defined
  in `deploy/.env.example` (and vice versa); the `$$` healthcheck escapes are
  intact; both shell scripts pass `bash -n`.
- The frontend production build was run for real with Node 22 + Yarn 1.22
  (the exact Dockerfile stage-1 toolchain): `yarn install --frozen-lockfile`
  and `yarn build` both succeed, and the emitted `dist/index.html` uses
  root-absolute `/assets/...` paths — correct for `UseStaticFiles()` +
  `MapFallbackToFile("index.html")` from `wwwroot`.
- The realm export was inspected: clients, redirect URIs, the public/confidential
  split, and the SMTP host `Mailpit` (matched by a network alias in both
  compose files).
- No stale references to the moved files remain anywhere in the repo.

## Known limitations (unchanged, by design)

- The .NET build stages could not be executed in this review environment
  (no .NET 10 SDK available); they were verified by inspection against
  `Program.cs`, the Wolverine codegen flow (`appsettings.Codegen.json`,
  `CodeGenerationDetection`, static `TypeLoadMode` outside Development), and
  `global.json`.
- Keycloak runs `start-dev` with H2 storage and the SQL `sa` account is used
  by the app — both acceptable for this sandbox and called out in the README,
  not production posture.
- The SQL Server image is x86-only (README already notes the ARM caveat).
