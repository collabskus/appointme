# CLAUDE.md

Guidance for AI coding assistants (and humans) working in this repository.

AppointMe is a personal learning sandbox: a multi-tenant appointment-booking
SaaS built as a **.NET 10 modular monolith** with a **React 19** front end. It
exists to practise — and to demonstrate clearly — modern back-end architecture
patterns. Correctness matters, but so does being a good worked example. When you
change something, keep it idiomatic and keep the docs honest.

For the *why* behind every pattern named below — from first principles, with the
trade-offs and the things deliberately done "wrong" — read **`docs/ARCHITECTURE.md`**.

---

## Tech stack (authoritative — verify here before claiming versions)

Back end:
- .NET 10 / C# 14 (`LangVersion` 14; uses extension members, `Guid.CreateVersion7`)
- EF Core 10 for writes; **Dapper** for read queries
- **WolverineFx 6** — in-process mediator, message handlers, durable messaging, sagas
- **Hangfire** — background jobs
- **Scrutor** — assembly scanning / decoration
- Asp.Versioning for API versioning; OpenTelemetry for traces/metrics/logs

Front end:
- React 19 + Vite + TypeScript, Tailwind CSS 4
- TanStack Query v5 (uses `useSuspenseQuery`), React Hook Form, Zod 4
- FullCalendar for the calendar UI
- **orval** generates a typed API client from the API's OpenAPI document

Infrastructure / dev:
- **SQL Server 2025** (`mcr.microsoft.com/mssql/server:2025-CU1-ubuntu-24.04`)
- **Keycloak 26** as the identity provider (`quay.io/keycloak/keycloak:26.6`)
- **Mailpit** as the local mail catcher
- **.NET Aspire** (`src/AppointMe.Aspire`) orchestrates all of the above for local dev

> Messaging note: locally and by default, Wolverine uses its **SQL-Server-backed
> durable transport** (`Wolverine:Transport = SqlDurable`) — there is no external
> broker and no Service Bus emulator in the loop. Azure Service Bus is an opt-in
> alternative (`Wolverine:Transport = AzureServiceBus`) used only in the
> Azure-hosted configuration.

---

## Solution layout

A module = a folder of projects under `src/<Module>/`, isolated behind a
`*.Contracts` project. Modules talk to each other only through contracts and
messages, never by referencing each other's internals.

- `src/Identity` — users, sign-up, login/logout, Keycloak provisioning
- `src/Organizations` — companies, members, roles, the **permission engine**
- `src/Crm` — customers
- `src/Booking` — services, providers, availability, **appointments** (fully built)
- `src/AppointMe.Shared` — cross-cutting building blocks (auth primitives,
  domain base types, EF/Dapper helpers, the startup **migration runner**,
  configuration options)
- `src/AppointMe.Api` — the composition root: wires every module, hosts the
  Wolverine handler-context middleware, serves the SPA, owns demo seeding
- `src/AppointMe.Frontend` — the React SPA
- `src/AppointMe.Aspire` — local orchestration host + the Keycloak realm export

---

## Key patterns (what you'll run into)

- **Vertical slices.** Each use case lives in its own folder — endpoint +
  request/command + handler + its read query — not spread across
  Controllers/Services/Repositories layers. Add features as new slices.
- **CQRS, pragmatic.** Writes go through EF Core aggregates; reads are hand-
  written Dapper SQL returning DTOs. They do not share a model.
- **Domain events via Wolverine + an EF outbox.** Aggregates raise events;
  they're persisted in the same transaction as the state change and dispatched
  after commit.
- **Handler-context middleware.** A Wolverine `IHandlerPolicy`
  (`src/AppointMe.Api/Wolverine/HandlerContext/`) inspects each handler's
  parameters and injects ambient context (current company, identity, principal)
  only into the handlers that declare it. If you need the caller's company in a
  handler, just add the parameter.
- **Permission engine.** Default grants plus per-company overrides, with
  conflicts resolved by a pluggable voting policy
  (`IOverrideConflictPolicy`: deny-wins vs grant-wins). See
  `src/Organizations/.../PermissionResolver.cs`.
- **Multi-tenancy, fail-closed.** `CompanyResolutionMiddleware` reads the
  `X-Company-Id` header into an `AsyncLocal` current-company accessor; EF global
  query filters scope every tenant-owned table to it. No company resolved ⇒ the
  filter matches **zero** rows (never "all rows"). The front end sets the header
  in `src/AppointMe.Frontend/src/lib/axios.ts`.
- **Value objects & strongly-typed IDs.** Domain types (`Email`, `PersonName`,
  …) are validated via factory methods; IDs are typed structs, not bare `Guid`s.
  Don't reintroduce primitive obsession.
- **Hybrid authentication.** A policy scheme picks **JWT Bearer** when an
  `Authorization` header is present, otherwise **cookie**. Browser login is a
  standard **OIDC authorization-code flow** (the API issues a `Challenge` that
  redirects to Keycloak). Two providers are supported behind one abstraction:
  **Keycloak** (default) and **Microsoft Entra External ID**
  (`Authentication:Provider = EntraExternalId`).

---

## Common commands

Run the whole thing locally with Aspire (starts SQL Server, Keycloak, Mailpit,
the API, and the frontend, wired together):

```bash
dotnet run --project src/AppointMe.Aspire
```

Or run the backing services with Compose and the app yourself:

```bash
# one-time: trust the dev cert Keycloak serves, and export it for the container
dotnet dev-certs https --trust
dotnet dev-certs https --format PEM --no-password -ep docker/keycloak/certs/keycloak.crt

docker compose up -d                                  # SQL Server, Keycloak, Mailpit
dotnet run --project src/AppointMe.Api                # API  → https://localhost:7233
cd src/AppointMe.Frontend && yarn dev                 # SPA  → https://localhost:5173
```

Build & test:

```bash
dotnet build AppointMe.sln
dotnet test                                           # xUnit unit tests
```

Code generation:

```bash
# Wolverine static codegen (also what the Dockerfile runs at build time)
ASPNETCORE_ENVIRONMENT=Codegen \
  dotnet run --project src/AppointMe.Api -- codegen write

# regenerate the typed frontend API client from the API's OpenAPI doc
cd src/AppointMe.Frontend && yarn generate:api
```

Deploy the full stack in containers (Podman + Cloudflare Tunnel):

```bash
cd deploy
cp .env.example .env          # then edit .env
podman-compose --env-file .env up -d --build
```

See **`README.md` → "Deploy on a Fedora server"** for the full walkthrough.

---

## Conventions & gotchas

- **Migrations apply automatically at startup** via a hosted service
  (`DatabaseMigrationService`). You don't run them by hand; the app migrates each
  registered `DbContext` on boot. A container deploy needs no separate migration
  step.
- **Demo seeding is config-gated, not environment-gated.** Setting
  `Demo:Enabled = true` seeds demo data even in Production. It is off by default
  in `appsettings.json`.
- **Reads use Dapper, writes use EF.** Don't "tidy up" a Dapper read query into
  the EF model or vice versa — the split is intentional.
- **Cross-module calls go through `*.Contracts` and messages only.** If you find
  yourself wanting a project reference into another module's internals, that's
  the smell the module boundary is meant to catch.
- **Auth cookie is `Secure`-always.** Login therefore requires HTTPS; there is no
  supported plain-HTTP login path (the deployment terminates TLS at Cloudflare).
- **The API serves the SPA.** In a published build the React bundle is copied to
  `wwwroot` and served with an `index.html` fallback; there is no separate
  front-end server in production.
