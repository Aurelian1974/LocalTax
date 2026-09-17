# Worked example — ERP for a Romanian SME

**Capabilities:** invoicing, e-Factura submission, partners, products/prices, stock, cash & bank,
general ledger postings, SAF-T D406, management reports, users/roles.

**Forces:** fiscal rules change yearly (regulated, costly when wrong); ANAF APIs change and fail
independently; 2 developers; long-lived product; SQL Server skills strong; peak = month-end reporting.

**Topology:** modular-monolith. Microservices rejected: one team, one release cadence, no differing
availability profile; month-end load is a reporting/read problem solvable with read models and indexes.

**Boundaries & recipes**

| Module | Subdomain | Score | Recipe | Notes |
|---|---|---|---|---|
| Invoicing | core | 5 | clean-sliced | numbering series, VAT, corrections are invariants |
| Ledger | core | 5 | clean-sliced | double-entry balance invariant; postings immutable |
| Stock | supporting | 3 | sliced-domain | valuation method (FIFO/CMP) is an invariant, small model |
| EFactura | generic | 2 (Q5) | hexagonal-integration | ACL over ANAF XML and SPV responses |
| Partners | supporting | 1 | pure-slices | CUI validation via SharedKernel value object |
| Products | supporting | 1 | pure-slices | |
| Reporting (SAF-T, mgmt) | supporting | 1 | pure-slices + table-module | read-only views, SPs allowed |
| Identity | generic | 0 | pure-slices | or external IdP |

**Integration:** Invoicing publishes `InvoiceIssued` (outbox) → Ledger posts, EFactura submits,
Reporting projects. Partners exposes `IPartnerLookup` query contract.

**Rejected:** Clean everywhere (ceremony on 5 of 8 modules); pure slices everywhere (fiscal
invariants would scatter across handlers and SPs, untestable in isolation).
