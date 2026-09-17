# Placement Rules per Recipe

Paths use `{Root}` = `system.root_namespace`, `{M}` = module name, `{Feature}` = capability or
aggregate grouping (e.g. `Invoices`), `{UseCase}` = verb-noun (e.g. `IssueInvoice`).
Topology `monolith` omits the `Modules/` level.

## Contents
1. clean-sliced
2. sliced-domain
3. pure-slices
4. hexagonal-integration
5. Module contracts (all recipes, modular-monolith)
6. Host / composition root
7. Tests
8. "Where does X go?" lookup table

---

## 1. clean-sliced
```
src/Modules/{M}/
  {Root}.Modules.{M}.Domain/            ← no references except SharedKernel
    {Aggregate}/  {Aggregate}.cs, {Aggregate}Id.cs, value objects, domain events, errors
    Services/     domain services (pure, no I/O)
  {Root}.Modules.{M}.Application/       ← references Domain, Contracts, SharedKernel
    Features/{Feature}/{UseCase}/
      {UseCase}Command.cs | {UseCase}Query.cs
      {UseCase}Handler.cs
      {UseCase}Validator.cs
      {UseCase}Response.cs              (query read models live here, not in Domain)
      {UseCase}Endpoint.cs              ← only if endpoint_placement: slice (Application references AspNetCore abstractions)
    Abstractions/                        ports for driven dependencies ONLY (e.g. IEFacturaGateway, IDocumentStorage)
    EventHandlers/                       handlers for domain events raised in this module
    IntegrationEventHandlers/            consumers of other modules' events
  {Root}.Modules.{M}.Infrastructure/    ← references Application, Domain
    Persistence/  {Aggregate}Repository.cs (Dapper), {Aggregate}Row records, Outbox writer
    ReadModels/   Dapper/SP-based query implementations for separate-models CQRS
    Adapters/     implementations of Application/Abstractions
    Outbox/
    {M}Module.cs                         DI registration + endpoint mapping entry point
  {Root}.Modules.{M}.Contracts/         ← references nothing but SharedKernel primitives
```
Dependency rule: Domain ← Application ← Infrastructure; Contracts referenced by Application of
this module and by other modules. Host references only `{M}Module` (Infrastructure) and Contracts.

## 2. sliced-domain
```
src/Modules/{M}/
  {Root}.Modules.{M}/                   single project
    Domain/{Aggregate}/                  same content as clean-sliced Domain; NO using of Features, Infrastructure, Dapper, SqlClient, AspNetCore
    Features/{Feature}/{UseCase}/        Command/Query, Handler, Validator, Response, Endpoint
    Infrastructure/Persistence/          {Aggregate}Repository.cs (Dapper), row records
    Infrastructure/Adapters/             only if a real external dependency exists
    {M}Module.cs
  {Root}.Modules.{M}.Contracts/
```
Rules enforced by architecture tests instead of project references:
`Domain` must not depend on `Features`, `Infrastructure`, `Dapper`, `Microsoft.Data.SqlClient`, `Microsoft.AspNetCore`.

## 3. pure-slices
```
src/Modules/{M}/
  {Root}.Modules.{M}/
    Features/{Feature}/
      {UseCase}.cs                       single file: request, response, validator, handler, endpoint (nested/static classes)
      — or a folder per use case when the file exceeds ~200 lines —
    Data/                                SQL constants shared by ≥ 3 slices, SP wrappers
    {M}Module.cs
  {Root}.Modules.{M}.Contracts/          only when topology is modular-monolith
```
Handlers use Dapper directly (`IDbSession` for writes, `ISqlConnectionFactory` for reads). No repositories, no Domain folder. Business rules live in the
handler (transaction script) or in SQL (table-module, reporting).

## 4. hexagonal-integration
```
src/Modules/{M}/
  {Root}.Modules.{M}/
    Features/{UseCase}/                  driving side: endpoint / job / event handler → use case
    Ports/                               driven ports expressed in the module's language (IInvoiceSubmissionGateway)
    Adapters/{ExternalSystem}/           implementation + external DTOs + mapping (anti-corruption layer)
      Dtos/                              external shapes — internal visibility, never referenced outside Adapters
      {ExternalSystem}Client.cs, {ExternalSystem}Mapper.cs, Resilience policies
    Data/                                persistence of integration state (submissions, attempts, message ids)
    {M}Module.cs
  {Root}.Modules.{M}.Contracts/
```
External DTO types must not appear in Features, Ports or Contracts.

