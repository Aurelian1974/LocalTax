## Claude Code specifics
- The main session is the orchestrator for M/L/XL work: follow skill `orchestration`, delegate with the Agent tool to `claude-<role>` subagents (`.claude/agents/`). Subagents have their skills preloaded.
- S-class changes: do them directly, then run build and affected tests.
- Do not use auto-memory for project decisions; write them to `.ai/` so Copilot sees them.
