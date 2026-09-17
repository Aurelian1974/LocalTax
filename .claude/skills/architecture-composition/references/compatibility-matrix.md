# Compatibility Matrix — full reasoning

Legend: ✅ composes · ⚠️ composes with conditions · ❌ conflicts (same axis, or larger-scale axis forbids it)

## A3 × A4 (dependency direction × organization)
| | vertical-slices | technical-layers |
|---|---|---|
| **clean** | ✅ Projects enforce direction; slices organize inside Application. Condition: Domain stays feature-agnostic (aggregates are not per slice). | ✅ Classic, but change for one use case touches 4+ folders; acceptable only for layered-legacy. |
| **hexagonal** | ✅ Each slice is a driving adapter + use case. Driven ports shared at module level. | ⚠️ Works, but ports/adapters folders by type fragment use cases. |
| **onion** | ✅ Same as clean (onion = clean with domain services ring explicit). | ✅ legacy only |
| **layered** | ❌ in the same module: a slice that also passes through Controller→Service→Repository layers has two organizing principles. | ✅ |
| **none** | ✅ pure-slices / sliced-domain (direction enforced by tests). | ⚠️ "folders by type" without dependency rules = big ball of mud risk. |

## A4 × A6 (organization × domain logic)
| | transaction-script | table-module | domain-model |
|---|---|---|---|
| **vertical-slices** | ✅ natural fit | ✅ reporting/bulk | ✅ condition: aggregates shared below slices; slices never contain entity logic |
| **technical-layers** | ✅ (service layer) | ✅ | ⚠️ tends to anemic model: logic migrates into services |

## A3 × A6
| | transaction-script | domain-model |
|---|---|---|
| **clean** | ⚠️ empty/anemic Domain layer; justify with ≥2 adapters or migration intent | ✅ |
| **hexagonal** | ✅ integration modules | ✅ |
| **none** | ✅ | ⚠️ only with architecture tests guarding Domain/ |

## A5 × A6 (CQRS level × domain logic)
| | transaction-script | domain-model |
|---|---|---|
| **none** | ✅ | ⚠️ loading aggregates for list screens → N+1 and bloated aggregates |
| **separate-methods** | ✅ default | ✅ |
| **separate-models** | ⚠️ only if reads are complex (Dapper/views) | ✅ recommended for core modules |
| **separate-stores** | ⚠️ needs measured justification | ✅ with outbox-driven projections; eventual consistency must be acceptable to the business |

## A6 × A8 (domain logic × persistence)
| | dapper | stored-procedures | event-sourcing |
|---|---|---|---|
| **transaction-script** | ✅ | ✅ logic may live in SP (test it) | ❌ |
| **table-module** | ✅ | ✅ | ❌ |
| **domain-model** | ✅ with one repository per aggregate root, rowversion concurrency and outbox in the same transaction (skill `ddd-tactical` §Persistence) | ⚠️ read side only; writes via SP only as dumb persistence of an already-validated aggregate | ✅ |

EF Core is intentionally not an option in this kit (profile `data_access.orm: none`).

## A1 × A7/A8 (topology constraints)
| | shared DB writes | cross-schema joins (writes) | in-proc contracts | integration events + outbox |
|---|---|---|---|---|
| **monolith** | ✅ | ⚠️ | ✅ | ⚠️ optional |
| **modular-monolith** | ✅ same server, separate schemas | ❌ | ✅ | ✅ for side effects across modules |
| **microservices** | ❌ | ❌ | ❌ (network contracts only) | ✅ required |

## Cross-cutting choices (system-wide, pick once)
- **Dispatch:** direct handler injection vs mediator. Mixing is ❌. Mediator is justified only by
  pipeline behaviors you actually need (transactions, auditing, validation) that endpoint filters or
  decorators cannot provide cleanly.
- **Error model:** Result<T> vs exceptions for expected failures. Mixing for expected failures is ❌.
  Exceptions remain for unexpected faults in both.
- **Endpoint placement:** slice vs host. Mixing across modules is ⚠️ (allowed only in migration).

## Mitigations for ⚠️
Each ⚠️ used in a profile needs: the condition stated in the module `notes`, and either an
architecture test or a review rule that detects when the condition stops holding.
