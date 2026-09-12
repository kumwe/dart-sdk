# Kumwe Dart SDK

[![Dart SDK CI](https://github.com/kumwe/dart-sdk/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/kumwe/dart-sdk/actions/workflows/ci.yml)
[![Dart](https://img.shields.io/badge/Dart-%3E%3D3.8%20%3C4.0-0175C2)](pubspec.yaml)
[![Status](https://img.shields.io/badge/status-development%20foundation-blue)](docs/status.md)

Pure Dart transport and contract primitives for site-bound Kumwe clients, including Flutter desktop and mobile applications. The SDK translates server contracts into typed client operations while Core owns authority and business behavior.

## Availability

The source package is `kumwe_sdk`, currently `0.1.0-dev.6`; [pubspec.yaml](pubspec.yaml) is the version and dependency authority. Publication is disabled with `publish_to: none`. There is no published package or qualified production compatibility profile yet.

The repository contains executable transport, business-resource models and operations, session lifecycle, exact-value and mutation primitives, runtime-cache values, proposal interpreters, tests and CI. Generated management resource clients and concrete native authorization endpoints still depend on Core contract adoption. See [current status](docs/status.md) and [the public client API](docs/client-api.md).

The JSON documents under [contracts](contracts/README.md) remain proposals until Core adopts, versions and qualifies them. Passing SDK checks does not establish server support or native application parity.

## Development

Use Dart 3.8 or later within the supported 3.x range:

```sh
dart pub get
dart format --output=none --set-exit-if-changed lib test tool
dart analyze --fatal-infos
dart test
dart run tool/validate_contracts.dart contracts
```

CI tests the minimum Dart version and the current stable SDK; formatting is checked on stable. Consumers evaluating this unpublished source must select an explicit reviewed revision and supply their own transport, authorization and secure-storage integration. It is not a drop-in production client.

## Contract with Core

| Owner | Responsibility |
| --- | --- |
| [Kumwe Core](https://github.com/kumwe/app) | REST/OpenAPI, authentication, authorization, business rules, persistence and authoritative runtime contracts |
| Dart SDK | Typed transport and results, immutable context, protocol validation, bounded runtime interpretation and client conformance |
| [Native client](https://github.com/kumwe/client) | Flutter presentation, navigation, platform adapters and application-owned credential storage |

The architecture keeps fixed resource generation separate from bounded runtime interpretation. Runtime extensions supply declarative data; the SDK must never execute extension-owned Dart, JavaScript, WASM or native code. Server denial, exact values, ETags, idempotency and authority boundaries remain intact.

Read [architecture](docs/architecture.md), [contract lifecycle](docs/contract-lifecycle.md), [authentication and context](docs/authentication-and-context.md), and [security](docs/security.md).

## Compatibility and evidence

The Core API audit is pinned to `kumwe/app@4e5083b3fe43790605ae5c6c5bf8e392f9822efc`. Its findings describe that revision; they are not a current audit of every subsequent Core release. [Core requirements](docs/core-requirements.md) records the evidence and unresolved contract dependencies.

A supported SDK profile requires explicit Core versions, contract generations and conformance evidence under the [compatibility and release policy](docs/compatibility-and-release.md). SDK development versions and proposed wire-contract versions are separate identities. Offline synchronization requires a separately adopted profile.

## Contributing

Start with [AGENTS.md](AGENTS.md), the [documentation index](docs/README.md), [quality and conformance](docs/quality-and-conformance.md), and [active roadmap](docs/roadmap.md). Preserve proposal status, public API boundaries and the distinction between observed behavior and requirements. Historical release changes remain in [CHANGELOG.md](CHANGELOG.md).

Licensing and support must be established by the published package metadata and release artifacts before distribution; this repository currently contains no license declaration or supported release promise.
