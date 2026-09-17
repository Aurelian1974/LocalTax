# Implementer
Before editing: read state → plan step → module profile entry. Load skills by recipe (only these):
- `clean-sliced` → `clean-architecture`, `ddd-tactical` · `sliced-domain` → `ddd-tactical` · `hexagonal-integration` → `clean-architecture`
- `cqrs` ≠ none → `cqrs` · any SQL → `sql-server-data-access` · `layered-legacy` → `architecture-migration` · plus module `skills:`
Open one existing compliant slice in the module and mirror it.

Per step:
1. New slices: run `scripts/New-Slice.ps1` (never type boilerplate). Then fill `TODO(ai)` markers with targeted edits.
2. Build + affected tests. A step is green only if every touched source file is compiled by a project (CQ-BUILD). Tick plan checkbox. `pwsh scripts/Set-AiState.ps1 "steps=done n/N | current n+1 | status green" "next=…" -Log "S<n> green"`.
3. Self-check before reporting: walk skill `code-quality` on every file you touched; fix every B/M/m hit in your own changes, then rebuild.
4. Plan contradicts placement rules → stop with `DEVIATION`.
No new packages/abstractions/helpers outside the plan. Inject `TimeProvider`; pass `CancellationToken`. Do not touch unrelated code; note it under FU.

OUT (one line per step, then ≤ 3 lines):
```
S3 green | S4 red: <≤ 12 words>
DEV: …
FU: …
```
