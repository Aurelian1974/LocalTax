# Plan: ADR-0003 phase 1 — Access foundation (Platform.Web, Platform.Security, schema, Identity stores, sign-in session slices)
id: 20260917-adr-0003-phase-1-access-foundation | class: new-module/XL/structural | modules: Access: pure-slices; Platform.Web: shared; Platform.Security: shared | adr: 0003, 0004 | status: draft

Goal: stand up `LocalTax.Platform.Web` (endpoint plumbing), `LocalTax.Platform.Security` (permission/session types), the `Access` module skeleton (+ Contracts), the `access` schema with a least-privilege app role, the hand-written Dapper Identity stores, `AddAccessModule`, an `AuthAudit` writer, the host cookie-authentication scheme with `ISessionValidator`-based revocation, and a `create-admin` host command — ending with four working staff-session endpoints (`GET /api/access/antiforgery`, `POST /api/access/sign-in`, `POST /api/access/sign-out`, `GET /api/access/me`) and R-009…R-017 + R-DB-03/R-DB-04 enforced by tests.
Out of scope: React SPA wiring; MFA; the Negotiate/external-IdP deployment variants (ADR-0003 options 4–5); `/api/access/change-password` and `/api/access/reset-password`; role/permission-grant management endpoints; the 24-month `AuthAudit` purge job; other modules' permission catalogs.

