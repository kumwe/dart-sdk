# Six-month roadmap

This is a relative M0–M6 plan beginning when maintainers approve the contract-foundation direction. Dates may move;
gate conditions do not. [Current status](status.md) records what is actually true.

## Programme boundary

G0–G6 below are SDK repository gates. They do not alter or satisfy Kumwe core Version 2, Gate A or Gate B, and they
cannot close work in a future core programme. This roadmap is preparatory input to a **proposed Version 3 Native
Client Platform**, not an adopted core Version 3 roadmap.

If core maintainers adopt that programme, the core roadmap should contain at least:

- a **native-client contract/SDK-readiness gate** requiring released, digest-pinned machine contracts, supported
  native-application authorization, adopted runtime client-surface discovery and cross-repository fixtures; and
- a **final parity-qualification gate** requiring native outcome evidence for every advertised profile. Missing or
  browser-only operations remain explicitly outside the profile and cannot satisfy the gate.

The local G1 and G5 gates are preparation for those proposed core-owned gates; passing either locally is neither
adoption nor core completion.

## M0–M1: contract adoption package

Target gate: **G1 — Core contract adoption**

The machine-readable half of this package is now drafted in [`contracts/`](../contracts/README.md); each proposal
seeds core review with an audit-grounded design instead of a blank page. Core's roadmap currently contains no
native-client finding at all, so the first adoption step is procedural: file the corresponding findings in core's
roadmap lifecycle, because core closes work only through that ledger.

| Requirement | Drafted proposal | Decision core owns |
| --- | --- | --- |
| `CORE-API-002` | [`problem-details-registry.proposal.json`](../contracts/problem-details-registry.proposal.json) | Freeze the observed `urn:kumwe:problem:` codes as a versioned registry with statuses and retry classes |
| `CORE-AUTH-001` | [`native-authorization.proposal.json`](../contracts/native-authorization.proposal.json) | Accept the authentication-link-first profile ([ADR 0007](decisions/0007-authentication-link-is-the-primary-sign-in.md)), with PKCE as the reviewed alternative ([ADR 0006](decisions/0006-native-authorization-is-pkce-first.md)) |
| `CORE-AUTH-002` | [`native-authorization.proposal.json`](../contracts/native-authorization.proposal.json) | Accept the single-use authenticated web-session handoff and its session-provenance semantics |
| `CORE-ACCOUNT-001` | [`native-authorization.proposal.json`](../contracts/native-authorization.proposal.json) | Accept the guest arrival and positioning lifecycle: pending accounts, steward notification and email-announced activation |
| `CORE-CTX-001` | [`native-discovery.proposal.json`](../contracts/native-discovery.proposal.json) | Adopt the pre-authentication discovery document — including advertised sign-in areas — and bind context selection to token issuance |
| `CORE-MUTATION-001` | [`mutation-semantics.proposal.json`](../contracts/mutation-semantics.proposal.json) | Make per-family replay/precondition declarations normative and scope the shared 24-hour header text |
| `CORE-SURFACE-001` | [`client-surface-contract.proposal.json`](../contracts/client-surface-contract.proposal.json) | Adopt the bounded declarative client-surface grammar and discovery resource |
| `CORE-COLLECTION-001` | [`collection-pagination.proposal.json`](../contracts/collection-pagination.proposal.json) | Extend the observed business cursor envelope to management collections |

Remaining package work:

- Review the capability requirement index and the drafted proposals with core maintainers.
- File the native-client findings in core's roadmap so the work exists in its authoritative ledger. Done:
  core carries them as `V3-NC-001` … `V3-NC-004` under decision D17 and ADR 0009.
- Accept core's outward product identity before it changes. `KumweApiDiscovery.fromJson` and
  `KumweLiveness.fromJson` refuse any `product` value other than the observed `Kumwe CMS`, so the day core
  closes its `V2-DOC-002` — the finding that renames the outward identity after the repository became
  `kumwe/app` — every deployed client built on this SDK fails at discovery and liveness. The SDK must ship
  acceptance of the new value first, and the transitional release accepts a bounded set of product values so
  the two repositories never have to release in the same instant. This is a released-artifact ordering
  constraint, not a contract change; it belongs to whichever milestone is current when core schedules
  `V2-DOC-002`.
