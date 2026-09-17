---
name: clean-architecture
description: Rules and implementation guidance for Clean Architecture and its siblings Hexagonal (Ports & Adapters) and Onion in .NET — dependency rule, project layout, ports, adapters, composition root, and the anti-patterns that turn it into ceremony. Use when working in a module whose recipe is clean-sliced or hexagonal-integration, when adding ports/adapters, when a dependency direction is questioned, or when someone proposes adding layers.
user-invocable: false
---
# Clean Architecture (and Hexagonal / Onion)

## The one rule
Source-code dependencies point inward, toward policy. Domain knows nothing; Application knows
Domain; Infrastructure and delivery know Application. Everything else is a consequence.

## Layers in this kit
| Layer | Contains | May reference | Must not reference |
|---|---|---|---|
| Domain | aggregates, entities, value objects, domain events, domain services, domain errors | SharedKernel | Dapper, SqlClient, ASP.NET, MediatR, logging, HttpClient, Application |
| Application | slices (commands/queries/handlers/validators/responses), repository interfaces per aggregate*, ports for driven dependencies, event handlers | Domain, Contracts, SharedKernel (`IDbSession`), FluentValidation, abstractions (`ILogger<T>`, `TimeProvider`) | Infrastructure, SQL, external SDKs |
| Infrastructure | Dapper repositories, read-model queries, adapters, outbox writer, module registration | Application, Domain, any library | — |
| Contracts | integration events, exposed query interfaces & DTOs | SharedKernel primitives | Domain, Application, Infrastructure |

\* One interface per aggregate root (`IAssessmentRepository`: `GetAsync`, `AddAsync`, `SaveAsync`), implemented with
Dapper in Infrastructure, sharing the use case's `IDbSession` transaction. Queries do not use repositories.

## Ports: when to create one
Create a port (interface in Application) only for a **driven** dependency that satisfies at least one:
- it crosses a process boundary (HTTP API, ANAF, email, file storage, message broker)
- a second implementation exists or is planned with a date (provider switch, sandbox vs production)
- the real thing cannot run in tests (paid API, hardware)
Name ports in the module's language: `IInvoiceSubmissionGateway`, not `IAnafHttpClient`.
Never create ports for: read queries (slices use `ISqlConnectionFactory` directly), logging,
time (`TimeProvider` exists), configuration (`IOptions<T>`).

## Hexagonal view (same rule, different vocabulary)
- **Driving adapters** (left side): endpoints, jobs, message consumers → call use cases (slices).
- **Driven ports/adapters** (right side): Application declares the port; Infrastructure implements.
- An **anti-corruption layer** is a driven adapter that also translates a foreign model. External
  DTOs never cross into Application. See `references/hexagonal-onion.md`.

## Composition root
Each module exposes `Add{M}Module(this IServiceCollection, IConfiguration)` and
`Map{M}Module(this IEndpointRouteBuilder)` in Infrastructure. The Host calls only these.
Internal types stay `internal`; tests get `InternalsVisibleTo`.

## Transactions and side effects
- One use case = one transaction = one aggregate modified (see `ddd-tactical`).
- Domain events are collected on aggregates and dispatched in the same transaction (in-module)
  by the repository's `SaveAsync`, or converted into integration events written to the outbox, before `session.CommitAsync`.
- No external calls inside the transaction; use outbox → adapter.

## Anti-patterns
| Symptom | Why it's wrong | Fix |
|---|---|---|
| `IRepository<T>` + `Repository<T>` | generic CRUD hides intent and invariants | aggregate-specific repository with intent-revealing methods; queries bypass repositories |
| DTO ↔ Entity ↔ ViewModel mapper chains | three copies of the same shape | map once at the slice boundary; query side projects directly to Response |
| `Services/` in Application with `InvoiceService` | transaction-script disguised as Clean; slices lose cohesion | move logic to aggregate (rules) or slice handler (orchestration) |
| Domain referencing `System.ComponentModel.DataAnnotations` | persistence/UI concern in domain | validators in slices + invariants in aggregates |
| Interfaces for every class | test mocks drive design, not seams | apply "ports: when to create one" |
| Application referencing Infrastructure "just for one type" | breaks the rule silently | move the type or introduce a port |

## Checks before finishing a change in a clean module
- [ ] No new project reference against the dependency rule (architecture tests green)
- [ ] New interfaces satisfy the port criteria
- [ ] Business rule added to Domain, not handler/endpoint/SQL
- [ ] External shapes stopped at the adapter
