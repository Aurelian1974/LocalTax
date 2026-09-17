# 0004 — Split generic endpoint plumbing into LocalTax.Platform.Web, keep LocalTax.Platform.Security permission-only

- **Status:** accepted
- **Date:** 2026-09-17
- **Deciders:** product owner, dev team (1–3 devs)
- **Modules:** none (shared platform projects only); referenced by every module's slices and the host
- **Axes:** none — no module boundary, recipe or A3–A8 value changes; this only splits a shared, AspNetCore-dependent plumbing project introduced by ADR-0003

## Context
| Force | Evidence |
|---|---|
| Naming vs. content | ADR-0003 put `Permission`, `IPermissionCatalog`, `ICurrentUser`, `RequirePermission()` **and** `IEndpoint`, `MapEndpoints()`, `ToHttpResult()` in one project, `LocalTax.Platform.Security`; the second group has no permission/authentication semantics — it is generic minimal-API endpoint discovery and `Result` → `IResult` mapping usable by any module regardless of whether it enforces permissions |
| R-010 auditability | R-010 requires `Platform.Security` to contain "no data access, no Identity types and no module types"; a project that also carries generic HTTP plumbing is a larger, harder-to-audit surface for that rule |
| Reuse | `IEndpoint`/`MapEndpoints()`/`ToHttpResult()` are conventions every module slice needs (feature-scaffold's endpoint discovery), independent of authorization; a future anonymous-only module would still need them without needing `Permission`/`ICurrentUser` |
| Timing | Phase 1 plan (`.ai/plans/20260917-adr-0003-phase-1-access-foundation.md`) step 3 has not been implemented yet — no code exists in `LocalTax.Platform.Security` to migrate; this is a pre-implementation correction, not a migration |
| SharedKernel constraint | ADR-0003 already established `SharedKernel` stays BCL-pure; `IEndpoint`/`ToHttpResult()` need `Microsoft.AspNetCore.Http`/`Routing` types and cannot move there either |

## Options
### Option 1 — Status quo: keep IEndpoint/MapEndpoints()/ToHttpResult()/ISessionValidator all in LocalTax.Platform.Security
- Consequences now: one project instead of two; no extra csproj/solution wiring.
- Consequences in 12 months: the project's name promises security-specific plumbing but the largest share of its surface (endpoint discovery, `Result`→HTTP mapping) is generic; every module slice depends on an assembly that reads as auth-specific even when it only needs endpoint mapping; R-010's "no data access, no Identity types, no module types" boundary review has to separately reason about two unrelated concerns in one assembly.
- Reversibility: medium — splitting later is mechanical but touches every slice file's `using` and every `AddPlatformSecurity`-style call site.
- **Rejected:** name/content mismatch; mixes a generic cross-cutting concern with a security-specific one in a project whose whole purpose (per R-010) is to stay small and auditable.

### Option 2 — Move IEndpoint/MapEndpoints()/ToHttpResult() into LocalTax.SharedKernel
- Consequences now: no new project.
- Consequences in 12 months: `SharedKernel` needs a reference to `Microsoft.AspNetCore.Http`/`Routing`, breaking the ADR-0003 statement that `SharedKernel` "stays BCL-pure"; every consumer of `SharedKernel` (currently BCL-only value types) picks up an AspNetCore dependency, including any future non-web consumer (e.g. a background worker or a unit test project that only needs `Result`).
- Reversibility: low once modules start referencing `SharedKernel` for both value types and endpoint plumbing.
- **Rejected:** contradicts the accepted `shared_kernel.allowed` boundary; `SharedKernel` never depends on AspNetCore.

### Option 3 — New LocalTax.Platform.Web for generic endpoint plumbing; LocalTax.Platform.Security keeps only permission/session types *(chosen)*
- Consequences now: one additional project to scaffold in phase-1 step 1/3 (csproj + solution entry); no other plan step changes because no code exists yet.
- Consequences in 12 months: `Platform.Web` is reusable by any module regardless of its authorization needs; `Platform.Security` stays the small, single-purpose surface R-010 already assumes (`Permission`, `IPermissionCatalog`, `ICurrentUser`, `RequirePermission()`, `ISessionValidator`); a slice's project references communicate intent — depending on `Platform.Web` only means no authorization semantics are involved.
- Reversibility: high — the two projects can be merged back later with a mechanical move if the split turns out unnecessary; starting narrow is cheaper than un-mixing concerns after slices exist.

## Decision
We will add a second shared, AspNetCore-dependent platform project, **`LocalTax.Platform.Web`**, holding generic endpoint plumbing with no security semantics: `IEndpoint` (the marker interface), `MapEndpoints()` (endpoint discovery/mapping over `IEndpointRouteBuilder`, mapping every discovered `IEndpoint` under `MapGroup("/api")` so every module endpoint route starts with `/api/` — R-017), and `ToHttpResult()` (`Result<T>` → `IResult`/`ProblemDetails` mapping). **`LocalTax.Platform.Security`** keeps only permission and session types: `Permission`, `IPermissionCatalog`, `ICurrentUser`, `RequirePermission()` (the endpoint convention that attaches a `PermissionRequirement`), and **`ISessionValidator`** with a BCL-only signature — `ValueTask<bool> IsValidAsync(ClaimsPrincipal principal, CancellationToken ct)` — consumed by `CookieAuthenticationEvents.OnValidatePrincipal`, implemented in `Access`, per the phase-1 plan's session-check decision.

R-015/R-016 are dependency rules, not type allow-lists, so NetArchTest can enforce them without enumerating every type: `LocalTax.Platform.Web` must not depend on `Microsoft.AspNetCore.Authentication*`, `Microsoft.AspNetCore.Authorization`, `Microsoft.AspNetCore.Identity`, `Microsoft.Extensions.Identity*`, `Dapper`, `Microsoft.Data.SqlClient`, `LocalTax.Platform.Security` or any `LocalTax.Modules.*` project. `LocalTax.Platform.Security` must not depend on `LocalTax.Platform.Web`, any `Microsoft.AspNetCore.Identity`/`Microsoft.Extensions.Identity*` namespace, `Dapper`, `Microsoft.Data.SqlClient` or any `LocalTax.Modules.*` project.

Allowed references are explicit: `LocalTax.Platform.Web` references only `LocalTax.SharedKernel` (for `Result`/`Error`); `LocalTax.Platform.Security` references neither `SharedKernel` nor any other project in this split. Neither platform project references the other, and neither references any module. Both are referenced by module feature slices and the host. This is a pre-implementation correction to ADR-0003's phase-1 plan step 3 — no code has been written against the single-project design yet.

## Consequences
- Positive: each shared project has one job — `Platform.Web` is generic HTTP plumbing, `Platform.Security` is permission/session plumbing — matching the naming and making R-010's audit ("no data access, no Identity types, no module types") a smaller, precise check.
- Positive: a future anonymous or non-permission-based module can depend on `Platform.Web` alone.
- Negative / accepted trade-off: one extra project (csproj, solution entry, `assembly reference in the host`) versus Option 1; mitigated by doing this before any slice code exists.
- Enforcement: architecture tests `R015_PlatformWeb_has_no_forbidden_dependencies`, `R016_PlatformSecurity_has_no_forbidden_dependencies` and `R017_MapEndpoints_maps_every_module_route_under_api`.

## Profile diff
```yaml
# .ai/architecture/profile.yml — before → after
platform:                           # shared, AspNetCore-dependent plumbing (schema v1 extension, ADR-0003)
- - project: LocalTax.Platform.Security
-   contains: [Permission, IPermissionCatalog, ICurrentUser, "RequirePermission() endpoint convention"]
-   referenced_by: "module feature slices and the API host; no data access, no Identity types, no module types"
+ - project: LocalTax.Platform.Web
+   contains: [IEndpoint, "MapEndpoints() endpoint discovery mapping every IEndpoint under MapGroup(\"/api\")", "ToHttpResult() Result-to-HTTP mapping"]
+   references: [LocalTax.SharedKernel]
+   referenced_by: "module feature slices and the API host; no security/permission types, no data access, no module types"
+ - project: LocalTax.Platform.Security
+   contains: [Permission, IPermissionCatalog, ICurrentUser, "RequirePermission() endpoint convention", "ISessionValidator: ValueTask<bool> IsValidAsync(ClaimsPrincipal principal, CancellationToken ct)"]
+   references: []
+   referenced_by: "module feature slices and the API host; no data access, no Identity types, no module types, no endpoint-discovery/mapping plumbing"

rules:
+ - { id: R-015, text: "LocalTax.Platform.Web must not depend on Microsoft.AspNetCore.Authentication*, Microsoft.AspNetCore.Authorization, Microsoft.AspNetCore.Identity, Microsoft.Extensions.Identity*, Dapper, Microsoft.Data.SqlClient, LocalTax.Platform.Security or LocalTax.Modules.*.", enforce: test }
+ - { id: R-016, text: "LocalTax.Platform.Security must not depend on LocalTax.Platform.Web, Microsoft.AspNetCore.Identity/Microsoft.Extensions.Identity* namespaces, Dapper, Microsoft.Data.SqlClient or LocalTax.Modules.*.", enforce: test }
+ - { id: R-017, text: "MapEndpoints() maps every discovered IEndpoint under MapGroup(\"/api\"); every module endpoint route starts with /api/.", enforce: test }
```

## Links
- Plan: `.ai/plans/20260917-adr-0003-phase-1-access-foundation.md` (step 3 / assumption 8 updated to reference `Platform.Web` for `IEndpoint`/`MapEndpoints()`/`ToHttpResult()`)
- Related ADRs: extends `docs/adr/0003-staff-authentication-and-authorization.md` (introduces the `platform:` key this ADR splits)
