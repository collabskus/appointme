# AppointMe

A multi-tenant **appointment-booking SaaS**, built as a **.NET 10 modular
monolith** with a **React 19** front end.

This is a **personal learning sandbox**. It is a deliberately over-engineered
worked example: a place to practise modern back-end architecture — modular
monoliths, vertical slices, CQRS, domain events, a permission engine,
fail-closed multi-tenancy — and to write the reasoning down so it teaches.
It is not a product and comes with no warranty. Treat the code as a reference,
not as something to run a real business on.

If you want the architecture explained from first principles — what each pattern
is, *why* it's used here, and where it's deliberately taken too far — start with
**[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)**.

---

## What's in the box

| Concern        | Choice                                                                 |
|----------------|------------------------------------------------------------------------|
| Language       | C# 14 on .NET 10; TypeScript on the front end                          |
| Web            | ASP.NET Core minimal APIs, versioned with Asp.Versioning               |
| Messaging      | **WolverineFx 6** (in-process mediator + **SQL-Server durable** transport) |
| Writes         | EF Core 10 (aggregates)                                                |
| Reads          | Dapper (hand-written SQL → DTOs)                                        |
| Background jobs| Hangfire                                                               |
| Identity       | **Keycloak 26** (OIDC); Microsoft Entra External ID also supported     |
| Database       | **SQL Server 2025**                                                    |
| Mail (local)   | Mailpit                                                                |
| Front end      | React 19, Vite, Tailwind 4, TanStack Query v5, React Hook Form, Zod 4, FullCalendar |
| API client     | Generated from OpenAPI with **orval**                                  |
| Local orchestration | **.NET Aspire**                                                   |
| Observability  | OpenTelemetry                                                          |

Modules: **Identity**, **Organizations** (companies, roles, permissions),
**CRM** (customers), **Booking** (services, providers, availability,
appointments).

---

## Run it locally

You need the .NET 10 SDK, Node.js 22 + Yarn, and a container engine (Docker or
Podman).

### Option A — Aspire (one process orchestrates everything)

```bash
dotnet run --project src/AppointMe.Aspire
```

Aspire starts SQL Server, Keycloak, and Mailpit, then launches the API and the
front end already wired together. The Aspire dashboard prints the URLs.

### Option B — Compose for the backing services, app by hand

```bash
# one-time: trust the ASP.NET dev cert and export it for Keycloak to serve
dotnet dev-certs https --trust
dotnet dev-certs https --format PEM --no-password -ep docker/keycloak/certs/keycloak.crt

docker compose up -d                          # SQL Server, Keycloak, Mailpit
dotnet run --project src/AppointMe.Api         # API  → https://localhost:7233
cd src/AppointMe.Frontend && yarn dev          # SPA  → https://localhost:5173
```

The repo-root `compose.yaml` runs **only the dependencies** — it mirrors what
Aspire brings up, on the same ports and credentials, for when you'd rather run
the API and SPA yourself.

> **Sign-up needs the mail catcher.** Creating an account sends a "verify your
> email and set your password" link. Read it in Mailpit (the Compose setup
> exposes its web UI on `http://localhost:8026`) and click through to set a
> password — that's how a new account becomes usable.

---

## Deploy on a Fedora server

This brings up the **entire application in containers** — API (which also serves
the React SPA), SQL Server, Keycloak, Mailpit — and publishes it on the internet
over HTTPS through a **Cloudflare Tunnel**, with **one command**. Everything is
built from `Containerfile`s by Podman; nothing needs to be installed on the host
except Podman itself.

Files live in [`deploy/`](deploy/).

### Prerequisites

```bash
sudo dnf install -y podman podman-compose
```

- A domain on a **Cloudflare** account (the free plan is fine). You'll publish
  the app on three subdomains of it.
- Roughly **3–4 GB of free RAM** (SQL Server alone wants ~2 GB) and a couple of
  GB of disk for images and data.
- An `x86_64` host. (The SQL Server image is x86-only; on ARM you'd swap in Azure
  SQL Edge.)

### 1. Create a Cloudflare named tunnel

In the Cloudflare dashboard: **Zero Trust → Networks → Tunnels → Create a
tunnel → Cloudflared**. Name it, and copy the **token** from the install command
it shows you (the long `eyJ...` string after `--token`).

Then, on the tunnel's **Public Hostnames** tab, add **three** routes. The
*Service* is the in-container address — cloudflared resolves these names on the
Podman network:

| Public hostname        | Type | Service          |
|------------------------|------|------------------|
| `app.your-domain.com`  | HTTP | `api:8080`       |
| `auth.your-domain.com` | HTTP | `keycloak:8080`  |
| `mail.your-domain.com` | HTTP | `mailpit:8025`   |

### 2. Configure the deployment

```bash
cd deploy
cp .env.example .env
```

Edit `.env`:

- `APP_PUBLIC_URL=https://app.your-domain.com`
- `AUTH_PUBLIC_URL=https://auth.your-domain.com`
- `TUNNEL_TOKEN=` ← the token from step 1
- **Change every secret**: `SA_PASSWORD`, `KC_ADMIN_PASSWORD`. (The Keycloak
  admin console is public at `auth.your-domain.com/admin`, so don't leave
  `admin/admin`.)

