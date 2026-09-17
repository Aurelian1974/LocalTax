# 0001 — Establish the LocalTax architecture baseline

- **Status:** accepted
- **Date:** 2026-09-17
- **Deciders:** product owner, dev team (1–3 devs)
- **Modules:** TaxpayerRegister, Taxation, Receivables, Enforcement, Reporting, OnlinePayments
- **Axes:** A1–A8

## Context
Forces gathered in the selection interview (`.ai/state/current.md`):

| Force | Evidence |
|---|---|
| Capabilities | taxpayer register; declaration of buildings/land/vehicles; annual assessment; payments & receipts; arrears and penalties; enforcement; certificates and reports — 7 capabilities, ≥ 3 with distinct language |
| Regulated rules | assessment/calculation, penalty accrual, payment allocation order: legally dated, audited, expensive when wrong |
| Change rate | rates, zones, coefficients and exemptions change at least yearly (national law + local council decisions), independent of UI/DB |
| Integrations | none at start; Ghiseul.ro payment gateway and e-mail/PDF are expected later |
| Team | 1–3 developers, shared ownership, moderate DDD experience, no distributed-systems operations |
| Scale & ops | one or a few municipalities, single deployment, no measured read-scale problem |
| Lifetime | long-lived line-of-business system |
| Code base | greenfield: no source code exists |
| Stack (fixed by the user) | .NET 10, SQL Server (VALERIA/LocalTax, Windows auth, schema applied by the user), Dapper for reads and writes, EF migrations, xUnit + LocalDB, NetArchTest, React + TypeScript |

## Options
### Option 1 — Single-project monolith, CRUD slices, rules in SQL and handlers (status quo for a greenfield 1–3 dev team)
- Consequences now: fastest first screens; no module wiring; every rule reachable from anywhere.
- Consequences in 12 months: assessment, penalty and allocation rules duplicated between stored procedures, handlers and UI; a legal change requires hunting them; no place to unit-test a legally dated calculation; audit questions answered by reading SQL.
- Reversibility: low — extracting a domain model out of SQL is the expensive migration described in `architecture-migration`.
- **Rejected:** the three regulated calculations are exactly the code that must be isolated and testable.

### Option 2 — Modular monolith with `clean-sliced` (Domain/Application/Infrastructure projects), EF Core, repositories and a mediator for every module
- Consequences now: ~24 projects and a mediator pipeline for a 1–3 dev team; master-data and reporting modules get an empty Domain layer (⚠️ "Clean + transaction script" in the compatibility matrix); conflicts with the fixed Dapper decision.
- Consequences in 12 months: ceremony cost paid on every slice; the team's moderate DDD experience is spent on plumbing instead of fiscal rules.
- Reversibility: high, but the cost is paid up front for a benefit that only two modules need.
- **Rejected:** over-engineering relative to team size; `sliced-domain` gives the same domain isolation and upgrades to `clean-sliced` cheaply if a second adapter appears.

### Option 3 — Microservices per capability
- Consequences now: messaging, per-service CI, observability and distributed transactions for a team that has none of it; one deployment target.
- Consequences in 12 months: distributed monolith around a shared fiscal account.
- Reversibility: very low.
- **Rejected:** none of the four microservice preconditions holds — no separate teams or cadence, no differing scale/availability profile, no isolation requirement that processes solve, no distributed-systems experience.

### Option 4 — Modular monolith, one deployable, heterogeneous recipe per module *(chosen)*
- Consequences now: module boundaries, Contracts projects and schema ownership must be respected from the first slice.
- Consequences in 12 months: fiscal rules concentrated in two domain models; CRUD and reporting stay cheap; the payment gateway arrives as an isolated adapter.
- Reversibility: high — a module can be extracted later because it already owns its schema and public contracts.

## Decision
We will build LocalTax as a **modular monolith** on .NET 10 with six modules, each owning its SQL Server schema and exposing only a Contracts project: `TaxpayerRegister` (supporting, `pure-slices`), `Taxation` (core, `sliced-domain`), `Receivables` (core, `sliced-domain`), `Enforcement` (supporting, `sliced-domain`), `Reporting` (supporting, `pure-slices`, `table-module`), `OnlinePayments` (generic, `hexagonal-integration`, planned boundary with no slices until the gateway contract exists). Declaration and assessment stay in one module because assessment needs every asset attribute; the fiscal account (debits, receipts, penalties, allocation order) is a separate consistency boundary in `Receivables`. System conventions: minimal APIs with endpoints in the slice, direct handler dispatch, `Result<T>` + ProblemDetails, FluentValidation, Dapper for reads and writes, EF Core only in the Migrations project, `TimeProvider` everywhere, xUnit + LocalDB + NetArchTest, React/TypeScript front end sliced by the same modules.