## 5. Module contracts — `*-CONTRACTS` (modular-monolith)
`{Root}.Modules.{M}.Contracts` contains only:
- integration events: immutable records of primitives / SharedKernel types, past-tense names, versioned when changed
- query interfaces exposed to other modules (`IPartnerLookup`) + their DTOs
- nothing referencing Domain, Dapper, SqlClient, AspNetCore
Implementation of exposed queries lives inside the module (Infrastructure/ReadModels or Features).

## 6. Host / composition root — `*-HOST`
```
src/{Root}.Host/   Program.cs → builder.Services.Add{M}Module(config); app.Map{M}Module();
                   cross-cutting: auth, ProblemDetails, logging, OpenTelemetry, outbox dispatcher
```
The host contains no business code and no endpoints when `endpoint_placement: slice`.

## 7. Tests (`*-TESTS`)
```
tests/
  {Root}.ArchitectureTests/                    generated from profile
  Modules/{M}/{Root}.Modules.{M}.UnitTests/     Domain (domain-model recipes only)
  Modules/{M}/{Root}.Modules.{M}.IntegrationTests/   Features/{Feature}/{UseCase}Tests.cs
```

## 8. "Where does X go?"

Rule id = `<recipe code>-<Key>` (e.g. `CS-HANDLER`, `PS-SP`). Plans and reviews cite ids instead of repeating rules.

| Key | Artifact | clean-sliced (CS) | sliced-domain (SD) | pure-slices (PS) | hexagonal-integration (HX) |
|---|---|---|---|---|---|
| `RULE` | Invariant / business rule | Aggregate method (Domain) | Aggregate method (Domain/) | Handler | Use case handler |
| `XRULE` | Rule spanning aggregates, no I/O | Domain service | Domain/ service | Handler | Handler |
| `VALIDATOR` | Input validation (shape, required) | Validator in slice | Validator in slice | Validator in slice file | Validator in slice |
| `HANDLER` | Use-case orchestration | Handler (Application) | Handler (Features) | Handler | Handler |
| `ENDPOINT` | HTTP endpoint | slice or Host (per convention) | slice | slice file | slice |
| `RESPONSE` | Read model / query DTO | Application slice Response | slice Response | slice file | slice |
| `QUERYIMPL` | Query implementation (separate-models) | Infrastructure/ReadModels | Features (Dapper inline) | Handler | Handler |
| `PERSIST` | Aggregate repository / SQL mapping | Infrastructure/Persistence | Infrastructure/Persistence | inline in handler | Data/ |
| `MIGRATION` | Schema change (DbUp script) | db/migrations | db/migrations | db/migrations | db/migrations |
| `SP` | Stored procedure | Infrastructure (read side only) | Infrastructure (read side only) | Data/ (logic allowed) | Data/ |
| `EXTCLIENT` | External API client | Infrastructure/Adapters via Application/Abstractions port | Infrastructure/Adapters (port only if 2nd impl/test seam) | Data/ or inline typed HttpClient | Adapters/{System} via Ports/ |
| `DOMEVENT` | Domain event | Domain/{Aggregate} | Domain/{Aggregate} | — | — |
| `INTEVENT` | Integration event (published) | Contracts | Contracts | Contracts | Contracts |
| `CONSUMER` | Integration event handler (consumed) | Application/IntegrationEventHandlers | Features/…/On{Event}.cs | Features/…/On{Event}.cs | Features/On{Event}/ |
| `JOB` | Background job | slice (driving adapter) | slice | slice | slice |
| `MAPPING` | Mapping domain → response | Handler or Response.From(…) | same | inline | Adapter mapper (external), inline (internal) |
| `AUTHZ` | Authorization policy | endpoint in slice + policy in Host | same | same | same |
| `OPTIONS` | Configuration options | Infrastructure/{M}Options | {M}Options at module root | module root | Adapters/{System}/Options |
