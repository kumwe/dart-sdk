# Vision, scope and non-goals

## Vision

Provide a safe, idiomatic Dart interface through which Flutter applications can use the same authorized Kumwe
application services as other machine surfaces, while allowing newly activated business extensions to become
discoverable without publishing client code.

The end state is a reusable SDK, not one Flutter application's private networking layer. It should support a native
administrator/portal client when core exposes the required contracts and remain useful to command-line, server-side
Dart and test consumers.

## Programme relationship

This foundation is parallel preparatory work, not a change to the current Kumwe core delivery programme. Core
Version 2, Gate A and Gate B remain untouched, and no artifact or local gate in this repository is evidence that
they passed. The intended programme destination is a **proposed Version 3 Native Client Platform**, for which this
repository may supply design, requirement and conformance input after core review.

The future Version 3 core roadmap should, if maintainers adopt this direction, include two explicit core-owned
outcomes:

1. a native-client contract and SDK-readiness gate before client implementation is treated as supportable; and
2. a final parity-qualification gate before any administrator, portal or public-site profile is advertised.

Those gates are recommendations, not current core roadmap commitments. Work here cannot mark either one complete.

## Product outcomes

The SDK aims to provide:

- typed access to stable, versioned core resources;
- runtime policy-filtered business definition, record, relation, action, report and export access;
- explicit site, organization and workspace context;
- first-class ETag, idempotency, retry and Problem Details handling;
- deterministic exact-value codecs;
- declarative client-surface discovery for extensions;
- secure token-provider integration without password handling;
- conformance evidence against pinned core releases; and
- actionable unsupported-capability results instead of hidden fallback behavior.

## Scope profiles

Parity is measured by profile rather than a single percentage.

| Profile | Definition | Current feasibility at audited core commit |
| --- | --- | --- |
| `business_companion` | Generated business discovery, CRUD, relations, history, actions, reports and exports | Feasible with known gaps |
| `cms_management` | Content, models, workflows, navigation, settings, identities and automation | Partial; contract schemas and pagination are incomplete |
| `administrator_parity` | All graphical administrator outcomes including media, security, localization and step-up | Not feasible through current REST API |
| `portal_parity` | Account/session, scoped workspaces, approvals and generated records | Not feasible through current REST API |
| `public_site_parity` | Public pages, routes, navigation, media semantics and active theme behavior | Not feasible as a native headless client |
| `realtime_updates` | Authenticated notification hints reconciled through a durable change feed | Not feasible; neither client feed nor subscription contract exists |
| `offline_sync` | Durable capture, delta pull, push acknowledgement and conflict reconciliation | Deferred; no adopted protocol |

Each release declares the profiles it actually satisfies. “Kumwe client” never implies every profile.

## In scope for the foundation

- Contract ownership and adoption rules.
- Proposed Dart public API and dependency boundaries.
- Requirements for a complete upstream OpenAPI contract.
- A bounded, declarative extension client-surface proposal.
- Security, compatibility, release and conformance policy.
- A gated six-month implementation plan.

## Non-goals

- Reimplementing Kumwe domain policy in Dart.
- Treating the caller-specific live OpenAPI contract as a build-time SDK source.
- Running PHP, Twig, Dart, JavaScript, WASM or native extension code downloaded from a Kumwe instance.
- Rendering an arbitrary server theme natively.
- Turning MCP into the application's primary data protocol.
- Guessing undocumented request or response bodies.
- Calling internal event/outbox tables a client change feed.
- Advertising offline support from idempotency and client-generated IDs alone.
- Offering distributed transactions across unrelated REST calls.
- Capturing passwords, second factors or recovery codes in the SDK.

## Success criteria

A production release requires all of the following:

1. Core adopts and versions the contracts consumed by the SDK.
2. Generated code is reproducible from a pinned artifact and digest.
3. Runtime schemas are closed, bounded, policy-filtered and lifecycle-versioned.
4. Authentication has a supported native application authorization flow or a documented external token-provider boundary.
5. Every advertised profile has executable conformance evidence.
6. Unsupported features are explicit in discovery and API results.

See [Current status](status.md) for evidence and [Roadmap](roadmap.md) for the gates leading there.
