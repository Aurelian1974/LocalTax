# State
task: ADR-0003 phase 1: Access module skeleton, Platform.Security, schema, host wiring, R-009..R-014 + R-DB-04
class: new-module size=XL impact=structural
modules: Access: pure-slices; Platform.Security: shared
plan: .ai/plans/20260917-adr-0003-phase-1-access-foundation.md
adrs: docs/adr/0003-staff-authentication-and-authorization.md; docs/adr/0004-platform-web-and-platform-security-split.md
base: 46d039f
sha: 46d039f
tool: copilot
phase: plan
gate: G1 waiting
steps: none
review_cycles: 0
next: implementer: plan step 1

## decisions
- Session validity check (GrantsVersion/SecurityStamp/IsEnabled) runs in CookieAuthenticationEvents.OnValidatePrincipal via ISessionValidator (interface in platform project, impl in Access): reject+sign-out -> 401; MustChangePassword stays authorization-time 403
- MapEndpoints() maps under MapGroup(/api); add test that every module endpoint path starts with /api/ so R-011 cannot pass vacuously
- Add access.AuthAudit writer with writes for sign-in success/failure, throttle rejection, lockout, sign-out; integration tests assert rows
- Least-privilege script grants SELECT/INSERT/UPDATE/DELETE on schema access, DENY UPDATE/DELETE on access.AuthAudit only; test via EXECUTE AS USER for the app role
- Migrations are created with scripts/New-Migration.ps1 (timestamped names), not 0001-*.sql literal prefixes
- Host gets a create-admin <username> command with interactive password prompt, no password in scripts
- R014 principal-claims test and R-DB-04 guard test move to the integration test project, not ArchitectureTests.cs
- R-015/R-016 are dependency rules via NetArchTest, not type allow-lists: Platform.Web must not depend on AspNetCore.Authentication*/Authorization/Identity, Microsoft.Extensions.Identity*, Dapper, Microsoft.Data.SqlClient, LocalTax.Platform.Security, LocalTax.Modules.*; Platform.Security must not depend on LocalTax.Platform.Web, Identity namespaces, Dapper, Microsoft.Data.SqlClient, LocalTax.Modules.*
- MapEndpoints() maps every IEndpoint under MapGroup(/api); add R-017 enforce:test that every module endpoint route starts with /api/
- ISessionValidator signature is BCL-only: ValueTask<bool> IsValidAsync(ClaimsPrincipal principal, CancellationToken ct)
- Allowed references: Platform.Web -> SharedKernel only (Result/Error); both platform projects referenced by module slices and host; neither references the other or any module

## notes
- First module+platform project in repo: no src/Modules or Host project exists yet; profile.yml already has Access + platform: sections from accepted ADR-0003; R-009..R-014 tests not yet written; no db/migrations folder yet

## log
- 2026-09-17 16:03 copilot classify state created
- 2026-09-17 16:04 copilot plan research done
- 2026-09-17 16:15 copilot plan plan written, 8 steps
- 2026-09-17 16:25 copilot architect G1 rejected; 8 revisions requested; item 6 needs architect decision on IEndpoint/MapEndpoints/ToHttpResult placement (new LocalTax.Platform.Web vs staying in Platform.Security)
- 2026-09-17 16:26 copilot architect architect proposed ADR-0004: split Platform.Web (endpoint plumbing) from Platform.Security (security types)
- 2026-09-17 16:34 copilot architect G0 revision requested on ADR-0004
- 2026-09-17 16:35 copilot architect ADR-0004 revised per user feedback: R-015/R-016 as NetArchTest dependency rules, R-017 added, ISessionValidator signature fixed, allowed references stated
- 2026-09-17 16:38 copilot plan G0 approved; ADR-0004 accepted; profile.yml applied (Platform.Web + Platform.Security split, R-015..R-017)
- 2026-09-17 16:45 copilot plan plan re-written with ADR-0004 split and all 8 revisions, 8 steps, 7 risks
