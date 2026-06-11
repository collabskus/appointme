# AppointMe — Architecture from first principles

This document explains *why* AppointMe is built the way it is. The patterns here
— modular monolith, vertical slices, CQRS, domain events, a permission engine,
fail-closed multi-tenancy — are not decoration. Each one solves a specific
problem, and each one has a cost. The goal of this doc is that you finish it able
to defend every choice **and** name the situation where you'd choose differently.

A running theme: **architecture is the art of deciding what's hard to change
later, and making *that* easy to change.** Almost every pattern below is buying
flexibility in one dimension by spending complexity in another. Good engineering
is knowing which dimension you actually need flexible.

The last section, ["What I'd do differently"](#what-id-do-differently-and-the-traps-this-repo-deliberately-shows),
is the most important. The patterns are the "what to do"; that section is the
"what not to do, and why."

---

## The system at a glance

One deployable process (the monolith) contains four business **modules** —
Identity, Organizations, CRM, Booking — plus a Shared kit and an API host. A
React SPA talks to it over a versioned HTTP API. Writes go through EF Core
aggregates; reads are hand-written Dapper queries. Modules never call into each
other's internals — they communicate through published **contracts** and
in-process **messages** carried by Wolverine. Every tenant-owned row is scoped to
a company that's resolved per request and enforced in the database layer.

That's the whole shape. The rest is detail and justification.

---

## Modular monolith

### The problem it solves

Two failure modes sit at opposite ends of a spectrum.

At one end, the **big ball of mud**: a single codebase where everything can reach
everything. It's fast to start and miserable to grow — a change to billing
quietly breaks scheduling because some helper reached across the whole app. There
are no real seams, so there's no safe place to cut.

At the other end, **microservices from day one**: every bounded context is its
own deployable service with its own database, talking over the network. This
gives you hard isolation and independent scaling — at the price of distributed
transactions, network failure handling, versioned wire contracts, eventual
consistency everywhere, and an operational burden (service discovery, tracing,
deployment orchestration) that can swallow a small team whole. You pay all of
that on day one, whether or not your scale or your org structure needs it.

A **modular monolith** takes the middle: **one process and one database, but
hard internal module boundaries enforced in code.** You get the isolation and the
clear seams of services without the network and the distributed-systems tax.

### How it's done here

- A module is a folder of projects under `src/<Module>/` (Identity,
  Organizations, Crm, Booking).
- Each module publishes a **`*.Contracts`** project: the DTOs, integration events,
  and interfaces that are its *public* surface. Everything else in the module is
  internal.
- Modules reference **only each other's Contracts**, never each other's internals.
  When Booking needs to react to "a company was registered," it handles the
  `CompanyRegistered` event from `Organizations.Contracts` — it does not reference
  the Organizations data model.
- The API project (`src/AppointMe.Api`) is the **composition root**: the one place
  that knows about every module and wires them together at startup.

### Why this specific discipline matters

The boundary is only real if it's **enforced**, not merely intended. A comment
saying "please don't call into this" is not a boundary. The `*.Contracts`
indirection makes the boundary a *compile error* to cross: there's simply no
reference that lets module A see module B's internals. That's the entire value —
the architecture defends itself, so it survives contact with a deadline.

The payoff you're banking for later: because the seams are genuine, **any module
could be extracted into its own service** if one day it actually needs separate
scaling or a separate team. You haven't paid the distributed-systems cost, but
you've kept the option to. That's the trade in one sentence — *isolation now,
distribution later if and only if you need it.*

### When you'd choose differently

- **A genuinely tiny app** (a CRUD form over one table) doesn't need modules; the
  ceremony would cost more than the mud would. Boundaries earn their keep once
  there are multiple bounded contexts that change for different reasons.
- **Truly independent scaling or failure isolation** — one component must scale to
  10× the rest, or must stay up when the rest is down — is a real reason to reach
  for separate services. Notice that's a *runtime* requirement, not a tidiness
  preference. "It would feel cleaner as microservices" is not a requirement.

---

## Vertical slice architecture

### The problem it solves

The default way most of us learned to structure a back end is by **technical
layer**: a Controllers folder, a Services folder, a Repositories folder, a
Models folder. It looks tidy in a diagram. But think about how you actually
*work*: you implement a feature — "schedule an appointment." With layers, that one
feature is smeared across four folders, and to understand it you open four files
that each also contain bits of twenty *other* features. The thing that changes
together (a feature) is scattered, and the things that change for different
reasons (unrelated features) are jammed together in the same `AppointmentService`.
That's backwards. It maximises the blast radius of every change.

### The idea

Organise by **feature**, not by layer. Each use case gets its own folder
containing everything that use case needs: the endpoint, the request/command, the
handler that does the work, and the read query that serves it. The unit of code
matches the unit of change.

A slice in this repo typically looks like:

```
Booking/.../Appointments/ScheduleAppointment/
    ScheduleAppointmentEndpoint.cs      // HTTP shape: route, binding, status codes
    ScheduleAppointmentRequest.cs       // the API contract
    ScheduleAppointmentCommand.cs       // the internal command
    ScheduleAppointmentCommandHandler.cs// the actual behaviour
```

To understand or change "schedule an appointment," you open **one folder**. To
add a feature, you add a **new folder** — you rarely touch existing ones, so you
rarely risk breaking them.

### Why it's worth it

- **Low coupling between features, high cohesion within one.** Exactly the
  property layered code inverts.
- **Changes are local.** New feature ⇒ new slice. The diff is contained and the
  review is easy.
- **The code reads like the product.** The folder tree is a list of things the
  system does, which is a far better map than a list of architectural nouns.

### The honest costs

- **Some duplication is expected and *fine*.** Two slices may each have a similar
  bit of validation or mapping. Vertical slicing deliberately tolerates a little
  duplication to avoid premature shared abstractions — because a shared helper is a
  coupling point, and coupling between features is the thing you're trying to
  avoid. The discipline is to extract to Shared **only** when the duplication is
  genuinely the same concept, not merely similar-looking code today. (This is the
  practical reading of "prefer duplication over the wrong abstraction.")
- **Cross-cutting concerns need a home.** Auth, logging, validation, transactions
  can't live in every slice. They live in middleware / Wolverine policies (see the
  handler-context section). Slices handle *features*; the pipeline handles
  *everything-features*.

