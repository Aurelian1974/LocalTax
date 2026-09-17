# Frontend Composition (React/TS, Blazor)

The same axes apply; only the vocabulary changes.

| Axis | React/TS | Blazor |
|---|---|---|
| A2 Boundaries | one top-level feature folder per backend module | one Razor Class Library or folder per module |
| A3 Direction | `app → pages → features → entities → shared` (upper may import lower only) | Pages → Components → Services → Contracts |
| A4 Organization | feature-sliced: `features/{feature}/{ui,model,api}` | `Features/{Feature}/{Page,Components,State}` |
| A5 Reads/writes | query hooks (TanStack Query) vs mutation hooks, separate files | separate query/command service methods |
| A6 Logic | UI logic only; business rules are backend-owned. Client validation mirrors, never replaces | same |

## Rules
1. A frontend feature maps to a backend module's Contracts/API, never to its internals.
2. `shared/` holds UI kit, API client base, formatting — no feature logic (rule of three applies).
3. Features do not import each other; compose them in `pages/` or through `entities/`.
4. Server state lives in the query cache; global client stores only for true UI state.
5. Generated API clients (OpenAPI) live in `shared/api` and are wrapped per feature.

Enforce with `eslint-plugin-boundaries` (or dependency-cruiser) rules generated from the same
module list in `profile.yml`.