## Consequences
- Positive: the three regulated calculations live in two unit-testable domain models; legally dated rates are resolved through `TimeProvider`; CRUD and reporting modules carry no layering tax; module extraction stays possible.
- Negative / accepted trade-off: `sliced-domain` has no compiler-enforced layer boundary — the dependency direction is enforced by architecture tests (R-004) instead of project references, and must be upgraded to `clean-sliced` if a second driving adapter (batch jobs, messaging) appears for `Taxation` or `Receivables`.
- Negative / accepted trade-off: choosing Dapper for writes means aggregates are persisted by hand-written module-internal repositories; EF Core is kept solely to generate migrations, which costs one migrations-only `DbContext` that must not leak into runtime code (R-005).
- Negative / accepted trade-off: `Reporting` reads across schemas through read-only views — a standing exception to R-002, recorded in `exceptions[]`.
- CQRS `separate-stores` (materialized read models fed by the outbox) is rejected for now: no measured read load. Revisit with numbers.
- Enforcement:

| Rule | Enforcement |
|---|---|
| R-001 modules only via Contracts | test `R001_Modules_reference_other_modules_only_through_contracts` |
| R-002 no cross-schema joins in write paths | review (exception: Reporting views) |
| R-003 Contracts purity | test `R003_Contracts_contain_no_domain_or_infrastructure_types` |
| R-004 domain purity in sliced-domain | test `R004_Domain_does_not_reference_features_or_infrastructure` |
| R-005 EF Core only in Migrations | test `R005_EfCore_is_referenced_only_by_migrations_project` |
| R-006 fiscal rules in Domain | review |
| R-007 dated rates, no `DateTime.Now/UtcNow` | test `R007_No_ambient_clock_outside_composition_root` |
| R-008 Money / decimal(19,2) | test `R008_Monetary_values_use_Money` |
| R-DB-01 / R-DB-02 | review |
| `consumes` declarations | test `Module_references_match_declared_consumes` |
| `request_dispatch: direct` | test `No_mediator_package_is_referenced` |
| slice hygiene | test `Slices_do_not_reference_other_slices_handlers` |
| visibility | test `Only_module_entry_point_and_contracts_are_public` |
| `db_schema` ownership | test `Each_module_uses_only_its_own_schema` |

Per-recipe test strategy: `sliced-domain` modules require aggregate unit tests for every invariant and transition plus one integration test per slice; `pure-slices` modules require an integration test per slice against SQL Server; `hexagonal-integration` requires mapper contract tests and a faked-gateway adapter test.

## Profile diff
```yaml
# .ai/architecture/profile.yml — created from the template (status: draft)
system: { name: LocalTax, root_namespace: LocalTax, topology: modular-monolith, frontend: react-ts }
shared_kernel: { project: LocalTax.SharedKernel, allowed: [Result, Error, Money, Cnp, Cui, FiscalYear, "strongly-typed ids base"] }
modules:
  - { name: TaxpayerRegister, subdomain: supporting, recipe: pure-slices,           db_schema: taxpayers }
  - { name: Taxation,         subdomain: core,       recipe: sliced-domain,         db_schema: taxation }
  - { name: Receivables,      subdomain: core,       recipe: sliced-domain,         db_schema: receivables }
  - { name: Enforcement,      subdomain: supporting, recipe: sliced-domain,         db_schema: enforcement }
  - { name: Reporting,        subdomain: supporting, recipe: pure-slices,           db_schema: reporting }
  - { name: OnlinePayments,   subdomain: generic,    recipe: hexagonal-integration, db_schema: onlinepayments }
rules: [R-001, R-002, R-003, R-004, R-005, R-006, R-007, R-008, R-DB-01, R-DB-02]
exceptions:
  - { rule: R-002, scope: "Reporting (read-only views over other schemas)", adr: docs/adr/0001-architecture-baseline.md, expires: null }
```

## Links
- Profile: `.ai/architecture/profile.yml` (status: draft until this ADR is accepted)
- Plan: none yet
- Related ADRs: none
