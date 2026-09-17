# 0003 — Authenticate staff with Identity Core over Dapper and authorize by permission

- **Status:** accepted
- **Date:** 2026-09-17
- **Deciders:** product owner, dev team (1–3 devs)
- **Modules:** new module `Access`; all modules (authorization of their endpoints)
- **Axes:** A2 new module boundary (`Access`, generic); A7 contracts + startup permission catalog; A1/A3–A6/A8 unchanged for existing modules

## Context
| Force | Evidence |
|---|---|
| Users | city-hall staff only (inspectors, cashiers, service head, administrator); no citizen self-service in scope. Taxpayers reach the system through Ghiseul.ro (`OnlinePayments`), not through login |
| Legal/audit | fiscal acts (assessment, receipt, enforcement document) must be attributable to a named operator with a timestamp; failed sign-ins and permission changes are auditable events |
| Authorization granularity | duties are separated by act, not by screen: a cashier posts receipts but may not correct an assessment; enforcement documents are signed by the service head. Role-name checks would hardcode an organigram that differs per municipality |
| Delivery | React SPA served same-origin by the .NET host (ADR-0001); no third-party API clients, no mobile app |
| Infrastructure | on-prem single deployment at the municipality; no identity provider is guaranteed to exist and no Active Directory is available for development; no distributed-systems or IdP operations experience in a 1–3 dev team |
| Revocation | suspending an operator (suspicion of fraud, staff leaving) must take effect on the next request, not at the end of a session window |
| Operational exposure | the sign-in endpoint is the only pre-authentication surface: failed attempts must be throttled per (IP, username) before the password is verified, on top of per-account lockout; no mail infrastructure exists, so password recovery cannot be self-service |
| Database privileges | `DENY` has no effect for `dbo` or `sysadmin`, so an append-only audit table is only real if the application runs under a dedicated least-privilege login |
| Persistence constraint | ADR-0002 / R-005: no EF Core in any project; Dapper for reads and writes, schema applied by the user as DbUp scripts |
| Security baseline | OWASP A07 (identification/authentication failures): password hashing, lockout, session fixation and credential-revocation handling must not be hand-written |

## Options
### Option 1 — No authentication yet, add it after the fiscal modules (status quo)
- Consequences now: nothing to build; slices ship faster.
- Consequences in 12 months: every endpoint, audit column (`CreatedBy`) and UI action is retrofitted at once; "who did this" is unanswerable for acts already recorded.
- Reversibility: low — attribution cannot be reconstructed retroactively.
- **Rejected:** attribution is a legal requirement of the first fiscal act, not a later feature.

### Option 2 — Hand-rolled authentication (own user tables, own hashing, own session cookie)
- Consequences now: full control, no package beyond Dapper.
- Consequences in 12 months: home-made password hashing, lockout counters, security-stamp/revocation and cookie protection are maintained by the team and reviewed by nobody; each is a known OWASP A07 failure mode.
- Reversibility: medium, but stored password hashes bind the format.
- **Rejected:** reimplements solved, security-critical primitives.

### Option 3 — ASP.NET Core Identity with its EF Core stores
- Consequences now: fastest scaffold; `IdentityDbContext` available immediately.
- Consequences in 12 months: EF Core returns to the dependency graph for one module, against ADR-0002; two persistence models coexist and "just one more EF query" becomes arguable.
- **Rejected:** violates R-005; the value taken from EF here is only table plumbing, which is ~5 DbUp tables and a set of Dapper stores.

### Option 4 — External identity provider (Entra ID, Keycloak, Duende) over OIDC
- Consequences now: an IdP to install, operate, back up and patch, or a cloud tenant and licence, for one on-prem municipality; staff accounts managed outside the application while permissions still live inside it.
- Consequences in 12 months: correct answer if the city hall standardizes on a directory or SSO is mandated.
- **Deferred, not rejected:** the chosen design keeps the swap at host level (see Consequences).