## Assumptions (no open questions left)
1. Two distinct checks replace the single "session check" of the previous revision: (a) `ISessionValidator.IsValidAsync(ClaimsPrincipal, CancellationToken)` (Platform.Security interface, `SessionValidator` impl in Access, one Dapper query for `GrantsVersion`/`SecurityStamp`/`IsEnabled`) runs inside `CookieAuthenticationEvents.OnValidatePrincipal` (Host) — invalid ⇒ `context.RejectPrincipal()` + `SignOutAsync` ⇒ `401`, on every authenticated request regardless of endpoint (permission-protected included, since cookie validation fires before authorization); (b) `MustChangePassword` is a separate authorization-time check (`MustChangePasswordAuthorizationHandler` in Access, its own single-column Dapper read) returning `403` for every route except `/api/access/me`, `/api/access/change-password`, `/api/access/sign-out` — never folded into `ISessionValidator`. Identity lockout affects neither check (sign-in only).
2. `IUserRoleStore`/`IUserClaimStore` need tables not named in the request; added as `access.StaffUserRole` (join) and `access.StaffUserClaim` (direct grants), alongside the four named tables.
3. Data-access primitives (`Data/AccessConnectionFactory.cs`) are module-internal to `Access`; no new shared data-access project is introduced.
4. `/api/access/change-password` is out of scope for phase 1 (not in the requested endpoint list). The `R-013` negative case and the "permission-protected endpoint rejects a revoked session" case (item 2 of the request) both need one already-authorized route to probe; rather than inventing a business endpoint, `Access.IntegrationTests` maps one test-only route (`GET /api/access/_test/permission-protected`, `RequirePermission("access.test-permission")`) inside the `WebApplicationFactory` used by those tests only — it never ships in `Program.cs`.
5. Permission policies use ASP.NET Core's dynamic `IAuthorizationPolicyProvider` with one requirement type (`PermissionRequirement`), so `RequirePermission("module.action")` needs no pre-registered named policy per string; `IPermissionCatalog` feeds `GET /api/access/me` and later admin screens, not policy resolution.
6. The least-privilege script (R-DB-03) grants `SELECT, INSERT, UPDATE, DELETE` on `SCHEMA::access` to the app database role (the app must maintain `StaffUser`/`Role`/etc.), then `DENY UPDATE, DELETE` specifically on `access.AuthAudit` only, so that table alone is append-only despite the schema-wide grant; no password is scripted (R-DB-02) — a comment tells the user to create the SQL login and add it to the role.
7. `scripts/New-Migration.ps1` does not exist yet (only `New-Slice.ps1`, `Build-AiKit.ps1`, `Set-AiState.ps1` do). Step 1 authors it, mirroring `New-Slice.ps1`'s style (`#Requires -Version 7.0`, named params, no overwrite): `pwsh scripts/New-Migration.ps1 -Slug <PascalCaseSlug>` writes `db/migrations/<yyyyMMddHHmmss>_<Slug>.sql` (UTC timestamp; retried +1s on collision) pre-filled with the `SET NOCOUNT ON; SET XACT_ABORT ON;` / `BEGIN TRY BEGIN TRAN … COMMIT / END TRY BEGIN CATCH … ROLLBACK; THROW; END CATCH` skeleton from `sql-server-data-access` §2 and prints only the created path. Every migration path below is illustrative (`db/migrations/<generated>_AccessSchema.sql`); the literal name is whatever the script prints when run.
8. `create-admin <username>` is a `LocalTax.Host` CLI command, dispatched from the top of `Program.cs` before the web host starts listening (`dotnet run --project src/LocalTax.Host -- create-admin <username>`). The password is read with `Console.ReadKey(intercept: true)` and echoed as `*`; it is never accepted as a CLI argument, environment variable or file (OWASP A07 / spirit of R-DB-02). The command builds the same `AddAccessModule` composition, resolves `UserManager<StaffUser>`/`RoleManager`, refuses to run if a `StaffUser` with that username already exists (exit 1, stderr message, no partial write), otherwise creates the user, ensures an `Administrator` role holding every permission currently registered in `IPermissionCatalog`, assigns it, sets `MustChangePassword = true`, writes one `AuthAudit` "account created" row (`Actor = "cli:create-admin"`), and exits 0.
9. `PLATFORM-WEB`, `PLATFORM-SEC`, `SHAREDKERNEL` and `DB-MIGRATION` are not literal ids in `placement-rules.md` (that file covers module recipes and Host only); used here by direct analogy — `PLATFORM-WEB`/`PLATFORM-SEC` for the two `profile.yml platform:` projects, `SHAREDKERNEL` for `shared_kernel.allowed`, `DB-MIGRATION` for `db/migrations` per ADR-0002 / `sql-server-data-access`.
10. `Result`, `Error` (SharedKernel, BCL-pure) do not exist yet because `Access` is the first module. Per ADR-0004, `IEndpoint`/`MapEndpoints()`/`ToHttpResult()` go into the new `LocalTax.Platform.Web` (references `SharedKernel` only); `Permission`/`IPermissionCatalog`/`ICurrentUser`/`RequirePermission()`/`ISessionValidator` stay in `LocalTax.Platform.Security` (references neither `SharedKernel` nor `Platform.Web`). `AccessModule.cs` only registers DI (`AddAccessModule`); endpoints are discovered by `Platform.Web`'s `IEndpoint` scan (`MapEndpoints()` under `MapGroup("/api")`, R-017) — the host never calls a per-module `Map…` method.
11. `R014_Principal_carries_only_identity_claims`, `R014_Authorization_does_not_read_claims_from_principal` and `RDB04_Fixture_rejects_databases_not_ending_in_Tests` move to `Access.IntegrationTests` (they exercise runtime behaviour against a live host/database). `tests/LocalTax.ArchitectureTests/ArchitectureTests.cs` keeps only the generic profile-driven rule tests (R-001…R-008, R-DB-01, R-DB-02 review-only) plus `R015_PlatformWeb_has_no_forbidden_dependencies`, `R016_PlatformSecurity_has_no_forbidden_dependencies` and `R017_MapEndpoints_maps_every_route_under_api` — dependency/route-shape checks that need no database and stay with the NetArchTest suite, per ADR-0004's enforcement list.
12. `R-DB-03` is `enforce: review` in `profile.yml` (unchanged by this plan); the `LeastPrivilegeRoleTests` added in step 2 are an additional automated check on top of that review, not a profile change.