Every variable is documented inline in `.env.example`.

### 3. Bring it up — one command

```bash
podman-compose --env-file .env up -d --build
```

That's it. Podman builds the SPA and the API from source, builds a self-
contained Keycloak image (realm baked in), starts the database and mail catcher,
registers your public URL with Keycloak, and opens the tunnel.

The **first** build is slow (it compiles the .NET solution and bundles the
front end) and, on first boot, the API may restart a couple of times while SQL
Server finishes initialising — that's expected and self-heals. Watch it settle
with:

```bash
podman-compose --env-file .env logs -f api
```

Open `https://app.your-domain.com`, create an account, read the verification
email at `https://mail.your-domain.com`, set your password, and log in.

Tear down:

```bash
podman-compose --env-file .env down        # keep data (named volumes)
podman-compose --env-file .env down -v     # also wipe the database & Keycloak data
```

### Rootful vs rootless

The happy path on a dedicated server is **rootful** Podman, which avoids
user-namespace UID surprises with the database volume:

```bash
sudo podman-compose --env-file .env up -d --build
```

The compose file is also written to work **rootless** — the `:U` flag on the two
data volumes (see below) chowns them to the right in-container user so SQL Server
and Keycloak can write to them. If you hit a database permission error rootless,
that flag is the fix; rerunning rootful is the quick escape hatch.

### A note on SELinux and `:z` / `:Z` (Fedora)

On Fedora, SELinux stops a container from reading host files through a bind mount
unless the mount is relabelled:

- **`:z`** — relabel the content as **shared** (multiple containers may use it).
- **`:Z`** — relabel as **private** to a single container. More secure; use it
  unless two containers genuinely share the path.

```yaml
volumes:
  - ./some/host/dir:/in/container:Z      # private to this container
```

**This deployment has no bind mounts**, so there is nothing to relabel — the
realm export and the config script are baked into the Keycloak image instead, and
all persistent data lives in **named volumes** (which Podman labels for SELinux
automatically). If you later add a bind mount (say, a `cloudflared` config file),
add `:Z` to it. The `:U` you'll see on the data volumes is unrelated to SELinux —
it fixes file **ownership**, not the security label.

### Why a *named* tunnel — and not `try cloudflare` (the random URL)

The quick `cloudflared tunnel --url http://api:8080` command hands you a fresh
random `https://something.trycloudflare.com` address each run, with no account
and no domain. It's great for showing a colleague a static site in ten seconds.

**It cannot carry this app's login**, and the reason is worth understanding,
because it's a property of OIDC, not a Cloudflare limitation:

1. **The login is a browser redirect.** Logging in sends the browser *to
   Keycloak* and back. So Keycloak itself has to be reachable at a public URL the
   browser can hit — but a quick tunnel gives you exactly **one** URL, pointed at
   one service. You can't reach both the app and Keycloak through it.
2. **OIDC pins itself to a known hostname.** Every token Keycloak issues stamps
   the issuer (`iss`) with its public hostname, and the API rejects tokens whose
   issuer doesn't match what it was configured to trust. A hostname that's
   different on every boot can't be configured ahead of time.
3. **Redirect URIs are allow-listed.** Keycloak only redirects back to URLs a
   client has pre-registered (that check is what stops an attacker stealing your
   authorization code). You can't pre-register a hostname you won't know until
   the tunnel is already running.

In short, **interactive OIDC login needs a stable, known-in-advance hostname**,
and a named tunnel gives you exactly that for free. (You *could* make the random
URL work by discovering it at boot and rewriting Keycloak's hostname, the API's
authority, and the clients' redirect URIs on every start — but that's a pile of
fragile glue that teaches a pattern you should never ship. The honest answer is:
use a named tunnel. It's the same `cloudflared`, same free plan, one extra DNS
record.)

You *can* still point a quick tunnel at `api:8080` to confirm the tunnel works
and watch the login page render — just expect the login round-trip itself to
fail until you move to a named tunnel.

### Tempted to switch login to a username/password POST instead?

It would make the random-URL problem vanish (the browser would only ever talk to
the app). Don't. That's OAuth's **Resource Owner Password Credentials** /
"direct grant" flow — deprecated in OAuth 2.1, and it throws away SSO, MFA,
social login, and the principle that your app never handles the user's IdP
password. It's a textbook example of a shortcut that's an anti-pattern;
`docs/ARCHITECTURE.md` walks through why.

---

## Continuous integration

GitHub Actions builds and unit-tests the solution on push. Note the workflow also
contains **publish-image** and **deploy-to-Azure** jobs gated on `main`; those
require Azure secrets and federated credentials to be configured in the repo, and
will fail on a fork without them. If you fork this to experiment, either add those
secrets or gate/remove those jobs — they're independent of the Podman deployment
above.

---

## License

MIT. See [`LICENSE`](LICENSE).
