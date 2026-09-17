---
name: architecture-docs
description: Rules for ADRs, the architecture profile, plans and orchestration state.
globs: docs/adr/**,.ai/architecture/**,.ai/plans/**,.ai/state/**
---
# Architecture documents

- ADRs follow skill `adr` and `adr/assets/adr-template.md`; accepted ADRs are never edited, only superseded.
- `profile.yml` changes require an ADR reference in the same change; keep `exceptions[]` time-boxed.
- Plans follow `.ai/templates/plan.md`; tables and rule ids, no prose; no step may contain "TBD", "decide", "consider" or "maybe".
- Write facts, numbers and decisions. No marketing language, no filler.
- State `.ai/state/current.md`: change only via `pwsh scripts/Set-AiState.ps1`; never edit the file.