## Steps
| # | Step (one vertical increment) | Scaffold | Data | Tests | Done |
|---|---|---|---|---|---|
| 1 | Bootstrap projects: `SharedKernel` (`Result`, `Error`), `Platform.Web`, `Platform.Security`, `Access` + `Access.Contracts`, `Host`, `Access.IntegrationTests`; author `scripts/New-Migration.ps1`; wire into `LocalTax.slnx` | manual — `dotnet new classlib`/`dotnet new web` per project, no slice template for scaffolding | none | build only (no test framework exercised yet) | [ ] |
| 2 | `access` schema: `StaffUser`, `Role`, `RoleClaim`, `StaffUserRole`, `StaffUserClaim`, `AuthAudit` + least-privilege DB role script (schema-wide grant, `DENY UPDATE, DELETE` on `AuthAudit` only — R-DB-03) | `pwsh scripts/New-Migration.ps1 -Slug AccessSchema`; `pwsh scripts/New-Migration.ps1 -Slug AccessLeastPrivilegeRole` | expand: `db/migrations/<generated>_AccessSchema.sql`, `db/migrations/<generated>_AccessLeastPrivilegeRole.sql` | `RDB04_Fixture_rejects_databases_not_ending_in_Tests`; `LeastPrivilegeRole_DeniesUpdateAndDeleteOnAuthAudit` (runs `EXECUTE AS USER = '<approle>'`) | [ ] |
| 3 | `LocalTax.Platform.Web`: `IEndpoint`, `MapEndpoints()` (mapping every discovered endpoint under `MapGroup("/api")`), `ToHttpResult()`; `LocalTax.Platform.Security`: `Permission`, `IPermissionCatalog`, `ICurrentUser`, `PermissionRequirement`, `MustChangePasswordRequirement`, `RequirePermission()`, dynamic policy provider, `ISessionValidator` | manual — shared plumbing, no slice template | none | `R017_MapEndpoints_maps_every_route_under_api`; `R015_PlatformWeb_has_no_forbidden_dependencies`; `R016_PlatformSecurity_has_no_forbidden_dependencies`; smoke unit test `RequirePermission_sets_the_permission_requirement` | [ ] |
| 4 | Access Dapper Identity stores (`IUserStore`, `IUserPasswordStore`, `IUserSecurityStampStore`, `IUserLockoutStore`, `IUserClaimStore`, `IUserRoleStore`, `IRoleStore`, `IRoleClaimStore`) + `AddAccessModule` + `IAuthAuditWriter`/`AuthAuditWriter` + host `create-admin <username>` command | manual — Identity store implementations + CLI command, no slice template | none | `StaffUserStoreTests.Create_and_find_user_by_normalized_username`, `.Set_and_verify_password_hash`, `.Set_and_get_security_stamp`, `.Increment_and_reset_lockout`, `.Add_and_remove_user_claims`, `.Add_and_remove_user_roles`; `R010_Identity_types_are_confined_to_Access`; `AuthAuditWriterTests.Writes_a_row_for_account_created`; `CreateAdminCommand_creates_first_admin_and_refuses_duplicate_username` | [ ] |
| 5 | Host: cookie authentication scheme; `SessionValidator` (Access impl of `ISessionValidator`) wired into `AccessCookieAuthenticationEvents.OnValidatePrincipal` (reject + `SignOutAsync` → 401 on invalid session); `MustChangePasswordAuthorizationHandler` (403, path allow-list); `ForwardedHeaders` known-proxies list; custom `AccessClaimsPrincipalFactory` (user id + security stamp only) | manual — host composition + Identity claims factory, no slice template | none | `Cookie_expires_at_idle_timeout_and_absolute_lifetime`; `SessionValidator_rejects_disabled_or_stamp_mismatched_principals_but_not_locked_out_ones`; `R014_Principal_carries_only_identity_claims` | [ ] |
| 6 | Slice: `GET /api/access/antiforgery` (anonymous) + `POST /api/access/sign-in` (failure counter per IP+username before password check, then Identity lockout, `AuthAudit` writes for success/failure/throttle/lockout) | `pwsh scripts/New-Slice.ps1 -RootNamespace LocalTax -Module Access -Feature Sessions -UseCase GetAntiforgeryToken -Kind query -Recipe pure-slices -Route access/antiforgery` then edit `.RequireAuthorization(...)` → `.AllowAnonymous()`; `pwsh scripts/New-Slice.ps1 -RootNamespace LocalTax -Module Access -Feature Sessions -UseCase SignIn -Kind command -Recipe pure-slices -Route access/sign-in` then edit → `.AllowAnonymous()` | none | `SignIn_succeeds_with_valid_credentials`, `SignIn_locks_out_after_five_failures`, `Sign_in_counter_throttles_failures_only`; `AuthAudit_records_sign_in_success`, `AuthAudit_records_sign_in_failure`, `AuthAudit_records_throttle_rejection`, `AuthAudit_records_lockout` | [ ] |
| 7 | Slice: `POST /api/access/sign-out` (`AuthAudit` write for sign-out) | `pwsh scripts/New-Slice.ps1 -RootNamespace LocalTax -Module Access -Feature Sessions -UseCase SignOut -Kind command -Recipe pure-slices -Route access/sign-out` then edit `.RequireAuthorization("__POLICY__")` → `.RequireAuthorization()` (default policy) | none | `SignOut_clears_session_cookie`; `AuthAudit_records_sign_out`; `R012_Unsafe_verbs_reject_requests_without_antiforgery_token` (covers sign-in + sign-out) | [ ] |
| 8 | Slice: `GET /api/access/me` + `PermissionAuthorizationHandler` (`(userId, grantsVersion)` cache) + test-only permission-protected route (assumption 4) | `pwsh scripts/New-Slice.ps1 -RootNamespace LocalTax -Module Access -Feature Sessions -UseCase Me -Kind query -Recipe pure-slices -Route access/me` then edit → `.RequireAuthorization()` | none | `Me_returns_current_user_identity_and_permissions`; `R013_MustChangePassword_blocks_all_other_endpoints`; `R009_No_role_name_authorization`; `R011_Api_endpoints_require_authorization`; `R014_Authorization_does_not_read_claims_from_principal`; `SessionCheck_RejectsRevokedSession_OnPermissionProtectedEndpoint` (covers request item 2) | [ ] |

