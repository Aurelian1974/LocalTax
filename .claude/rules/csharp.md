---
name: csharp-standards
description: "C# / .NET coding standards applied to all C# files."
applyTo: "**/*.cs"
paths:
  - "**/*.cs"
---
<!-- GENERATED from .ai/kit by scripts/Build-AiKit.ps1 — edit the sources, not this file -->
# C# standards

- Target the runtime in `profile.yml`; use current language features where they reduce noise
  (primary constructors for DI, collection expressions, `required`, file-scoped namespaces, raw strings for SQL).
- Types: `sealed` by default; `internal` by default inside modules; public types only for Contracts and `{M}Module`.
- Members forming a type's API are `public`, also inside `internal` types; `internal`/`private` only to restrict below the type.
- No `using` covered by implicit usings or `global using`; file-scoped namespaces matching the folder.
- Nullable reference types enabled; no `!` suppression without a comment stating the invariant.
- Async all the way: `Async` suffix, `CancellationToken ct` as last parameter and passed through; no `.Result`/`.Wait()`.
- Time: injected `TimeProvider.GetUtcNow()`; instants are UTC `DateTimeOffset`, dates are `DateOnly`. Never `GetLocalNow()`/`DateTime.Now` in business code; convert to a named zone only at the presentation boundary.
- Ids via `Guid.CreateVersion7()` or strongly-typed ids.
- Expected failures → `Result`/`Error` (when profile `error_model: result`); exceptions for faults only.
- Records for commands, queries, responses, events, value objects. No mutable DTOs.
- Logging: structured templates (`"Invoice {InvoiceId} issued"`), no string interpolation, no personal data.
- No `static` mutable state, no service locator (`IServiceProvider` in business code).
- Data access: Dapper with `CommandDefinition` (parameters, `session.Transaction`, `cancellationToken`); no Entity Framework Core; SQL in raw string literals with explicit columns.
- Names: business language from the module; no `Manager`, `Helper`, `Util`, `Processor` suffixes.
- Comments explain why, not what. XML docs only on Contracts.
- Before finishing any change, apply skill `code-quality` to the touched files.
