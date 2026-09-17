# State
task: Choose architecture baseline for LocalTax (profile.yml + ADR-0001)
class: architecture/XL/structural
modules: TaxpayerRegister: pure-slices | Taxation: sliced-domain | Receivables: sliced-domain | Enforcement: sliced-domain | Reporting: pure-slices | OnlinePayments: hexagonal-integration
plan: none
adrs: docs/adr/0001-architecture-baseline.md
base: 05075f7
sha: eb23fd4
tool: copilot
phase: architecture
gate: G0 approved
steps: none
review_cycles: 0
next: /add-fitness-tests: generate NetArchTest suite from profile rules R-001..R-008

## decisions
- Domain: Romanian local taxes for a city hall - taxpayer register, assessment of building/land/vehicle taxes, payments & receipts, arrears/penalties, enforcement, certificates & reports
- Regulated rules to model as domain logic: assessment/calculation, penalties, payment allocation order (legally dated, audited)
- Integrations: none at start; design room for payment gateway (Ghiseul.ro) and e-mail/PDF later
- Scale/team/lifetime: 1-3 devs, single deployment, one or few municipalities, long-lived LOB, moderate DDD experience
- Frontend: react-ts
- Recipe bias: sliced-domain for core taxation, pure-slices for reporting/certificates, hexagonal-integration for payment integrations
- User approved ADR-0001 and set profile status: active

## notes
- Greenfield repo: only AI kit files, no source code, no researcher phase needed
- Repo evidence prefilled: dotnet-10, SQL Server VALERIA/LocalTax windows auth (user applies schema), dapper read+write, xunit+localdb, ef-migrations, netarchtest

## log
- 2026-09-17 13:22 copilot classify state created
- 2026-09-17 13:31 copilot architecture architect wrote profile.yml (draft) + ADR-0001 (proposed)
- 2026-09-17 13:40 copilot architecture committed eb23fd4 and pushed to origin/main