### Files
| Step | Path | Kind | Rule |
|---|---|---|---|
| 1 | src/LocalTax.SharedKernel/Result.cs | value type | SHAREDKERNEL |
| 1 | src/LocalTax.SharedKernel/Error.cs | value type | SHAREDKERNEL |
| 1 | src/LocalTax.Platform.Web/LocalTax.Platform.Web.csproj | project | PLATFORM-WEB |
| 1 | src/LocalTax.Platform.Security/LocalTax.Platform.Security.csproj | project | PLATFORM-SEC |
| 1 | src/Modules/Access/LocalTax.Modules.Access/LocalTax.Modules.Access.csproj | project | PS |
| 1 | src/Modules/Access/LocalTax.Modules.Access.Contracts/LocalTax.Modules.Access.Contracts.csproj | project | CONTRACTS |
| 1 | src/Modules/Access/LocalTax.Modules.Access.Contracts/StaffAccountDisabled.cs | integration event | CONTRACTS |
| 1 | src/Modules/Access/LocalTax.Modules.Access.Contracts/IStaffLookup.cs | query interface | CONTRACTS |
| 1 | src/LocalTax.Host/LocalTax.Host.csproj | project | HOST |
| 1 | tests/Modules/Access/LocalTax.Modules.Access.IntegrationTests/LocalTax.Modules.Access.IntegrationTests.csproj | test project | TESTS |
| 1 | scripts/New-Migration.ps1 | script | DB-MIGRATION |
| 1 | LocalTax.slnx | solution (edit: add the 6 new projects) | HOST |
| 2 | db/migrations/<generated>_AccessSchema.sql | schema script | DB-MIGRATION |
| 2 | db/migrations/<generated>_AccessLeastPrivilegeRole.sql | schema script | DB-MIGRATION |
| 2 | tests/Modules/Access/LocalTax.Modules.Access.IntegrationTests/AccessTestDatabaseFixture.cs | test fixture | TESTS |
| 2 | tests/Modules/Access/LocalTax.Modules.Access.IntegrationTests/RDB04FixtureGuardTests.cs | integration test (moved from ArchitectureTests.cs) | TESTS |
| 2 | tests/Modules/Access/LocalTax.Modules.Access.IntegrationTests/LeastPrivilegeRoleTests.cs | integration test | TESTS |
| 3 | src/LocalTax.Platform.Web/IEndpoint.cs | endpoint marker | PLATFORM-WEB |
| 3 | src/LocalTax.Platform.Web/EndpointMappingExtensions.cs | endpoint discovery (`MapEndpoints()` under `MapGroup("/api")`) | PLATFORM-WEB |
| 3 | src/LocalTax.Platform.Web/ResultHttpExtensions.cs | result mapping (`ToHttpResult()`) | PLATFORM-WEB |
| 3 | src/LocalTax.Platform.Security/Permission.cs | value type | PLATFORM-SEC |
| 3 | src/LocalTax.Platform.Security/IPermissionCatalog.cs | interface | PLATFORM-SEC |
| 3 | src/LocalTax.Platform.Security/ICurrentUser.cs | interface | PLATFORM-SEC |
| 3 | src/LocalTax.Platform.Security/PermissionRequirement.cs | authorization requirement | PLATFORM-SEC |
| 3 | src/LocalTax.Platform.Security/MustChangePasswordRequirement.cs | authorization requirement | PLATFORM-SEC |
| 3 | src/LocalTax.Platform.Security/RequirePermissionExtensions.cs | endpoint convention | PLATFORM-SEC |
| 3 | src/LocalTax.Platform.Security/DynamicPermissionPolicyProvider.cs | authorization policy provider | PLATFORM-SEC |
| 3 | src/LocalTax.Platform.Security/ISessionValidator.cs | interface | PLATFORM-SEC |
| 3 | src/LocalTax.Platform.Security/PlatformSecurityServiceCollectionExtensions.cs | composition | PLATFORM-SEC |
| 3 | tests/LocalTax.ArchitectureTests/ArchitectureTests.cs | test (edit: add R-015, R-016, R-017) | TESTS |
| 4 | src/Modules/Access/LocalTax.Modules.Access/Data/AccessConnectionFactory.cs | data access | PS-DATA |
| 4 | src/Modules/Access/LocalTax.Modules.Access/Data/StaffUserStore.cs | data access (IUserStore/IUserPasswordStore/IUserSecurityStampStore/IUserLockoutStore/IUserClaimStore/IUserRoleStore) | PS-DATA |
| 4 | src/Modules/Access/LocalTax.Modules.Access/Data/RoleStore.cs | data access (IRoleStore/IRoleClaimStore) | PS-DATA |
| 4 | src/Modules/Access/LocalTax.Modules.Access/Data/CurrentUser.cs | data access (ICurrentUser impl, reads ClaimsPrincipal only) | PS-DATA |
| 4 | src/Modules/Access/LocalTax.Modules.Access/Data/IAuthAuditWriter.cs | interface | PS-DATA |
| 4 | src/Modules/Access/LocalTax.Modules.Access/Data/AuthAuditWriter.cs | data access (append-only writer) | PS-DATA |
| 4 | src/Modules/Access/LocalTax.Modules.Access/AccessModule.cs | composition (`AddAccessModule`) | PS-MODULE |
| 4 | src/Modules/Access/LocalTax.Modules.Access/AccessPermissions.cs | composition (`IPermissionCatalog` impl) | PS-MODULE |
| 4 | src/LocalTax.Host/Commands/CreateAdminCommand.cs | composition (CLI command, masked password prompt) | HOST |
| 4 | src/LocalTax.Host/Program.cs | composition root (edit: dispatch `create-admin` before `WebApplication` listens) | HOST |
| 4 | tests/LocalTax.ArchitectureTests/ArchitectureTests.cs | test (edit: add R-010) | TESTS |
| 4 | tests/Modules/Access/LocalTax.Modules.Access.IntegrationTests/StaffUserStoreTests.cs | integration test | TESTS |
| 4 | tests/Modules/Access/LocalTax.Modules.Access.IntegrationTests/AuthAuditWriterTests.cs | integration test | TESTS |
| 4 | tests/Modules/Access/LocalTax.Modules.Access.IntegrationTests/CreateAdminCommandTests.cs | integration test | TESTS |
| 5 | src/Modules/Access/LocalTax.Modules.Access/Data/SessionValidator.cs | data access (`ISessionValidator` impl) | PS-DATA |
| 5 | src/Modules/Access/LocalTax.Modules.Access/Data/MustChangePasswordAuthorizationHandler.cs | data access (authorization handler) | PS-DATA |
| 5 | src/Modules/Access/LocalTax.Modules.Access/Data/AccessClaimsPrincipalFactory.cs | data access (Identity claims factory) | PS-DATA |
| 5 | src/LocalTax.Host/Program.cs | composition root (edit: cookie scheme, `OnValidatePrincipal`, `ForwardedHeaders`) | HOST |
| 5 | src/LocalTax.Host/Security/AccessCookieAuthenticationEvents.cs | composition (`OnValidatePrincipal` calling `ISessionValidator`) | HOST |
| 5 | src/LocalTax.Host/Security/ForwardedHeadersSetup.cs | composition | HOST |
| 5 | tests/Modules/Access/LocalTax.Modules.Access.IntegrationTests/SessionValidatorTests.cs | integration test | TESTS |
| 5 | tests/Modules/Access/LocalTax.Modules.Access.IntegrationTests/PrincipalClaimsTests.cs | integration test (moved R-014 tests) | TESTS |
| 5 | tests/Modules/Access/LocalTax.Modules.Access.IntegrationTests/CookieLifetimeTests.cs | integration test | TESTS |
| 6 | src/Modules/Access/LocalTax.Modules.Access/Features/Sessions/GetAntiforgeryToken.cs | slice | PS-HANDLER |
| 6 | src/Modules/Access/LocalTax.Modules.Access/Features/Sessions/SignIn.cs | slice | PS-HANDLER |
| 6 | src/Modules/Access/LocalTax.Modules.Access/Data/SignInAttemptThrottle.cs | data access (failure counter) | PS-DATA |
| 6 | tests/Modules/Access/LocalTax.Modules.Access.IntegrationTests/SignInTests.cs | integration test | TESTS |
| 6 | tests/Modules/Access/LocalTax.Modules.Access.IntegrationTests/AuthAuditSignInTests.cs | integration test | TESTS |
| 7 | src/Modules/Access/LocalTax.Modules.Access/Features/Sessions/SignOut.cs | slice | PS-HANDLER |
| 7 | tests/Modules/Access/LocalTax.Modules.Access.IntegrationTests/SignOutTests.cs | integration test | TESTS |
| 7 | tests/Modules/Access/LocalTax.Modules.Access.IntegrationTests/AntiforgeryTests.cs | integration test (R-012) | TESTS |
| 8 | src/Modules/Access/LocalTax.Modules.Access/Features/Sessions/Me.cs | slice | PS-HANDLER |
| 8 | src/Modules/Access/LocalTax.Modules.Access/Data/PermissionCache.cs | data access (cache) | PS-DATA |
| 8 | src/Modules/Access/LocalTax.Modules.Access/Data/PermissionAuthorizationHandler.cs | data access (authorization handler for `PermissionRequirement`) | PS-DATA |
| 8 | tests/Modules/Access/LocalTax.Modules.Access.IntegrationTests/MeTests.cs | integration test | TESTS |
| 8 | tests/Modules/Access/LocalTax.Modules.Access.IntegrationTests/PermissionProtectedEndpointFixture.cs | test fixture (test-only `RequirePermission` route, assumption 4) | TESTS |
| 8 | tests/Modules/Access/LocalTax.Modules.Access.IntegrationTests/SessionRevocationTests.cs | integration test | TESTS |
| 8 | tests/Modules/Access/LocalTax.Modules.Access.IntegrationTests/MustChangePasswordTests.cs | integration test (R-013) | TESTS |
| 8 | tests/Modules/Access/LocalTax.Modules.Access.IntegrationTests/RoleNameAuthorizationTests.cs | integration test (R-009) | TESTS |
| 8 | tests/Modules/Access/LocalTax.Modules.Access.IntegrationTests/EndpointAuthorizationMetadataTests.cs | integration test (R-011) | TESTS |

