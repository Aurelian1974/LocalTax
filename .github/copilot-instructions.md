<!-- GENERATED from .ai/kit by scripts/Build-AiKit.ps1 — edit the sources, not this file -->
# AI contract

## Architecture
1. Truth: `.ai/architecture/profile.yml` + `docs/adr/`. Profile missing or `status: draft` → single-file fixes only; recommend `/choose-architecture`.
2. Before code: identify module → apply its `recipe` → place files per `.claude/skills/architecture-composition/references/placement-rules.md`.
3. Never add abstractions, packages, mediators, repositories or interfaces the profile does not call for. Never invent APIs, tables, columns, packages — verify in the repo.
4. Mirror existing profile-compliant code in the same module.
5. Business rules never in endpoints, EF configurations, UI, or SQL of `domain-model` modules.
6. Cannot comply → stop: `DEVIATION: <rule> | <why> | <options>`.
7. Work larger than one file, schema changes, new module, cross-module behavior → orchestration (`/new-feature`, protocol in skill `orchestration`).

## Tool switching (Copilot ⇄ Claude Code)
- Chat history never transfers. Durable context lives only in files: plan (`.ai/plans/`), state (`.ai/state/current.md`), ADRs, profile.
- Anything decided in chat that the plan/ADR does not contain → one line in state `decisions` before the turn ends.
- State changes only via `pwsh scripts/Set-AiState.ps1` (never edit the state file).
- `/handoff` before switching; `/resume` after. Never push as part of a handoff. Do not rely on tool-specific memory features for project decisions.

## Output economy (mandatory)
Input is cheap; output is not. Read as much as needed; write as little as possible.
1. No preamble, no restating the request, no narration of what you are about to do or just did, no closing summary.
2. Never print code or file content that is written to disk. Refer to `path:line`.
3. Change files with minimal targeted edits. Never rewrite a whole file to change part of it.
4. Boilerplate comes from scripts/templates, not from generation: `scripts/New-Slice.ps1` for slices, copy asset templates with a shell command, then edit only the placeholders/`TODO(ai)` markers.
5. Reports use the role's fixed format; omit empty fields; no prose around them.
6. Plans: tables; reference rule ids and paths instead of re-explaining rules. State: one `Set-AiState.ps1` command.
7. Subagent delegation: short pointer prompts (see skill `orchestration`); context lives in state/plan files, not in the prompt.
8. Questions: one numbered block, each with a proposed default, answerable as `1a 2b`.
9. Tests: parameterized theories over repeated methods; builders over inline setup.
10. No comments restating code; XML docs only on Contracts.
11. Artifacts (code, plans, state, ADRs, reports) in English. Chat replies in the user's language, terse.

## Done
Build without new warnings, with every touched source file compiled by a project; tests + architecture tests green; no `TODO(ai)` left in touched files; plan step ticked; state updated.

## GitHub Copilot specifics
- Agents: `.github/agents/` — `orchestrator` coordinates; specialists run as subagents via the `agent` tool.
- Skills are read from `.claude/skills/` (shared with Claude Code). Load a skill by reading its `SKILL.md` when its description matches.
- No `agent` tool available (e.g. Visual Studio) → orchestrator runs phases sequentially per skill `orchestration`.