### Option 5 — Windows authentication (Negotiate) against the customer's on-prem Active Directory
- Consequences now: nothing to build and nothing to test in this repo — no local AD is available and none is required for the chosen design; documented here as the expected per-deployment variant.
- Consequences in 12 months: a municipality that already runs AD gets single sign-on with domain accounts and no application password store; the swap is host-level (replace the cookie handler with `AddNegotiate()`), the AD account maps to an existing `Access` user by UPN/SID, and the permission model is unchanged because grants stay application-owned.
- Constraints when adopted: IIS/HTTP.sys hosting with Kerberos, no browser-side sign-in screen, password policy and lockout move to the domain, and the `Access` sign-in slices plus the local password store are disabled for that deployment.
- **Deferred, documentation only:** adopted per deployment when a customer supplies a domain; no implementation in this repo.

### Option 6 — Identity Core + Dapper stores, cookie authentication, permission-based policies *(chosen)*
- Consequences now: one new module, hand-written `IUserStore`/`IRoleStore` implementations, a permission policy provider in the host.
- Consequences in 12 months: password hashing, lockout, security stamps and cookie protection come from the framework; authorization granularity follows fiscal duties and is configurable per municipality without code changes.
- Reversibility: high for the authentication half (replace the cookie handler with OIDC or Negotiate), unchanged for the authorization half (permissions stay application-owned).

## Decision
We will add a module **`Access`** (generic subdomain, `pure-slices`, `transaction-script`, `separate-methods`) owning schema **`access`**. It uses **`Microsoft.Extensions.Identity.Core`** (`UserManager`, `RoleManager`, PBKDF2 `PasswordHasher`, `IdentityOptions`, lockout and security-stamp logic) together with `SignInManager`, which ships in **`Microsoft.AspNetCore.Identity`** (ASP.NET Core shared framework), not in `Microsoft.Extensions.Identity.Core`. Persistence is **module-internal Dapper implementations** of `IUserStore`, `IUserPasswordStore`, `IUserSecurityStampStore`, `IUserLockoutStore`, `IUserClaimStore`, `IUserRoleStore`, `IRoleStore` and `IRoleClaimStore` — role membership and role claims are the stored grant bundles from which the server resolves a user's permission set. No EF Core (R-005 holds).

`Access` owns its own composition: a single `AddAccessModule(IConfiguration)` entry point calls `AddIdentityCore` + `AddRoles` + `AddSignInManager`, registers the Dapper stores, and binds `IdentityOptions` (password policy, lockout) from configuration. The host registers **only the authentication scheme** (cookie handler and its options) and the authorization services; no other project touches Identity types (R-010).

Sessions use **cookie authentication** (`HttpOnly`, `Secure`, `SameSite=Lax`) with an **idle timeout** (sliding, default 30 minutes) and an **absolute lifetime** (default 12 hours, not extended by activity), both bound from configuration. The host returns `401`/`403` with ProblemDetails instead of login redirects. `SameSite=Lax` is not by itself a CSRF defence, so **every unsafe-verb endpoint validates an antiforgery token explicitly, JSON endpoints included** (R-012). The token is issued by an anonymous `GET /api/access/antiforgery`; the SPA fetches it at start-up and **refreshes it after sign-in and after sign-out**, because both operations change the cookie identity and invalidate the previous token. Bearer tokens in browser storage are rejected (XSS token theft).