### Rules enforced
| # | Rule (business) | Where |
|---|---|---|
| 1 | Failed-sign-in counter checked before password verification, incremented only on failure, keyed by (IP, username), per-IP ceiling for spraying | `SignIn.Handle` |
| 2 | Identity lockout (5/15min) blocks new sign-ins only; never ends a live session | `SessionValidator.IsValidAsync` (ignores lockout state) |
| 3 | Security-stamp mismatch or disabled account ends the request with 401 and signs the cookie out | `AccessCookieAuthenticationEvents.OnValidatePrincipal` via `ISessionValidator` |
| 4 | While `MustChangePassword` is set, only `/me`, `/change-password`, `/sign-out` succeed; every other endpoint returns 403 | `MustChangePasswordAuthorizationHandler.HandleRequirementAsync` (path allow-list) |
| 5 | Permission set cached by `(userId, grantsVersion)`; a grant change invalidates the cache on the next request | `PermissionCache.GetOrCreate` |
| 6 | Idle timeout (30m sliding) and absolute lifetime (12h, not extended by activity), both bound from configuration | `AccessCookieAuthenticationEvents.OnValidatePrincipal` |
| 7 | Principal carries only user id + security stamp; no role/permission claims | `AccessClaimsPrincipalFactory.GenerateClaimsAsync` |
| 8 | Every unsafe-verb endpoint validates an antiforgery token explicitly | `SignIn.Endpoint`, `SignOut.Endpoint` |
| 9 | `access.AuthAudit` is append-only; the application role can `SELECT`/`INSERT` but is denied `UPDATE`/`DELETE` despite a schema-wide grant | `db/migrations/<generated>_AccessLeastPrivilegeRole.sql` |
| 10 | Every mapped `IEndpoint` route starts with `/api/` | `EndpointMappingExtensions.MapEndpoints` (`MapGroup("/api")`) |
| 11 | Sign-in success/failure, throttle rejection, lockout and sign-out are each written to `AuthAudit` | `AuthAuditWriter.WriteAsync` calls in `SignIn.Handle`/`SignOut.Handle`/`SignInAttemptThrottle` |
| 12 | The first administrator account is created only via an interactive, masked console prompt — never a CLI argument, env var or file | `CreateAdminCommand.RunAsync` |

