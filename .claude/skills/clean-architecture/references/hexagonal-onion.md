# Clean vs Hexagonal vs Onion — what actually differs

| Aspect | Clean | Hexagonal | Onion |
|---|---|---|---|
| Core idea | concentric policy layers, dependency rule | inside/outside with ports, symmetric driving/driven | concentric rings with domain services ring |
| Emphasis | use cases as first-class | adapters and replaceability | domain model at the center |
| Layers named | Entities, Use Cases, Interface Adapters, Frameworks | Application core, Ports, Adapters | Domain Model, Domain Services, Application Services, Infrastructure/UI |
| In this kit | `clean` macro (Domain/Application/Infrastructure) | `hexagonal` macro (Features/Ports/Adapters) | treat as `clean` |

They are one family: all enforce inward dependencies. Choose by **what dominates the module**:
- rich rules → clean (Domain gets its own project)
- external systems → hexagonal (Ports/Adapters get the structure)

## Anti-corruption layer (ACL) — implementation checklist
1. External DTOs: `internal`, in `Adapters/{System}/Dtos`, generated or hand-written to match the wire.
2. Mapper: pure functions external → module types; exhaustive handling of external status codes/enums;
   unknown values map to an explicit `Unknown` + logged, never to a default that looks valid.
3. Client: typed `HttpClient`, resilience (timeouts, retry only for idempotent operations, circuit breaker).
4. Idempotency: store external correlation ids (upload index, message id) before acting on responses.
5. Contract tests: recorded real payloads (sanitized) → mapper → expected module types.
6. The port method signature contains no external vocabulary.
