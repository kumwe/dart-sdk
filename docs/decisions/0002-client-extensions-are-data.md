# ADR 0002: client extensions are bounded declarative data

- Status: Accepted
- Date: 2026-08-15

## Context

Server extensions may execute trusted PHP and render Twig within Kumwe's server boundaries. Replicating that model in
a native client would require downloading code, solving platform signing/sandboxing, and granting extension code
access to tokens, local files and native APIs. Server trust does not automatically establish client-device trust.

## Decision

Client-surface contributions are closed, bounded JSON documents with semantic workspace, navigation and screen
bindings. They may reference core-owned definition/view/action/report handles. They may not contain arbitrary URLs,
HTTP paths, scripts, modules, handlers, templates, expressions, credentials or executable assets.

The Flutter host owns widgets, navigation, accessibility and platform integration. Unknown required vocabulary fails
closed. Server-only extension pages remain server-only or may be opened only in the external system browser through
separately trusted application routing, outside native parity and without forwarding native credentials.

## Consequences

- One installed native application can render compatible extensions safely across supported desktop and mobile hosts.
- Extension authors work within a finite UI vocabulary.
- Highly bespoke server pages are not automatically native.
- Adding a new semantic component requires a versioned contract change and SDK support.
- Core must admission-test, policy-filter and lifecycle-bind manifests.

## Rejected alternatives

- Download extension Dart/JavaScript/WASM: expands the device attack surface and distribution complexity.
- Embed arbitrary Twig/HTML as native UI: cannot preserve server sandbox, theme and security semantics.
- Accept arbitrary API paths in manifests: bypasses typed OpenAPI, capability and data-flow review.
