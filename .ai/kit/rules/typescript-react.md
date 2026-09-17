---
name: typescript-react-standards
description: TypeScript and React standards, feature-sliced organization mirroring backend modules.
globs: **/*.ts,**/*.tsx
---
# TypeScript / React standards

Composition rules: `architecture-composition/references/frontend-composition.md`.
- `strict` TypeScript; no `any` (use `unknown` + narrowing); no non-null `!` without a reason.
- Layers: `app → pages → features → entities → shared`; imports only downward; features never import each other.
- Server state in TanStack Query (query keys per feature); client global state only for UI state.
- API types generated from OpenAPI into `shared/api`; wrapped per feature; no hand-written duplicates of backend DTOs.
- Business rules belong to the backend; client validation mirrors for UX only.
- Components: function components, props typed explicitly, no default exports except route modules.
- Accessibility: semantic elements, labels for inputs, keyboard reachable actions.