The principal carries **identity only**: a custom `UserClaimsPrincipalFactory` emits the user id and the security stamp and nothing else — no role claims, no permission claims (R-014). **Permissions are resolved server-side on every request** by an authorization handler that reads `(GrantsVersion, SecurityStamp, IsEnabled)` for the user in **one query**; a security-stamp mismatch or a disabled account ends the request with `401` and signs the cookie out. Lockout is deliberately **not** part of that check: it blocks new sign-ins only, otherwise a third party could lock a colleague's account and sign that colleague out mid-work. A password change therefore revokes every existing session immediately (stamp rotation), while a lockout never does. The permission set comes from a cache keyed by `(userId, grantsVersion)`; `access.StaffUser.GrantsVersion` is bumped by every grant change (role assignment, role-claim change, direct grant, account disable), so the next request misses the cache and sees the new set. Authorization is **permission-based**: a permission is the string `<module>.<action>` (e.g. `receivables.post-receipt`, `taxation.correct-assessment`). Roles exist only as **grant bundles** stored in `access`; code never tests a role name. Each module **registers its own permission catalog at startup** through `LocalTax.Platform.Security` — a small AspNetCore-dependent project holding `Permission`, `IPermissionCatalog`, `ICurrentUser` and `RequirePermission(...)` — so no module takes a compile-time dependency on `Access`, and `Access` needs no reference to the modules it grants for. The SPA reads the resolved set from `GET /api/access/me` to hide actions; the server enforces it on every endpoint.

Account protection: throttling of failed sign-ins is a **failure counter inside the sign-in slice**, not the ASP.NET Core rate-limiter middleware — the middleware acquires a permit before the endpoint runs, so it can neither read the submitted username nor distinguish success from failure. The slice checks the counter **before password verification** and increments it **only on failure**, keyed by `(client IP, username)` with a window of 5 failures / 5 minutes and a per-IP ceiling of 30 failures / 5 minutes for username spraying; exceeding either returns `429` with `Retry-After`. The client IP comes from `ForwardedHeaders` configured with an **explicit known-proxies list** — without it the header is attacker-controlled and the key is forgeable. On top of this sits Identity's per-account lockout of **5 failed attempts → 15 minutes temporary lockout**, which expires without administrator action and rejects sign-in attempts only. There is **no self-service password reset** (no mail infrastructure at start): an administrator with `access.reset-password` issues a one-time password, which sets `MustChangePassword`; while that flag is set the server allows only `GET /api/access/me`, `POST /api/access/change-password` and `POST /api/access/sign-out` and answers every other endpoint with `403` (R-013). **MFA is deferred** to a later ADR, to be introduced for administrator accounts first.

`Access` writes an append-only **`access.AuthAudit`** (sign-in success/failure, rate-limit rejection, lockout, password change and reset, role and permission grant changes, account enable/disable) with actor, IP, user agent and a `TimeProvider` timestamp. The application connects with a **dedicated SQL login mapped to a least-privilege database role — never `db_owner` and never `sysadmin`**, because `DENY` is ignored for `dbo` and members of `sysadmin`: that role is granted `INSERT`/`SELECT` and explicitly **`DENY UPDATE, DELETE`** on `access.AuthAudit` in a DbUp script. Entries are retained **24 months** and purged by a scheduled job running under a separate maintenance login. Fiscal audit stays in the owning modules; they record the operator id taken from `ICurrentUser`.

