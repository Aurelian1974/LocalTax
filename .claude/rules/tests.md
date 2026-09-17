---
name: test-standards
description: "Testing standards for unit, integration and architecture tests."
applyTo: "**/*Tests/**/*.cs,**/*.Tests/**/*.cs"
paths:
  - "**/*Tests/**/*.cs"
  - "**/*.Tests/**/*.cs"
---
<!-- GENERATED from .ai/kit by scripts/Build-AiKit.ps1 — edit the sources, not this file -->
# Test standards

Strategy per recipe: skill `architecture-fitness-tests` §3.
- xUnit; test names describe behavior in business terms: `Cancelling_issued_invoice_after_deadline_fails`.
- Arrange/Act/Assert separated by blank lines; one behavior per test.
- Domain tests: pure, no mocks, no DI container.
- Integration tests: real SQL Server via Testcontainers, `WebApplicationFactory`, `FakeTimeProvider`; replace only external adapters.
- Do not mock repositories, IDbSession, handlers or anything the module owns.
- Assertions on observable outcomes: HTTP result, persisted state, outbox messages — not on internal calls.
- Test data via builders in the test project; no shared mutable fixtures across test classes.