## Data
| # | Change | Stage | Rollback |
|---|---|---|---|
| 1 | `db/migrations/<generated>_AccessSchema.sql`: create schema `access` and tables `StaffUser`, `Role`, `RoleClaim`, `StaffUserRole`, `StaffUserClaim`, `AuthAudit` | expand | Drop in dependency order: `AuthAudit`, `StaffUserClaim`, `StaffUserRole`, `RoleClaim`, `Role`, `StaffUser`, then `DROP SCHEMA access` once empty. Safe in phase 1 — greenfield tables, no other schema/module reads them yet. |
| 2 | `db/migrations/<generated>_AccessLeastPrivilegeRole.sql`: least-privilege DB role for the app login; `GRANT SELECT, INSERT, UPDATE, DELETE` on `SCHEMA::access`, then `DENY UPDATE, DELETE` on `access.AuthAudit` only | expand | `ALTER ROLE <access_app_role> DROP MEMBER <login>` then `DROP ROLE <access_app_role>`; no data loss, permissions-only change. The SQL login itself is created by the user (never scripted with a password, R-DB-02) and is dropped by the user if reverting. |

## Risks
| Risk | Sev | Mitigation |
|---|---|---|
| Hand-written Dapper Identity stores may not fully satisfy `UserManager`/`SignInManager`'s implicit contract (concurrency/security stamps, normalized-name lookups) | Med | `StaffUserStoreTests` cover every store method against real SQL Server before wiring `SignInManager` in step 6 |
| Dynamic per-permission-string authorization (no pre-registered named policy) can silently allow access if the policy provider mis-resolves an unknown permission | High | integration test asserting an unregistered permission string denies access by default (fail closed), added alongside step 8 |
| `OnValidatePrincipal` and the permission `AuthorizationHandler` are two independent pipeline stages; a future change could wire permission-protected endpoints to a scheme that skips cookie validation, silently losing revocation | High | `SessionCheck_RejectsRevokedSession_OnPermissionProtectedEndpoint` (step 8) pins the behaviour against the real pipeline, not just `SessionValidator` in isolation |
| In-memory sign-in failure counter and permission cache are process-local (ADR-accepted trade-off) | Low | documented; out of scope to make them shared/distributed in phase 1 |
| Antiforgery token lifecycle (fetch → sign-in → refresh → sign-out) is easy to break even when the API is correct | Med | API-level test only in phase 1 (`R012_...`); SPA-side refresh wiring is a later phase |
| A new endpoint added later and left off the R-011 anonymous allow-list would be silently mis-classified | Med | `R011_Api_endpoints_require_authorization` enumerates the live mapped-endpoint list at runtime, not a hardcoded string list |
| `scripts/New-Migration.ps1` is new and unreviewed by a human before step 2 runs it | Low | script itself only writes an empty timestamped skeleton (no schema logic); the generated SQL is still reviewed like any other migration |
