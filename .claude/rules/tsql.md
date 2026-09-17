---
name: tsql-standards
description: "T-SQL standards for SQL scripts, stored procedures and migrations."
applyTo: "**/*.sql"
paths:
  - "**/*.sql"
---
<!-- GENERATED from .ai/kit by scripts/Build-AiKit.ps1 — edit the sources, not this file -->
# T-SQL standards

Full guidance: skill `sql-server-data-access`. Always:
- `SET NOCOUNT ON; SET XACT_ABORT ON;` in procedures; TRY/CATCH with `THROW`.
- Schema-qualified names; explicit column lists; no `SELECT *`; no `NOLOCK`.
- Types match target columns exactly; date ranges as `>= start AND < endExclusive`.
- `datetime2`, `decimal(19,4)` for money, sized `nvarchar(n)`.
- Idempotent DDL (`IF NOT EXISTS` / `CREATE OR ALTER`); migrations follow expand → migrate → contract.
- Dynamic SQL only through `sp_executesql` with parameters; identifiers via `QUOTENAME` + whitelist.
- A module's scripts touch only its own schema (`db_schema` in profile), except Reporting read-only views with an exception.
- Business rules in SQL only for modules whose `domain_logic` is not `domain-model`.
