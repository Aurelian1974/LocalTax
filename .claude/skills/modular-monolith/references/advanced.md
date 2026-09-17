# Modular Monolith — advanced topics

## Integration event versioning
- Additive changes (new optional field) keep the name; consumers ignore unknown fields.
- Breaking changes → new type `InvoiceIssuedV2`; publisher emits both until all consumers migrate; ADR records the sunset date.
- Never reuse a removed field name with a different meaning.

## Process manager / saga (in-process)
- Lives in the module that owns the business process (e.g. Invoicing owns "issue & submit").
- State table in the owner's schema: `ProcessId, Step, Status, LastEventId, TimeoutAt`.
- Reacts to events, issues commands via contracts/events, handles timeouts via scheduled check.
- Every step idempotent; compensation defined for each step that has external effects.

## Module-level authorization
- Permissions namespaced `{M}.{Action}`; policies registered by the module's `Add{M}Module`.
- Query contracts enforce data scope (company/tenant) themselves; callers cannot bypass by passing ids.

## Shared kernel governance
- Changes to SharedKernel require review from all module owners (CODEOWNERS).
- Candidates: Result/Error, Money/Currency, fiscal identifiers (CUI/CNP) with validation, typed id base.
- Not candidates: entities, DTOs, "helpers", enums of one module's states.

## Per-module performance isolation
- Separate `DbContext` pools per module; connection resiliency configured per module.
- Heavy reporting runs on a readable secondary or snapshot isolation to avoid blocking write modules.
