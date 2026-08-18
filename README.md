# Kumwe Dart SDK

Contract-first Dart foundations for authenticated Kumwe clients, including Flutter applications for desktop,
Android, and iOS.

> [!IMPORTANT]
> This repository is at **proposal/foundation stage**. It does not yet provide a production-ready client, and
> the JSON documents under [`contracts/`](contracts/README.md) are not Kumwe core contracts. They become
> authoritative only after adoption and compatibility protection in `kumwe/app`.

This work runs in parallel with the Kumwe core programme. It does not modify, supersede or supply evidence for
core Version 2, Gate A or Gate B. It is preparatory design and conformance input for a **proposed Version 3 Native
Client Platform**; that programme has not adopted the proposal merely because this repository exists. An eventual
Version 3 core roadmap should add both a native-client contract/SDK-readiness gate and a final parity-qualification
gate. Only core-owned adoption and qualification evidence could close those gates.

The intended SDK has two deliberately separate planes:

1. an invariant, generated Dart API for versioned core REST resources; and
2. a bounded runtime transport for policy-filtered business definitions and declarative client surfaces.

That split lets ordinary API changes remain type-safe while extensions appear without shipping or executing
extension-owned Dart code. See [ADR 0001](docs/decisions/0001-two-plane-sdk.md).

## What the audited core supports today

This baseline was prepared against `kumwe/app` commit
`4e5083b3fe43790605ae5c6c5bf8e392f9822efc`.

| Capability | Current assessment |
| --- | --- |
| Policy-filtered generated business discovery and CRUD | Available and suitable for a generic client |
| Bounded search, relations, history, reports and exports | Available |
| Strong business-record concurrency and retry primitives | Available, with contract inconsistencies to resolve |
| Complete typed OpenAPI for every management operation | Not available |
| Native user authorization flow | Not available |
| Media, business-security and localization administration parity | Not available |
| Declarative KIS/client-surface discovery | Not available; proposed here |
| Headless public-site/theme parity | Not available |
| Client change feed, realtime subscription and offline sync | Not available |

The detailed boundary is in [Core-facing requirements](docs/core-requirements.md). Documentation never treats a
missing endpoint as implemented.

## Documentation map

- [Vision, scope and non-goals](docs/vision-and-scope.md)
- [Architecture](docs/architecture.md)
- [Source of truth and contract lifecycle](docs/contract-lifecycle.md)
- [Current foundation and target client-facing API](docs/client-api.md)
- [Extension client surfaces](docs/extension-client-surfaces.md)
- [Authentication and execution context](docs/authentication-and-context.md)
- [Security model](docs/security.md)
- [Compatibility and release policy](docs/compatibility-and-release.md)
- [Quality and conformance](docs/quality-and-conformance.md)
- [Current status](docs/status.md) and [six-month roadmap](docs/roadmap.md)
- [Architecture decisions](docs/decisions/README.md)
- [Draft machine contracts](contracts/README.md)

The reference Flutter host is developed separately in [`kumwe/client`](https://github.com/kumwe/client). This
package remains Flutter-independent and does not own that application's screen models, widgets, navigation, or
platform adapters.

## Repository rules

Start with [`AGENTS.md`](AGENTS.md) before contributing. In particular:

- do not hand-write claims that conflict with the pinned core contract;
- do not introduce an executable extension mechanism into the client;
- do not generate Dart from the caller-specific runtime OpenAPI document;
- keep proposal contracts visibly non-authoritative until core adopts them; and
- never collect a Kumwe password in this SDK.

## License and support

No support or stability promise is made until the release gates in
[Compatibility and release](docs/compatibility-and-release.md) are met. Licensing will follow the repository's
published package metadata and release artifacts.