### When you'd choose differently

If a codebase is small and overwhelmingly uniform CRUD, classic layering is
perfectly fine and more familiar to newcomers. Vertical slices shine when
features are numerous and behaviourally distinct — which is exactly the case for
a booking domain with scheduling rules, availability, permissions, and tenancy.

---

## CQRS, the pragmatic kind

### What it is (and what it is *not*)

CQRS — Command Query Responsibility Segregation — means **the model you use to
change state and the model you use to read state don't have to be the same
model.** That's the whole idea. It does *not* require event sourcing, separate
databases, separate services, or message buses. Those are options some teams bolt
on; they are not CQRS.

### Why split reads from writes

Writes and reads want opposite things:

- **Writes** must protect invariants. "You can't book an appointment in the past."
  "A company must have at least one owner." Enforcing rules like these needs a rich
  object — an **aggregate** — that owns its data and refuses to enter an invalid
  state. EF Core, with change tracking and a domain model, is built for this.
- **Reads** just need to shovel exactly the right shape of data to a screen, fast.
  A calendar view wants a flat, joined, paged projection. Loading a graph of
  tracked aggregates to render a list is wasteful and often awkward. Hand-written
  SQL that returns precisely the DTO the screen needs is simpler and faster.

Forcing both through one model means one side always compromises: either your
reads drag a heavy domain model around, or your writes get anaemic to keep reads
convenient.

### How it's done here

- **Write side:** EF Core 10 aggregates. Commands flow through Wolverine handlers,
  load an aggregate, call a method on it that enforces the rules, and save.
- **Read side:** Dapper. Hand-written SQL maps straight to query DTOs, with
  helpers for pagination. No EF model involved.

This is "CQRS-lite": same database, two models over it. You get the clarity of
purpose-built read and write models without the consistency headaches of two data
stores.

### The cost, and when to go further

The cost is **two ways to touch data** — contributors must know writes go through
EF aggregates and reads go through Dapper, and not "tidy" one into the other. That
split is intentional; don't undo it.

