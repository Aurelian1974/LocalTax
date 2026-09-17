---
name: sql-server-data-access
description: SQL Server data access standards for .NET systems — T-SQL coding rules, stored procedure contracts, Dapper data access (no EF Core) per module recipe, expand/contract migrations, index design, SARGability, parameter sniffing, isolation levels, RCSI, deadlocks, and execution plan review. Use for any .sql file, migration, stored procedure, Dapper query or repository, query performance issue, schema change, locking/deadlock problem, or when deciding where SQL logic is allowed.
user-invocable: false
---
# SQL Server Data Access

## 1. Where logic may live (from the profile)
| Module domain_logic | Business rules in SQL | SPs for writes | SPs for reads |
|---|---|---|---|
| domain-model | ❌ (constraints as last line of defense only) | ❌ (except bulk/maintenance) | ✅ |
| transaction-script | ✅ if covered by integration tests | ✅ | ✅ |
| table-module | ✅ natural home | ✅ | ✅ |

## 2. T-SQL rules
- `SET NOCOUNT ON; SET XACT_ABORT ON;` at the top of every procedure.
- Schema-qualify every object; explicit column lists; no `SELECT *` outside `EXISTS`.
- `BEGIN TRY / BEGIN TRAN … COMMIT / END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; THROW; END CATCH`.
- Types: `datetime2(3)` (or `datetimeoffset` when offset matters), `date` for dates, `decimal(19,4)` money,
  `bit` flags, `uniqueidentifier` with sequential generation (v7 from app) or `bigint` identity, sized `nvarchar(n)`.
- SARGable predicates: no functions on indexed columns, no implicit conversions (match parameter types exactly),
  date ranges as `>= @From AND < @ToExclusive`.
- Set-based over cursors/loops; `MERGE` only with `HOLDLOCK` and a reason — prefer explicit `UPDATE` + `INSERT … WHERE NOT EXISTS`.
- No `NOLOCK`. Use RCSI (database-level) for read/write contention.
- Temp tables for multi-step processing with statistics needs; table variables only for tiny sets.
- Dynamic SQL only via `sp_executesql` with parameters; whitelist identifiers with `QUOTENAME`.

## 3. Stored procedure contract
- Name `{schema}.{Entity}_{Verb}` (e.g. `reporting.SaftD406_GenerateSalesInvoices`).
- Inputs typed exactly as target columns; table-valued parameters for sets.
- One result shape per procedure (or documented multiple result sets in fixed order).
- Error signaling: `THROW 50000 + <code>` with codes documented; the app maps codes to `Error`.
- Grant `EXECUTE` to the module's DB role only.

## 4. Dapper data access (no EF Core)
- Writes: `IDbSession` — `BeginAsync` → commands with `session.Connection` + `session.Transaction` → `CommitAsync`. Uncommitted work rolls back on dispose.
- Reads: `ISqlConnectionFactory.OpenAsync` → `QueryAsync`/`QueryMultipleAsync`; no transaction.
- Always `CommandDefinition(sql, parameters, transaction, cancellationToken: ct)`.
- Parameter types match columns: strings as `DbString { Value, Length, IsAnsi }`, decimals with the column precision, dates as `DateOnly`/`DateTimeOffset` matching `date`/`datetimeoffset`.
- SQL as `const string` raw literals next to their use; explicit columns; schema-qualified names.
- Multi-row inserts: table-valued parameters (`AsTableValuedParameter`) instead of loops.
- Domain-model persistence: skill `ddd-tactical` §Persistence (repository per aggregate, rowversion, outbox in the same transaction).
- `buffered: false` only for large streaming exports.

## 5. Migrations — expand / migrate / contract
1. **Expand:** add nullable column / new table / new index `ONLINE = ON` (edition permitting); deploy app writing both.
2. **Migrate:** backfill in batches (`TOP (5000)` loops with `WAITFOR DELAY` if needed), verifiable counts.
3. **Contract:** make NOT NULL / drop old column in a later release after all readers moved.
- Large-table changes: estimate row count and lock impact; schedule; avoid size-of-data operations in peak hours.
- Every migration idempotent (`IF NOT EXISTS` / `OBJECT_ID` / `COL_LENGTH` guards).

### DbUp workflow (this kit)
- Create: `pwsh scripts/New-Migration.ps1 -Schema <db_schema> -Name <snake_case>` → `db/migrations/<yyyyMMddHHmmss>_<schema>_<name>.sql`. Timestamps keep ordering stable across branches and tools.
- DbUp journals by script name (`dbo.SchemaVersions`): an edited script never re-runs. Fixes are new scripts.
- Each script runs in its own transaction. Statements that cannot run in a transaction (`ALTER DATABASE`, full-text catalogs) go in a separate script and are flagged in the plan for manual application.
- Applying: the user runs the scripts (SSMS or the host's `Database:MigrateOnStartup` in Development, template in `.ai/templates/dotnet/Host`). Agents never apply scripts; they list them under `APPLY:`.
- Other environments: the same scripts through CI/CD or manual deployment.

## 6. Indexing
- Clustered key: narrow, static, ever-increasing when possible.
- Nonclustered for each important read predicate: equality columns first, then range, `INCLUDE` for covered columns.
- Filtered indexes for status-based queues (`WHERE Status = 'Pending'`).
- Every new index states its write cost and the queries it serves. Remove unused ones (sys.dm_db_index_usage_stats) via ADR-less maintenance plan.

## 7. Performance investigation procedure
Read `references/performance-playbook.md`. Summary: reproduce with real parameters → actual plan +
`STATISTICS IO, TIME` → look for scans with high reads, key lookups, implicit conversions, bad
estimates → Query Store for regressions/parameter sniffing → fix query first, index second, hints last.

## 8. Concurrency
- Default `READ COMMITTED` + RCSI enabled at DB level.
- Optimistic concurrency via `rowversion` on aggregate roots; map conflicts to a domain-level error.
- Sequences needing no gaps (fiscal numbering): dedicated row per series updated with `UPDLOCK, HOLDLOCK` in the same transaction as the insert; document serialization impact.
- Deadlocks: capture from `system_health` XE; fix access order and indexing before retry logic; retries only for idempotent operations.