## Consequences
- Positive: security-critical primitives are framework-owned; duty separation is expressed per fiscal act and configurable per municipality; `ICurrentUser` gives every module attribution without depending on `Access`.
- Positive: revocation is immediate — disabling an account, changing a password or removing a grant takes effect on the next request; no session-lifetime window to reason about during an incident. Lockout stays a sign-in control, so it cannot be used to evict a working colleague.
- Positive: a principal that carries no permission claims cannot go stale and cannot be replayed for authorization; the cookie stays small.
- Positive: the append-only audit trail is enforced by the database, not by discipline, because the application role cannot update or delete its rows.
- Positive: moving to an external IdP or to Windows/Negotiate against a customer's AD changes the host authentication scheme and the claims source; permissions, policies and module code are untouched.
- Negative / accepted trade-off: the Dapper stores are hand-written and must satisfy Identity's contracts (concurrency stamp, normalized names, security stamp, role and role-claim lookups); they are covered by integration tests and are the price of keeping EF Core out.
- Negative / accepted trade-off: the failed-sign-in counter is application code (store plus window logic) instead of framework middleware, because the middleware cannot key on the username; it is process-local and must move to a shared store if the host is scaled out.
- Negative / accepted trade-off: one indexed single-row read per authenticated request for `(GrantsVersion, SecurityStamp, IsEnabled)`, and a process-local permission cache — correct for one deployment, and it must move to a shared or invalidated cache before the host is scaled out.
- Negative / accepted trade-off: a stolen cookie remains usable until the absolute lifetime expires or the security stamp rotates; shortening the absolute lifetime is the configuration lever.
- Negative / accepted trade-off: deployment now has database prerequisites the user must satisfy — a dedicated application login in a least-privilege role (not `db_owner`), a separate maintenance login for the purge job, and a proxy/known-proxies configuration wherever the host sits behind a reverse proxy.
- Negative / accepted trade-off: the SPA must manage the antiforgery token lifecycle (fetch at start-up, refresh after sign-in and sign-out); a missed refresh surfaces as a `400` on the next write.
- Negative / accepted trade-off: explicit antiforgery validation on every unsafe-verb endpoint is per-endpoint work that is easy to forget; it is therefore enforced by an integration test over the mapped endpoint list rather than by convention.
- Negative / accepted trade-off: no self-service password reset means administrator effort for every forgotten password; accepted until mail infrastructure exists.
- Negative / accepted trade-off: a new shared, AspNetCore-dependent project (`LocalTax.Platform.Security`) is referenced by module slices. It is deliberately *not* part of `SharedKernel`, which stays BCL-pure, and must contain no data access and no Identity or module types (R-010).
- Negative: integration tests require the SQL Server instance named in `profile.yml database` (`VALERIA`), not LocalDB — a developer or CI agent without that instance cannot run them; the profile is corrected accordingly.
- Negative: `profile.yml` gains a `platform:` key that schema v1 does not define; the architecture tests ignore unmatched properties, and the schema reference is updated with this ADR.
- Open: MFA (administrators first) — deferred to a later ADR.
- Enforcement:

| Rule | Enforcement |
|---|---|
| R-009 authorization only through permission policies; no role-name checks, no `[Authorize(Roles = …)]` | test `R009_No_role_name_authorization` |
| R-010 no type outside the `Access` module depends on `Microsoft.AspNetCore.Identity` / `Microsoft.Extensions.Identity.Core`; the host calls only `AddAccessModule` and the authentication scheme | test `R010_Identity_types_are_confined_to_Access` |
| R-011 every endpoint mapped under `/api/**` carries authorization metadata unless it is on the explicit anonymous allow-list (`/api/access/sign-in`, `/api/access/antiforgery`, health); static files and the SPA fallback are anonymous and out of scope | test `R011_Api_endpoints_require_authorization` |
| R-012 every `POST`/`PUT`/`PATCH`/`DELETE` endpoint validates antiforgery, JSON included | integration test `R012_Unsafe_verbs_reject_requests_without_antiforgery_token` |
| R-013 while `MustChangePassword` is set, only `me`, `change-password` and `sign-out` succeed; every other endpoint returns `403` | integration test `R013_MustChangePassword_blocks_all_other_endpoints` |
| R-014 the principal carries only user id and security stamp; authorization never reads role or permission claims from it | tests `R014_Principal_carries_only_identity_claims` and `R014_Authorization_does_not_read_claims_from_principal` |
| session check: disabled account or stamp mismatch → `401` + sign-out; an active lockout does **not** end a live session | integration test `Session_check_rejects_disabled_or_stale_principals_but_not_locked_out_ones` |
| failed-sign-in counter checked before password verification, incremented only on failure, keyed by (IP, username) with a per-IP ceiling | integration test `Sign_in_counter_throttles_failures_only` |
| idle timeout and absolute cookie lifetime bound from configuration | integration test `Cookie_expires_at_idle_timeout_and_absolute_lifetime` |
| application connects with a least-privilege SQL login (not `db_owner`/`sysadmin`); `DENY UPDATE, DELETE` on `access.AuthAudit`; 24-month retention job under a separate login | review of the DbUp script and the deployment checklist |
| `ForwardedHeaders` configured with an explicit known-proxies list | review of the host composition root |
| permission strings are declared constants registered in the catalog (no literals at call sites) | review |
| password policy, lockout thresholds, failure-counter windows, session lifetimes and cookie options bound from configuration in `AddAccessModule` / the host scheme | review |