You'd go *further* (separate read store, projections kept up to date by events)
only when reads and writes have genuinely different **scaling** needs, or read
shapes are so divergent that maintaining them against the write DB hurts. That's a
real technique with a real price (eventual consistency between the stores); this
app doesn't need it, and reaching for it here would be cargo-culting.

---

## Domain events, the outbox, and the handler-context middleware

### Why domain events at all

When something meaningful happens in one part of the domain, other parts often
need to react. A company is registered ⇒ seed its demo data, set up its defaults.
You could hard-wire those reactions into the registration handler, but then
registration *knows about* demo seeding and defaults and everything else, and grows
a new dependency every time a new reaction is added. That's coupling creeping back
in through the back door.

**Domain events invert the dependency.** The aggregate announces a fact —
"`CompanyRegistered`" — without knowing or caring who listens. Reactions subscribe.
Registration stays about registration; new reactions are new handlers, touching no
existing code. (This is the same decoupling instinct as vertical slices, applied to
*behaviour over time* instead of *code on disk*.)

### The reliability problem, and the outbox

Here's the subtle trap. You change state in the database **and** you want to fire
an event. If you commit the DB change and *then* publish the event, a crash in
between loses the event — the state changed but nobody reacted. If you publish
first and the DB commit fails, you've announced something that didn't happen. This
is the **dual-write problem**, and it's a classic source of "impossible" production
bugs.

The fix is the **transactional outbox**: the event is written to an outbox table
**in the same database transaction** as the state change. Either both land or
neither does. A separate dispatcher then reads the outbox and delivers the events,
retrying until they're acknowledged. Wolverine implements this on top of SQL
Server here (its durable transport). The result is **at-least-once** delivery with
no lost or phantom events — which is why handlers should be **idempotent** (safe to
run twice), since "at least once" can mean "occasionally twice."

### The standout: handler-context middleware

Most handlers need ambient facts about the current call: *which company* is this
for, *who* is the caller, what's their principal. The naïve approaches are both
bad:

- Pass them as parameters through every layer → noise everywhere, and easy to
  forget.
- Reach into a global/static "current context" inside each handler → hidden
  dependency, untestable, and it couples every handler to the ambient plumbing.

This codebase does something cleaner. A Wolverine **`IHandlerPolicy`**
(in `src/AppointMe.Api/Wolverine/HandlerContext/`) inspects each message
handler's **parameters** at startup and, for handlers that *declare* they want the
current company / identity / principal, weaves the code to supply it into the
generated handler pipeline (`chain.Uses<…>()`). A handler that needs the caller's
company simply **adds that parameter to its signature** — and the middleware fills
it in. A handler that doesn't, doesn't pay for it.

Why this is good design, from first principles:

- **Dependencies are explicit and local.** A handler's needs are visible in its
  own signature — the best possible documentation — instead of hidden in a base
  class or a static accessor.
- **Pay-for-what-you-use.** The context is injected only where it's asked for; no
  blanket coupling of every handler to ambient state.
- **Testable.** Test a handler by calling it with the context you want. There's no
  global to stub, no `HttpContext` to fake.

It's the dependency-injection principle ("ask for what you need; don't reach for
it") applied to per-request ambient data, implemented through the framework's
codegen instead of by hand.

---

## The permission engine

### Why not just roles

Role checks ("is this user an Admin?") get you surprisingly far and then fall over.
Real authorization is **per-tenant and per-resource**: company A may let receptionists
cancel appointments while company B reserves that for managers; the platform ships
sensible **defaults** but each company must be able to **override** them. A flat role
enum can't express "the default for this permission is *grant*, but this company has
overridden it to *deny* for this role." You need data, not an enum.

### The model here

Authorization resolves through layers (`src/Organizations/.../PermissionResolver.cs`
and `src/AppointMe.Shared/Authorization/Permissions/`):

1. **Default grants** — the platform's baseline for each permission.
2. **Per-company overrides** — a company can grant or deny on top of the defaults.
3. **Conflict resolution by voting.** When sources disagree, a pluggable
   **`IOverrideConflictPolicy`** decides the winner:
   - **deny-wins** (`DenyWinsPolicy`): *every* vote must grant, or it's denied — the
     conservative, secure default.
   - **grant-wins** (`GrantWinsPolicy`): *any* grant is enough.

