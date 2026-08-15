# ADR 0001: separate invariant and runtime contract planes

- Status: Accepted
- Date: 2026-08-15

## Context

Kumwe has fixed core REST resources and a generated business family whose definitions change as extensions activate,
upgrade and disable. The caller-specific live OpenAPI contract also varies by actor/policy. Generating the entire
Dart package from one runtime caller would make the package authority-specific and stale after lifecycle changes.

## Decision

Use two planes:

1. generate invariant Dart endpoints/models from a complete contract artifact released by core; and
2. validate and expose policy-filtered business definitions and client-surface manifests at runtime as bounded,
   immutable wire-level contract/value models.

Both planes share transport, context, exact values, failure and cache-invalidation primitives. Runtime schemas never
modify generated source or load extension-owned code.

## Consequences

- Core DTOs remain strongly typed and reproducible.
- New business extensions appear without a Dart package release.
- Applications must handle unsupported runtime vocabulary explicitly.
- Runtime record values are schema-backed maps/value objects rather than one generated class per entity.
- Two conformance suites and version domains are required.

## Rejected alternatives

- Generate from `/api/v1/openapi.json` for each user: authority-specific, operationally impractical and unsafe to
  cache as a package.
- Hand-write all endpoints and dynamic entities: drifts from core and loses deterministic compatibility.
- Generate a new app when an extension activates: incompatible with native app distribution and extension lifecycle.
