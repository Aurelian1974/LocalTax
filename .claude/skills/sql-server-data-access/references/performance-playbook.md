# SQL Server Performance Playbook

## 1. Reproduce
- Capture the exact statement + parameters (Query Store, XE `rpc_completed`, app logs with parameter values redacted appropriately).
- Run in SSMS with `SET STATISTICS IO, TIME ON;` and *Include Actual Execution Plan*.
- Compare with `OPTION (RECOMPILE)` run: large difference → parameter sensitivity.

## 2. Read the plan (in this order)
1. Highest-cost operator by *actual* rows and logical reads, not estimated cost %.
2. Estimated vs actual rows off by 10x+ → statistics, predicates on expressions, table variables, multi-statement TVFs.
3. Warnings: implicit conversion, missing index, spill to tempdb, residual predicates.
4. Key lookups with high execution counts → covering index (`INCLUDE`).
5. Scans on large tables in OLTP paths → missing/unused index or non-SARGable predicate.
6. Parallelism on OLTP queries → usually a symptom of a missing index.

## 3. Fix order
1. Rewrite predicate (SARGable, correct types, split OR into UNION ALL when beneficial).
2. Index (design per §6 of SKILL.md), statistics update, filtered stats.
3. Parameter sensitivity: SQL Server 2022 PSP optimization, `OPTIMIZE FOR`, plan guides/Query Store hints — record why.
4. Hints (`FORCESEEK`, `MAXDOP`) last, with ADR-level justification for long-lived code.

## 4. Useful queries
```sql
-- Top resource queries last 24h (Query Store)
SELECT TOP (20) qt.query_sql_text, rs.avg_logical_io_reads, rs.avg_duration/1000.0 AS avg_ms, rs.count_executions
FROM sys.query_store_runtime_stats rs
JOIN sys.query_store_plan p ON p.plan_id = rs.plan_id
JOIN sys.query_store_query q ON q.query_id = p.query_id
JOIN sys.query_store_query_text qt ON qt.query_text_id = q.query_text_id
WHERE rs.last_execution_time > DATEADD(HOUR, -24, SYSUTCDATETIME())
ORDER BY rs.avg_logical_io_reads * rs.count_executions DESC;

-- Unused indexes (since last restart)
SELECT OBJECT_SCHEMA_NAME(i.object_id) AS [schema], OBJECT_NAME(i.object_id) AS [table], i.name,
       us.user_seeks, us.user_scans, us.user_lookups, us.user_updates
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats us ON us.object_id = i.object_id AND us.index_id = i.index_id AND us.database_id = DB_ID()
WHERE i.type_desc = 'NONCLUSTERED' AND OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
ORDER BY COALESCE(us.user_seeks + us.user_scans + us.user_lookups, 0), us.user_updates DESC;
```

## 5. Report format
```
SYMPTOM: <query/use case, p95, reads>
ROOT CAUSE: <plan evidence>
FIX: <change> — EXPECTED: <reads/duration after, measured>
WRITE COST / RISK: <for indexes and hints>
```
