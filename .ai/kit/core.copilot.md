## GitHub Copilot specifics
- Agents: `.github/agents/` — `orchestrator` coordinates; specialists run as subagents via the `agent` tool.
- Skills are read from `.claude/skills/` (shared with Claude Code). Load a skill by reading its `SKILL.md` when its description matches.
- No `agent` tool available (e.g. Visual Studio) → orchestrator runs phases sequentially per skill `orchestration`.
