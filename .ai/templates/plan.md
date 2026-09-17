# Plan: <title>
id: <yyyymmdd>-<slug> | class: <type>/<size>/<impact> | modules: <Name: recipe> | adr: <ids|none> | status: draft

Goal: <1–2 lines, observable outcome>
Out of scope: <…>

## Steps
| # | Step (one vertical increment) | Scaffold | Data | Tests | Done |
|---|---|---|---|---|---|
| 1 | <use case> | `New-Slice.ps1 -Module M -Feature F -UseCase U -Kind command -Recipe r` | none | `F.UTests.Happy`, `...Rule` | [ ] |

### Files
| # | Path | Kind | Rule |
|---|---|---|---|
| 1 | src/Modules/M/.../UHandler.cs | handler | CS-HANDLER |

### Rules enforced
| # | Rule (business) | Where |
|---|---|---|
| 1 | <invariant> | `Aggregate.Method` |

## Data
| # | Change | Stage | Rollback |
|---|---|---|---|

## Risks
| Risk | Sev | Mitigation |
|---|---|---|