### The first-principles wins

- **Open for extension, closed for modification.** Conflict resolution is a
  strategy behind an interface. Need a new policy ("two managers must both approve")?
  Add a class; don't edit the resolver. New behaviour without touching tested code is
  the whole point of the Open/Closed Principle.
- **Secure default.** Deny-wins means a *missing* or *ambiguous* permission denies
  rather than grants. Security decisions should fail toward "no." (Same instinct as
  the tenancy filter below — when in doubt, show/allow nothing.)
- **Policy is data, not code.** Companies customise via override records, not code
  changes or redeploys — exactly what a multi-tenant product needs.

### The cost

It's more moving parts than `[Authorize(Roles="Admin")]`, and resolving a permission
is a small computation rather than a constant. For a multi-tenant SaaS that's the
right trade; for a single-tenant internal tool it would be over-built. Match the
mechanism to whether tenants actually need to differ.

---

## Multi-tenancy, fail-closed

### The stakes

In a multi-tenant system, **the worst bug is one tenant seeing another tenant's
data.** Not a crash — a crash is loud and you fix it. A silent cross-tenant leak is
quiet, catastrophic, and erodes the one thing a SaaS sells: trust. So the design
principle is bluntly defensive: **make leaking data require a deliberate mistake,
and make the failure mode "see nothing," never "see everything."**

### The mechanism, layer by layer

