# State
task: Add architecture fitness tests from profile.yml
class: architecture/L/structural
modules: TaxpayerRegister: pure-slices | Taxation: sliced-domain | Receivables: sliced-domain | Enforcement: sliced-domain | Reporting: pure-slices | OnlinePayments: hexagonal-integration
plan: none
adrs: docs/adr/0001-architecture-baseline.md
base: 05075f7
sha: ad9ab9460971fa19d6ce00dcb5737f861338fa73
tool: copilot
phase: implementation
gate: G0 approved
steps: done: copy template; add SharedKernel Money; add tests for R-003/R-004/R-005/R-007/R-008; fix review cycles 1-2 | current=review complete | status green
review_cycles: 2
next: Build first module slices per profile recipes

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
- 2026-09-17 14:05 copilot implementation S1 green: architecture tests pass 8/8
- 2026-09-17 14:09 copilot implementation S1 green after review cycle 2
