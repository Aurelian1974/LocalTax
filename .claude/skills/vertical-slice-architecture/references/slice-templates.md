# Slice templates

Executable templates live in `.claude/skills/feature-scaffold/assets/templates/` and are instantiated by
`scripts/New-Slice.ps1` (see skill `feature-scaffold`). Do not copy code from documentation; generate.

| Template | Recipe | Kind |
|---|---|---|
| `multi/command/*` | clean-sliced, sliced-domain, hexagonal-integration | command: Command, Validator, Handler (`IDbSession` transaction), Endpoint |
| `multi/query/*` | same | query: Query, Response, Handler (Dapper via `ISqlConnectionFactory`), Endpoint |
| `multi/consumer/*` | same | integration event consumer with idempotency |
| `single/command`, `single/query` | pure-slices | nested request/response/endpoint/handler in one file |