## Profile diff
```yaml
# .ai/architecture/profile.yml — before → after
conventions:
  testing:
-   integration: localdb
+   integration: sqlserver          # the instance in `database:` (VALERIA), test database LocalTax_Tests
+platform:                          # shared, AspNetCore-dependent plumbing (schema v1 extension, ADR-0003)
+  - project: LocalTax.Platform.Security
+    contains: [Permission, IPermissionCatalog, ICurrentUser, "RequirePermission() endpoint convention"]
+    referenced_by: "module feature slices and the API host; no data access, no Identity types, no module types"
modules:
+  - name: Access
+    purpose: "Owns staff accounts, sign-in sessions, roles as permission bundles and the authentication audit trail."
+    subdomain: generic
+    recipe: pure-slices
+    macro: none
+    organization: vertical-slices
+    domain_logic: transaction-script
+    cqrs: separate-methods
+    db_schema: access
+    exposes:
+      contracts_project: LocalTax.Modules.Access.Contracts
+      integration_events: [StaffAccountDisabled]
+      queries: [IStaffLookup]
+    consumes: []
+    skills: []
+    notes: "Identity Core + SignInManager with module-internal Dapper stores (no EF Core, R-005); AddAccessModule is the only Identity composition point. The principal carries only user id and security stamp; permissions are registered at startup in LocalTax.Platform.Security and resolved per request from a (userId, grantsVersion) cache after a single-query session check. Lockout blocks sign-in only. Modules never reference Access; attribution flows through ICurrentUser."
rules:
+  - { id: R-009, text: "Authorization only through permission policies; no role-name checks and no [Authorize(Roles = ...)].", enforce: test }
+  - { id: R-010, text: "Only the Access module depends on Microsoft.AspNetCore.Identity / Microsoft.Extensions.Identity.Core types; the host registers the authentication scheme and calls AddAccessModule. Platform.Security contains no data access, no Identity types and no module types.", enforce: test }
+  - { id: R-011, text: "Every endpoint mapped under /api/** carries authorization metadata unless listed on the explicit anonymous allow-list (sign-in, antiforgery, health); static files and the SPA fallback are anonymous.", enforce: test }
+  - { id: R-012, text: "Every POST/PUT/PATCH/DELETE endpoint validates an antiforgery token explicitly, JSON endpoints included.", enforce: test }
+  - { id: R-013, text: "While MustChangePassword is set, only /api/access/me, /api/access/change-password and /api/access/sign-out succeed; every other endpoint returns 403.", enforce: test }
+  - { id: R-014, text: "The claims principal carries only user id and security stamp; authorization never reads role or permission claims from the principal.", enforce: test }
+  - { id: R-DB-03, text: "The application connects with a dedicated least-privilege SQL login (never db_owner or sysadmin) so that DENY UPDATE, DELETE on access.AuthAudit is effective; the retention job uses a separate maintenance login.", enforce: review }
+ - { id: R-DB-04, text: "Exception to R-DB-01: the integration test fixture may apply DbUp scripts and reset data only on a database whose name ends with _Tests (guard in code, test fails otherwise). The user creates that database; agents never create or drop it.", enforce: test }
```

## Links
- Profile: `.ai/architecture/profile.yml`
- Plan: none
- Related ADRs: extends `docs/adr/0001-architecture-baseline.md`; constrained by `docs/adr/0002-dbup-scripts-instead-of-ef-core-migrations.md` (R-005)
