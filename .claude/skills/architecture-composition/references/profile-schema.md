# Architecture Profile Schema (`.ai/architecture/profile.yml`)

| Path | Type | Used by | Meaning |
|---|---|---|---|
| `version` | int | all | schema version (1) |
| `status` | draft/active | orchestrator | draft blocks M/L/XL tasks except architecture selection |
| `system.name`, `root_namespace` | string | planner, implementer | naming and namespace roots |
| `system.topology` | enum | architect, tests | A1; constrains A7/A8 |
| `system.runtime`, `frontend`, `database` | enum | all | technology selection for skills/instructions |
| `system.adr` | path | architect | baseline ADR |
| `conventions.api_style` | enum | implementer | minimal-apis / controllers |
| `conventions.endpoint_placement` | slice/host | planner, tests | where endpoints live |
| `conventions.request_dispatch` | direct/mediator | implementer, tests | handler dispatch convention |
| `conventions.validation` | enum | implementer | validation library |
| `conventions.error_model` | result/exceptions | implementer, reviewer | expected-failure handling |
| `conventions.data_access.orm` | none | all | `none`: no EF Core; Dapper + SQL only (architecture test) |
| `conventions.data_access.write/read` | dapper/stored-procedures/views | db-engineer, implementer | default A8; modules may override in notes with ADR |
| `conventions.migrations` | dbup | db-engineer | DbUp .sql scripts |
| `database.name/server/auth` | string | agents (informational) | the database you created; agents never connect to it |
| `database.migrations_path` | path | New-Migration.ps1, host | DbUp script folder |
| `database.apply` | user/host-startup-dev | db-engineer, implementer | who applies scripts; agents never apply them |
| `conventions.time` | enum | implementer | clock abstraction |
| `conventions.testing.*` | enum | test-engineer | frameworks |
| `shared_kernel.project/allowed` | list | tests, reviewer | only these types are shareable across modules |
| `modules[].name` | string | all | module identity (PascalCase) |
| `modules[].purpose` | string | architect, researcher | capability owned — used to reject misplaced features |
| `modules[].subdomain` | core/supporting/generic | architect | drives recipe choice |
| `modules[].recipe` | enum | all | named composition (see SKILL.md §2) |
| `modules[].macro/organization/domain_logic/cqrs` | enum | all | explicit A3/A4/A6/A5 values |
| `modules[].db_schema` | string | db-engineer, tests | data ownership |
| `modules[].exposes.*` | lists | planner, reviewer, tests | public surface; everything else internal |
| `modules[].consumes` | list | reviewer, tests | declared dependencies; undeclared usage = BLOCKER |
| `modules[].skills` | list | implementer | extra domain skills to load |
| `modules[].notes` | string | all | conditions for ⚠️ combinations, invariants worth stating |
| `rules[]` | id/text/enforce | tests, reviewer | repo-specific rules |
| `exceptions[]` | rule/scope/adr/expires | reviewer, tests | time-boxed, ADR-backed deviations |

## Validation rules
- `recipe` and axis values must agree with the recipe table unless `notes` justifies the override.
- Every `consumes` entry must exist in the target module's `exposes`.
- `topology: microservices` requires every `consumes` to be an integration event or network API.
- `exceptions[].adr` must point to an existing ADR; expired exceptions are review BLOCKERs.
