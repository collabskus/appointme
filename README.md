# AppointMe

A personal **learning sandbox** — a multi-tenant appointment-booking app I use to
explore advanced .NET and React patterns end to end. It's a modular monolith
(.NET 10 + React 19) with the genuinely hard parts wired up: multi-tenancy,
hybrid authentication, a permission engine, CQRS with domain events, durable
messaging, and a typed frontend generated from the backend's OpenAPI contract.

## What this is (and isn't)

This repo is **public so it's easy to read and learn from**, but it's a personal
project, not a product or a starter template:

- **Not a template.** There's no "clone-and-build-your-startup" intent. It's where
  I try ideas — some patterns here are deliberately more elaborate than a real
  product would need, because the point is to learn them.
- **No support, no roadmap, no contribution process.** Issues and PRs aren't being
  solicited. Read it, borrow from it, fork it — all fine (it's MIT) — but I'm
  building it for myself.
- **It may break or change shape without notice.** `main` is my working branch.

If you landed here looking for production-grade reference patterns, plenty of them
are here and they work — just treat them as study material, not a supported library.

## What's inside

- **Modular monolith** — `Identity`, `Organizations`, `CRM`, and `Booking`, each a
  bounded context with its own `DbContext` and database schema, organized by
  vertical slice (one folder per use case: command, handler, endpoint, request).
- **Hybrid authentication** — Keycloak (OIDC) locally, with JWT Bearer for API
  calls and cookies for browser flows. Sign-up, email verification, and password
  reset are handled by the app, not by hitting Keycloak directly. An **Entra
  External ID** path is also wired in as the cloud-identity option.
- **Multi-tenancy** — company resolved from the `X-Company-Id` header, enforced two
  ways: EF Core query filters at the data layer (tenant isolation *fails closed* —
  no company context means no rows), and a handler guard that rejects work with no
  active company.
- **CQRS + DDD** — writes go through EF Core aggregates that raise domain events;
  reads go through Dapper. Async messaging runs on **Wolverine**, which publishes
  domain events out of the EF change tracker. Locally the transport is a **durable
  SQL Server queue** (no external broker); **Azure Service Bus** is available as an
  opt-in transport for cloud.
- **Permission engine** — permissions are auto-discovered by assembly scanning.
  Effective permissions are computed from per-role default grants plus per-company
  overrides, with conflicts arbitrated by a pluggable voting policy
  (`DenyWins` / `GrantWins`).
- **Background jobs** — Hangfire runs the recurring reconciliation jobs that keep
  each module's local projections in sync with the others.
- **Typed frontend** — React 19 + Vite + Tailwind 4, with TanStack Query hooks and
  TypeScript types generated directly from the backend OpenAPI spec via **orval**.
- **One-command local stack** — .NET Aspire orchestrates SQL Server, Keycloak,
  Mailpit, the API, and the frontend, applying EF migrations and seeding demo data
  automatically. A matching `compose.yaml` runs the same backing services if you'd
  rather launch the API and frontend yourself.

## Quick start

Goal: clone the repo and have AppointMe running locally — backend, frontend,
database, auth, and mail.

You choose how the backing services (SQL Server, Keycloak, Mailpit) run:

- **Option A — .NET Aspire** *(recommended)*: one command starts everything,
  including the API and frontend.
- **Option B — Docker Compose**: brings up only the backing services on the same
  ports; you run the API and frontend yourself.

Both produce an identical running app — same images, ports, credentials, and
seeded data. Do the [prerequisites](#prerequisites) once, then follow either option.

### Prerequisites

| Requirement | Why | Notes |
|---|---|---|
| [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0) | Builds and runs the API and the Aspire host | `dotnet --version` should report `10.x` |
| [Docker](https://www.docker.com/products/docker-desktop/) (running) | Hosts SQL Server, Keycloak, and Mailpit containers | Docker Desktop or any OCI-compatible runtime |
| [Node.js 22+](https://nodejs.org/) & [Yarn](https://yarnpkg.com/) | Builds and serves the React frontend | `corepack enable` gives you Yarn |
| HTTPS dev certificate | Frontend and services run over HTTPS | `dotnet dev-certs https --trust` |

> First run pulls container images and restores NuGet/Yarn packages, so it takes a
> few minutes. Subsequent runs are fast — the SQL Server, Keycloak, and Mailpit
> containers are persistent and reused across restarts.

### Clone and trust the dev cert

Both options start here:

```bash
git clone https://github.com/collabskus/appointme.git
cd appointme

# One-time: trust the local HTTPS dev cert (used by the API, frontend, and Keycloak)
dotnet dev-certs https --trust
```

### Option A — .NET Aspire

```bash
# Start the whole stack — backing services, API, and frontend
cd src/AppointMe.Aspire
dotnet run
```

**Prefer an IDE?** Open `AppointMe.sln` in Visual Studio or Rider, set
**`AppointMe.Aspire`** as the startup project, and press **F5**.

Either way, the [.NET Aspire dashboard](https://learn.microsoft.com/dotnet/aspire/fundamentals/dashboard/overview)
opens automatically. Wait for every resource to turn **Running** (green) — the API
waits for SQL Server and Keycloak to be healthy before it starts.

What happens on startup, with no action from you:

- SQL Server, Keycloak, and Mailpit containers come up.
- The `appointme` Keycloak realm (clients, roles, mappers) is imported.
- EF Core migrations are applied to every module's schema.
- Demo customers and appointments are seeded (Development only).
- The API starts, then the Vite frontend.

### Option B — Docker Compose

Compose runs only the backing services (SQL Server, Keycloak, Mailpit) — on the
same ports, images, and credentials as Aspire. You run the API and frontend
yourself.

```bash
# 1. One-time: export the trusted dev cert that Keycloak serves on https://localhost:8082
./docker/keycloak/export-dev-cert.sh
#    (Windows / no bash — run the command the script wraps:)
#    dotnet dev-certs https --format PEM --no-password -ep docker/keycloak/certs/keycloak.crt

# 2. Start the backing services and wait for them to report healthy
docker compose up -d
docker compose ps          # SQL Server and Keycloak should show "healthy"

# 3. Run the API (applies migrations + seeds demo data on first start)
dotnet run --project src/AppointMe.Api

# 4. In a second terminal, run the frontend
cd src/AppointMe.Frontend
yarn install
yarn dev
```

Then open **https://localhost:5173**. To stop the services, `docker compose stop`
(keeps data) or `docker compose down` (removes the containers; SQL Server and
Keycloak data survive in named volumes — add `-v` to wipe them too).

EF Core migrations and demo-data seeding happen when **you** start the API in
step 3 (same as Aspire — the API does this on startup, not Compose).

### Where everything lives

| Service | URL | Credentials |
|---|---|---|
| **Frontend (the app)** | https://localhost:5173 | sign up — see below |
| Aspire dashboard | shown in the console at startup | — |
| Keycloak admin console | https://localhost:8082 | `admin` / `admin` |
| Mailpit (catches all outgoing email) | http://localhost:8026 | — |
| API OpenAPI document | https://localhost:7233/openapi/v1.json | — |
| SQL Server | `localhost:60740` | `sa` / `Password1` |

> **About these credentials.** Every secret used in local development — the SQL `sa`
> password, the Keycloak `admin` account, and the Keycloak client secrets in
> `appsettings.Development.json` and `appointme-realm.json` — is a throwaway default.
> It only protects containers running on your machine, and it's committed on purpose
> so the stack runs with zero setup. These are safe in a public repo, but **never
> reuse them anywhere real**. Any cloud secrets live in Azure Key Vault and are
> injected at deploy time (see [`infra/`](./infra)). A `gitleaks` workflow scans
> every push/PR to catch any *real* secret that slips in.

### Create your first account

The app manages its own sign-up — you don't register through Keycloak directly.

1. Open **https://localhost:5173** and go to **Sign up** (`/auth/signup`).
2. Submit the form. AppointMe provisions your user in Keycloak and sends a
   verification email.
3. Open **Mailpit at http://localhost:8026**, find the verification email, and click
   the link. (No real mail is sent — Mailpit catches everything locally.)
4. Log in with your new credentials.
5. Complete **onboarding** to create your company. You now have a working,
   multi-tenant AppointMe instance with demo data to explore.

## Project layout

```
src/
├── AppointMe.Aspire/        # .NET Aspire orchestrator — the F5 entry point for local dev
├── AppointMe.Api/           # ASP.NET Core API host (endpoints auto-discovered)
├── AppointMe.Shared/        # Shared domain abstractions, value objects, infrastructure
├── Identity/                # Authentication & user provisioning (Keycloak / Entra External ID)
├── Organizations/           # Companies, employees, invitations, onboarding, permissions
├── CRM/                     # Customer management
├── Booking/                 # Appointments, attendees, service providers, scheduling
└── AppointMe.Frontend/      # React + Vite + TypeScript SPA
```

The codebase follows Domain-Driven Design with **vertical slice architecture** —
each use case owns its command, handler, endpoint, and request/response in a single
folder. For the full architecture guide, conventions, and patterns, see
[`CLAUDE.md`](./CLAUDE.md).

## Common commands

```bash
# Full stack (recommended) — from src/AppointMe.Aspire
dotnet run

# Backing services only, without Aspire (see Quick start → Option B)
docker compose up -d        # start SQL Server, Keycloak, Mailpit
docker compose ps           # check health
docker compose down         # stop and remove containers (data volumes persist)

# Backend only
dotnet build AppointMe.sln
dotnet run --project src/AppointMe.Api

# Tests (all unit tests — domain rules + the permission engine)
dotnet test
dotnet test --filter "FullyQualifiedName~TestName"   # a single test

# Frontend — from src/AppointMe.Frontend
yarn install
yarn dev            # dev server on https://localhost:5173
yarn build          # production build
yarn lint           # ESLint
yarn generate:api   # regenerate the typed API client from the backend OpenAPI spec
```

> When you change the backend contract (endpoints, request/response shapes, routes,
> or auth attributes), restart the API and run `yarn generate:api` to keep the
> frontend's typed client in sync. A reachable-but-stale backend silently produces a
> stale client.

## Tech stack

- **Backend:** .NET 10, C# 14, EF Core 10, Wolverine 6, Dapper, Hangfire, Scrutor
- **Frontend:** React 19, TypeScript 5, Vite, Tailwind CSS 4, TanStack Query v5,
  React Hook Form + Zod, FullCalendar, orval (OpenAPI → typed client)
- **Messaging:** Wolverine on a durable SQL Server transport locally; Azure Service
  Bus as an opt-in transport
- **Local stack:** SQL Server 2025, Keycloak, Mailpit — orchestrated with .NET Aspire
- **Observability:** OpenTelemetry (traces/metrics exported to the Aspire dashboard)

## CI & deployment

The repo includes more pipeline than a sandbox strictly needs, kept as a working
reference:

- **`secret-scan`** — gitleaks on every push/PR. Useful regardless of deployment.
- **`devtest`** — build, test, and frontend lint/build on every push/PR, followed by
  jobs that build a container image, push it to Azure Container Registry, and deploy
  to Azure App Service. **Those deploy jobs require Azure secrets and live
  infrastructure** ([`infra/`](./infra) provisions it via Bicep); without them, only
  the build-and-test stage is meaningful. If you fork this, expect the deploy jobs to
  be red until you supply your own Azure setup (or disable them).

## License

Released under the [MIT License](./LICENSE) — free to use, modify, and distribute,
including commercially. It builds on open-source libraries that remain under their
own licenses; see [`THIRD-PARTY-NOTICES.md`](./THIRD-PARTY-NOTICES.md) for
attribution and a note on Hangfire (LGPL-3.0).
