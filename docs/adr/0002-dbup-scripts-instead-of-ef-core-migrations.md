# 0002 — Use DbUp SQL scripts for schema changes and remove EF Core from the solution

- **Status:** proposed
- **Date:** 2026-09-17
- **Deciders:** product owner, dev team (1–3 devs)
- **Modules:** all (system-wide convention)
- **Axes:** none (A1–A8 unchanged); `conventions.data_access` / `conventions.migrations` only

## Context
| Force | Evidence |
|---|---|
| Runtime data access | ADR-0001 fixed Dapper for reads **and** writes; no module uses `DbContext` at runtime (`profile.yml conventions.data_access`) |
| Cost of EF-only-for-migrations | one migrations-only `DbContext` plus entity configurations must be written and kept in sync with hand-written Dapper persistence — a second, non-authoritative model of the same schema |
| Schema authority | the database is applied by the user (`database.apply: user`, R-DB-01); agents may only produce SQL files. EF's value (generated diffs applied by `dotnet ef database update`) is unusable under that constraint |
| Review requirement | `sql-server-data-access` already requires every migration to be reviewed as SQL; with EF that means generating a script from a model the team does not otherwise use |
| SQL features needed | schemas per module, read-only cross-schema views for `Reporting`, indexes, check constraints, seed of legally dated rate tables — all expressed directly in T-SQL |
| Repo state | greenfield: no migration has been written yet, so the change costs nothing to make now |

## Options
### Option 1 — Keep EF Core as migrations-only tool (status quo, ADR-0001)
- Consequences now: one extra project, a `DbContext` + configurations duplicating the Dapper mapping, an architecture test (R-005) whose whole job is to stop EF leaking into runtime code.
- Consequences in 12 months: the migrations model drifts from the real schema (nobody executes it); expand/contract steps, views and seed data still end up as raw SQL inside `migrationBuilder.Sql(...)`; EF packages remain in the dependency graph and invite "just this one query with EF".
- Reversibility: high while greenfield, lower once migrations exist.

### Option 2 — DbUp journaled SQL scripts, no EF Core anywhere *(chosen)*
- Consequences now: `db/migrations/NNNN-<slug>.sql` are the schema; a small DbUp runner project applies them; the R-005 test becomes a stronger, simpler rule (no EF reference at all).
- Consequences in 12 months: one authoritative artefact per schema change, reviewable and runnable by the user in SSMS; full T-SQL available; no ORM model to keep in sync.
- Reversibility: medium — returning to EF migrations means baselining the existing schema, which is the normal EF onboarding path.

### Option 3 — SSDT `.sqlproj` state-based deployment
- Consequences now: model-based deploys fit "user applies the schema" poorly (dacpac + SqlPackage on every environment), and generated diffs for data-carrying tables need manual pre/post scripts anyway.
- Consequences in 12 months: strong drift detection, but tooling weight and Windows/SqlPackage coupling for a 1–3 dev team.
- **Rejected:** heavier than the problem; DbUp's ordered scripts match how the schema is actually applied here.

## Decision
We will apply every schema change as a numbered, idempotent T-SQL script under `db/migrations/`, executed by DbUp with a journal table, and remove Entity Framework Core from the solution entirely: no package reference, no `DbContext`, no migrations project. Runtime data access stays Dapper over `IDbSession`/`ISqlConnectionFactory` for reads and writes. Agents write scripts only; the user runs them (R-DB-01 unchanged). This supersedes the migrations part of ADR-0001 (`conventions.migrations: ef-core-migrations`, the migrations-only `DbContext` trade-off and the old wording of R-005); every other decision in ADR-0001 stands.

## Consequences
- Positive: one model of the schema instead of two; the reviewed artefact and the executed artefact are the same file; full T-SQL (schemas, views, filtered indexes, seed of dated rate tables) without escape hatches.
- Positive: R-005 becomes absolute — "no EF Core reference in any project" is a cheaper and stricter test than "EF Core only in the Migrations project".
- Negative / accepted trade-off: no generated diff and no compile-time check that the C# mapping matches the schema; drift is caught by integration tests against LocalDB, which every slice already requires (ADR-0001 test strategy).
- Negative / accepted trade-off: script ordering and idempotency are the developer's responsibility; expand/contract sequencing must be written by hand per `sql-server-data-access`.
- Enforcement:

| Rule | Enforcement |
|---|---|
| R-005 (new text) no EF Core in any project | test `R005_No_project_references_EfCore` (replaces `R005_EfCore_is_referenced_only_by_migrations_project`) |
| R-DB-01 agents never apply migrations | review (unchanged) |
| script naming/idempotency in `db/migrations` | review |

## Profile diff
```yaml
# .ai/architecture/profile.yml — before → after
conventions:
  data_access:
-   orm: ef-core
+   orm: none
    write: dapper
    read: dapper
- migrations: ef-core-migrations   # EF Core exists ONLY in the Migrations project (R-005)
+ migrations: dbup                 # numbered T-SQL scripts in db/migrations, journaled by DbUp
rules:
  - id: R-005
-   text: "Entity Framework Core is referenced only by the Migrations project; runtime data access is Dapper."
+   text: "No Entity Framework Core anywhere: data access with Dapper over IDbSession/ISqlConnectionFactory; schema changes only as DbUp scripts."
    enforce: test
```

## Links
- Profile: `.ai/architecture/profile.yml`
- Plan: none
- Related ADRs: supersedes the migrations decision in `docs/adr/0001-architecture-baseline.md`