- Complete request and success schemas for the supported core resource set (`CORE-API-001` has no machine proposal
  here; it is core's own P0-C machine-surface classification work).
- Add upstream compatibility fixtures, semantic-version rules and deprecation metadata.

Exit evidence: released core artifacts, immutable digests, fixture results and a compatibility window. A proposal in
this repository is not exit evidence.

## M1–M2: invariant Dart client alpha

Target gate: **G2 — Generated SDK alpha**

- Pin the adopted core contract by version and digest.
- Build deterministic Dart generation on top of the SDK-owned primitives that already exist: canonical exact-value
  types (`KumweDecimal`, `KumweMoney`, `KumweQuantity`), idempotency-key and strong-entity-tag values,
  HTTP-semantics retry classification, immutable execution context, and the authorization-provider and
  credential-store ports.
- Implement the remaining transport abstractions the generated client needs: typed results, cursor pages and
  mutation receipts against the adopted contract.
- Add fake-server and released-core contract suites.
- Publish an internal alpha only; do not advertise graphical parity.

Exit evidence: clean regeneration, zero diff on repeat generation, public API review and contract conformance on all
supported Dart runtimes.

## M2–M3: dynamic business and client surfaces

Target gate: **G3 — Dynamic runtime alpha**

- Implement policy-filtered business catalog transport independent of generated models.
- Validate runtime schemas and manifests against the adopted bounded grammar.
- Immutable manifest models with typed unsupported-vocabulary results are implemented against the *proposed*
  grammar (`ClientSurfaceInterpreter`); re-point them at the adopted grammar once core adopts a descendant. Host
  screen models remain client-owned.
- Cache by server-provided generation/checksum and invalidate on authority changes.
- Prove activate/disable/upgrade lifecycle removal without loading executable extension code.

Exit evidence: extension lifecycle fixtures, schema-fuzz tests, locale/accessibility model fixtures and no-code static
analysis gates.

## M3–M4: native authorization and context beta

Target gate: **G4 — Native authorization/context beta**

- Integrate the adopted authentication-link flow behind an application-supplied provider, including the
  deep-link return, the manual cross-device completion code, guest account states and area binding.
- Support secure credential storage adapters without a platform-storage dependency in core models.
- Implement the multi-account roster: explicit origin/area/credential selection, switching and removal, plus
  site/organization/workspace selection and invalidation.
- Integrate the adopted web-session handoff with single-use, exact-origin, redacted URL handling.
- Add retry classification, clock handling and redacted diagnostics.
- Run token theft, link-interception, enumeration, guest-escape, redirect, downgrade, context-confusion and
  local-storage abuse cases.

Exit evidence: provider/context conformance fixtures, threat review, and end-to-end credential revocation tests.

## M4–M5: profile applications and parity

Target gate: **G5 — Advertised profile parity**

- Publish shared host fixtures for the separate [`kumwe/client`](https://github.com/kumwe/client) conformance suite.
- Qualify `business_companion` first.
- Add CMS management only for resources whose contracts are adopted and complete.
- Measure keyboard, screen-reader, responsive and localization behavior.
- Publish a parity matrix that excludes unsupported/browser-only operations from every advertised native profile.

Exit evidence: cross-surface outcome fixtures and released-core tests for every advertised profile.

## M5–M6: stable release candidate

Target gate: **G6 — Stable release**

- Freeze the 1.0 public Dart surface.
- Run compatibility, mutation, fuzz, integration, documentation and package-provenance gates.
- Publish signed artifacts, SBOM/provenance where supported, API documentation and migration guidance.
- Perform backup/reconnect/outage tests for cached metadata without claiming offline sync.
- Record residual risks and an explicit list of profiles not supported by 1.0.

Exit evidence: reproducible package, release checklist, immutable conformance report and maintainer approval.

## Parallel discovery lanes

These lanes do not enter 1.0 unless their own upstream contracts are adopted:

- headless public-site/theme semantics;
- media upload and resumable transfer;
- durable delta/change feed and realtime hints;
- offline capture, reconciliation and document numbering; and
- administrative business-security and high-impact step-up delegation.

Deferring a lane is not permission to make its future implementation impossible. See
[ADR 0005](decisions/0005-offline-sync-is-a-separate-profile.md).
