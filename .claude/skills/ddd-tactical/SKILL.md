---
name: ddd-tactical
description: DDD tactical design in .NET — aggregates and consistency boundaries, invariants, value objects, strongly-typed ids, domain events vs integration events, domain services, factories, repositories, and Dapper persistence of aggregates that keeps the model persistence-ignorant. Use whenever code touches a module with domain_logic domain-model, when adding business rules, entities or state transitions, or when an entity has public setters and logic lives in handlers.
user-invocable: false
---
# DDD Tactical Patterns

## Aggregates — the decisions that matter
1. **An aggregate is a consistency boundary**, not an object graph. It contains exactly what must be
   consistent in one transaction to protect an invariant.
2. **Small aggregates.** Start with root + value objects; add child entities only when an invariant
   spans them (invoice lines belong to the invoice because totals/VAT must be consistent).
3. **Reference other aggregates by id** (`PartnerId`), never by navigation property.
4. **One aggregate modified per transaction.** Other aggregates react to domain events — in the same
   module synchronously in the same transaction only if the business requires atomicity; otherwise
   eventually.
5. **All changes go through methods named in business language** (`Issue`, `Cancel`, `AddLine`).
   No public setters. Constructors/factories produce only valid instances.

## Designing an aggregate (procedure)
1. List invariants as sentences: "An issued invoice cannot change its lines." "The sum of lines
   equals the total." "Numbers are sequential within a series and year."
2. For each invariant, find the smallest set of data required to check it → that set is the aggregate.
3. Invariants that need data from many instances (uniqueness, sequences) → enforce with a domain
   service + database constraint, or model the collection as its own aggregate (`InvoiceSeries`).
4. Model state as an explicit enum + guarded transitions; illegal transitions return errors.
5. Decide which transitions raise domain events.

## Building blocks
| Block | Rules |
|---|---|
| **Value object** | immutable `record`/`readonly record struct`; validated factory `Create(...) → Result<T>`; equality by value; carries behavior (`Money.Add`, `VatRate.Apply`) |
| **Strongly-typed id** | `readonly record struct InvoiceId(Guid Value)`; generated with `Guid.CreateVersion7()`; Dapper `SqlMapper.TypeHandler` or `.Value` in parameters |
| **Entity** | identity within the aggregate; no public setters; only reachable through the root |
| **Domain event** | past tense, immutable, raised inside aggregate methods, contains ids + facts; module-internal |
| **Integration event** | lives in Contracts; primitives only; versioned; produced from domain events at the module boundary via outbox |
| **Domain service** | stateless rule needing several aggregates or external policy data passed in; no I/O inside |
| **Factory** | static method on the root or dedicated class when creation needs policies |
| **Repository** | exactly one per aggregate root; `GetAsync`/`AddAsync`/`SaveAsync` (+ intent-revealing lookups); Dapper implementation; never used by queries |
| **Domain error** | static factory class per aggregate (`InvoiceErrors.AlreadyIssued`) returning `Error` with stable code |

## Minimal aggregate shape (.NET)
```csharp
public sealed class Invoice : AggregateRoot<InvoiceId>
{
    private readonly List<InvoiceLine> _lines = [];
    public IReadOnlyList<InvoiceLine> Lines => _lines;
    public InvoiceStatus Status { get; private set; }
    public Money Total { get; private set; }

    private Invoice() { }                                         // rehydration only (Invoice.Rehydrate)

    public static Result<Invoice> Draft(PartnerId partner, Currency currency) { ... }

    public Result AddLine(ProductId product, Quantity qty, Money unitPrice, VatRate vat)
    {
        if (Status != InvoiceStatus.Draft) return InvoiceErrors.NotEditable(Id);
        _lines.Add(InvoiceLine.Create(product, qty, unitPrice, vat));
        Total = _lines.Sum(l => l.Total, Total.Currency);
        return Result.Success();
    }

    public Result Issue(InvoiceNumber number, DateTimeOffset now)
    {
        if (Status != InvoiceStatus.Draft) return InvoiceErrors.AlreadyIssued(Id);
        if (_lines.Count == 0) return InvoiceErrors.Empty(Id);
        Status = InvoiceStatus.Issued;
        Raise(new InvoiceIssuedDomainEvent(Id, number, now));
        return Result.Success();
    }
}
```

## Persistence with Dapper (no EF Core)
The aggregate knows nothing about SQL. The repository maps rows ↔ aggregate inside the use case's `IDbSession` transaction.
1. **Load:** one round trip with `QueryMultipleAsync` (root row + child rows) → `Aggregate.Rehydrate(rootRow, childRows)`,
   an `internal static` factory that bypasses creation rules but not type invariants. Rows are private `record`s in Infrastructure.
2. **Concurrency:** root table has `RowVersion rowversion`. Update: `UPDATE … WHERE Id = @Id AND RowVersion = @RowVersion`;
   0 rows → return `Error.Concurrency` (no retry inside the handler).
3. **Children:** replace strategy for small collections (`DELETE` children + insert current set) or track changes explicitly
   (added/removed lists kept by the aggregate) for large ones. Choose per aggregate and document it in the repository.
4. **Domain events:** aggregate collects them; `SaveAsync` writes them to `[{schema}].[Outbox]` in the same transaction and clears them.
5. **Value objects / strongly-typed ids:** map to columns explicitly in the repository (`Money` → `Amount decimal(19,4)` + `Currency char(3)`);
   register `SqlMapper.TypeHandler` only for ids used in many queries.
6. **Parameters:** strings as `DbString { Value, Length, IsAnsi }` matching the column, `decimal` precision matching the column — avoid implicit conversions.
7. **Tests:** repository round-trip integration test (save → load → equal state, concurrency conflict returns error).

## Result vs exceptions
Expected business failures return `Result`/`Error` (profile `error_model: result`). Exceptions only for
programmer errors and infrastructure faults. Never throw to signal "invoice already issued".

## Smells
- Handler contains `if (invoice.Status == ...)` → rule belongs in the aggregate.
- Aggregate loads > ~100 child rows routinely → boundary too big; split or model as separate aggregate.
- Domain event handlers modifying the aggregate that raised the event → cycle; rethink boundaries.
- Aggregates injected with services → pass policies/values as method arguments instead.