1. **Resolve the tenant once, at the edge.** `CompanyResolutionMiddleware` reads the
   `X-Company-Id` header and puts it into a current-company accessor backed by
   `AsyncLocal`. `AsyncLocal` is the right primitive: it flows with the logical async
   call (so it's available deep in a handler) without being a process-global shared
   across requests. The front end sends the header from
   `src/AppointMe.Frontend/src/lib/axios.ts`.
2. **Enforce it in the database layer.** EF Core **global query filters** (the named
   filters in EF 10) attach `WHERE CompanyId = @current` to *every* query against a
   tenant-owned entity, automatically. You can't forget the `WHERE` clause on a
   read, because you never write it.
3. **Fail closed.** This is the crucial bit. If no company was resolved, the filter
   compares against `null`, so `CompanyId == null` matches **zero** rows. The absence
   of a tenant yields **nothing**, never **everything**. A bug that drops the tenant
   shows an empty screen — annoying, safe, obvious — instead of leaking the whole
   table.

### Why defense in depth, not one check

A single `if` at the controller is one forgotten line away from a breach. Putting
enforcement at the **data layer** means it holds for *every* query by default —
including ones a future contributor writes without thinking about tenancy. Combined
with resolving the tenant at the **edge**, you get two independent layers that both
have to fail in the same direction to leak data. Defense in depth is exactly this:
no single mistake is sufficient to cause the catastrophic outcome.

### The cost / the watch-outs

- Background jobs and message handlers run **outside** an HTTP request, so there's no
  header to read — ambient tenant context has to be **explicitly carried** on the
  message/job. (This is part of what the handler-context middleware is for.) Forgetting
  this is the classic way ambient-context tenancy bites you; the discipline is to make
  the company part of the message, not assume it'll be "around."
- A genuinely cross-tenant admin/reporting query has to *intentionally* bypass the
  filter. That bypass should be rare, obvious, and reviewed — its rarity is a feature.

---

## Value objects & strongly-typed IDs

### Primitive obsession, the disease

Represent an email as `string`, a money amount as `decimal`, a customer id as
`Guid`, and the compiler can't help you. Nothing stops you passing a name where an
email goes, swapping a `CustomerId` and a `CompanyId` (both `Guid` — the type
checker sees no difference), or constructing an "email" that isn't one. The rules
about what makes a value *valid* end up copy-pasted across every place that
accepts the primitive, and drift.

### The fix here

- **Value objects** (`Email`, `PersonName`, …) are small types created through
  **validated factory methods** (`Email.Create(...)`, `PersonName.FromFullName(...)`).
  Validation lives in **one place**, at the boundary where the value comes into
  existence. Once you hold an `Email`, it is — by construction — a valid email;
  nothing downstream needs to re-check.
- **Strongly-typed IDs** are distinct types, not bare `Guid`s. `CustomerId` and
  `CompanyId` are different types, so passing one where the other is expected is a
  **compile error**, not a runtime mystery.
- IDs are generated with `Guid.CreateVersion7()` — time-ordered UUIDs, which (unlike
  random v4) cluster by creation time and so behave far better as database keys
  (less index fragmentation, better insert locality).

### Why it pays off

- **Invalid states become unrepresentable.** The cheapest bug is the one the
  compiler won't let you write. This is the practical face of "make illegal states
  unrepresentable."
- **Validation can't drift**, because it isn't duplicated — it's at the single point
  of construction.
- **The code documents itself.** A method taking `(CustomerId, Email)` tells you far
  more than one taking `(Guid, string)`.

### The cost

A little more typing and a little mapping at the edges (to/from the database and the
wire). It's a small, front-loaded cost that buys correctness for the life of the
codebase — a good trade for any domain with more than a couple of entities. For a
throwaway script, skip it.

---

## Authentication: one hybrid scheme, a real OIDC flow

### Two callers, two mechanisms

The same API serves a **browser** (the SPA) and could serve **API clients**. These
want different auth:

- A browser is happiest with an **HttpOnly, Secure cookie** — it's sent
  automatically and, being HttpOnly, is out of reach of XSS-stealing JavaScript.
- A programmatic client sends a **bearer token** in the `Authorization` header.

This app uses a **policy scheme** (`src/AppointMe.Api/Authentication/`) that picks
per request: if there's a bearer token header, authenticate as **JWT Bearer**;
otherwise, **cookie**. One pipeline, both audiences, no compromise.

### Login is a redirect, on purpose

Login isn't a username/password POST to the API. The login endpoint issues an OIDC
**`Challenge`**, which redirects the browser to the identity provider (Keycloak),
where the user authenticates; Keycloak redirects back to the API's
`/signin-oidc` callback with an authorization **code**; the API exchanges the code
for tokens server-side and establishes the cookie session. This is the OAuth 2.0 /
OpenID Connect **authorization-code flow**.

Why bother, instead of just taking the password yourself? Because the
authorization-code flow means **your application never sees the user's password.**
The IdP owns credentials, MFA, social/enterprise login, lockout, password policy —
all of it. Your app only ever receives short-lived tokens. That's more secure, and
it's *less* code for you to own and get wrong. The deprecated alternative
(Resource Owner Password Credentials, a.k.a. direct grant) hands the password to
your app and throws all of that away — see the next section.

### Pluggable providers

The provider sits behind an abstraction: **Keycloak** is the default; **Microsoft
Entra External ID** is supported by configuration (`Authentication:Provider`). The
flow and the rest of the app don't change when you swap the IdP — only configuration
does. That's the Dependency Inversion Principle paying rent: the app depends on "an
OIDC provider," not on Keycloak specifically.

### The consequence to remember

The auth cookie is **`Secure`-always**, so the browser only sends it over HTTPS.
That's correct — but it means **there is no working plain-HTTP login**. Logging in
requires TLS, which is why the deployment terminates HTTPS at Cloudflare. Don't
"fix" a local HTTP login problem by weakening the cookie; fix it by putting TLS in
front. (This is also half the reason the random-`trycloudflare.com` URL can't carry
login — see the README.)

---

## Testing: what's here, and the honest gap

What exists is a solid base of **unit tests** (xUnit) over the pieces where logic
concentrates — value-object validation, the permission resolver's voting, domain
rules on aggregates. These are fast, run anywhere, and pin down the trickiest bits.
Good.

What's **missing** is **integration tests**: nothing exercises a real request
through the actual pipeline — middleware, auth, Wolverine, EF against a real
database. The tools for this are standard (`WebApplicationFactory` to host the app
in-memory; **Testcontainers** to spin up real SQL Server and Keycloak in Docker for
the duration of a test run), but they aren't wired up here.

Why this matters, from first principles: **the bugs in a system like this live in
the wiring**, not in the leaf logic the unit tests cover. Does the tenant filter
actually fail closed end-to-end? Does the outbox really deliver after a commit? Does
a permission denial actually produce a 403 through the real middleware stack? Unit
tests can't answer those — they mock exactly the seams where these bugs hide.
A handful of integration tests over the critical paths (auth, tenancy isolation,
scheduling, the outbox) would catch a class of failure the current suite cannot.
This is the single highest-value addition the test strategy could make.

---

## What I'd do differently — and the traps this repo deliberately shows

The patterns above are the "what to do." This section is the "what to watch," and
it's the part worth re-reading. A learning sandbox earns its keep partly by showing
where the seams strain.

1. **An aggregate base type implemented as a `record` with a public mutable events
   collection.** C# `record`s give *value equality* — two records are "equal" if
   their fields match. An aggregate has **identity**: two customers with the same
   data are still two different customers. Worse, a public mutable `Events` list
   participating in that generated equality means equality depends on
   not-yet-dispatched events, by reference. Entities should compare by **id**, not by
   value. Prefer a class with identity-based equality (or at minimum keep the events
   out of equality). This is a small footgun today that becomes a real one the moment
   anything puts aggregates in a set or compares them.

2. **No overlap / double-booking check when scheduling.** The scheduling command
   doesn't verify the new appointment doesn't collide with an existing one for the
   same provider. For a *booking* product, "two people booked the same slot" is close
   to the worst domain bug there is. The fix is both an in-domain invariant (the
   aggregate refuses overlaps) **and** a database guard (a constraint / careful
   concurrency handling), because under concurrency two requests can each pass an
   in-memory check and both commit. This is the textbook example of why some
   invariants *must* be enforced at the database, not just in code.

3. **The CI pipeline is shaped for one specific deployment.** The GitHub Actions
   workflow's publish-image and deploy-to-Azure jobs are gated on `main` and assume
   Azure secrets/federated credentials exist. On a fork without them, `main` goes red
   for reasons that have nothing to do with the code. Build-and-test (which everyone
   needs) should be separated from publish-and-deploy (which only the canonical repo
   needs), so a contributor's green build doesn't depend on infrastructure they can't
   have. Pipelines are part of the architecture; portability is a feature.

4. **Request and Command are often near-duplicates.** Many slices have a
   `FooRequest` (the API/wire shape) and a `FooCommand` (the internal shape) that look
   almost identical, plus a mapping between them. It feels like pointless ceremony —
   right up until the day the public API must stay stable while the internal command
   changes, or one external request fans out into several commands. The separation is
   *cheap insurance* on the API↔domain boundary. Reasonable people merge them in small
   apps; just merge them knowingly, understanding what coupling you're accepting.

5. **The "just take the password" temptation (don't).** Because login is a browser
   redirect, it can't ride a random ephemeral hostname (the README explains why). The
   tempting shortcut is to switch to OAuth's **Resource Owner Password Credentials** /
   direct-grant flow so the SPA posts username+password to the API and the browser
   never visits Keycloak. Resist it. ROPC is **deprecated in OAuth 2.1** for good
   reasons: your app handles the user's IdP password (the thing the whole flow exists
   to avoid), and you lose SSO, MFA, social/enterprise login, and centralized policy.
   It would "work" and it would be a step backwards. The right answer to the hostname
   problem is a **stable hostname**, not a weaker protocol. This is the cleanest
   example in the whole project of a shortcut that solves the immediate problem by
   creating a worse one.

6. **Ambient context outside a request.** The tenant and identity are resolved from
   the HTTP request. Background jobs and message handlers have no request, so that
   context must be **explicitly carried** on the job/message. This is correct as
   designed — but it's a sharp edge: add a background path that *assumes* ambient
   context will "be there" and you'll get either a crash or, worse with tenancy, the
   wrong scope. The rule: outside a request, pass the context in; never reach for it.

If you internalise one thing from this section: **every pattern is a trade, the
trades are context-dependent, and the senior move is naming the cost out loud.** The
code above mostly makes good trades. Knowing *why* they're good — and exactly when
they'd flip — is the actual skill.
