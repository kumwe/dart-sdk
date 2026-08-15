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

- Review the capability requirement index with core maintainers.
- Decide the native-application authorization profile for desktop and mobile hosts.
- Complete request, success and Problem Details schemas for the supported core resource set.
- Resolve idempotency and concurrency semantics by resource family.
- Adopt a versioned client-surface contract and discovery resource in core.
- Add upstream compatibility fixtures, semantic-version rules and deprecation metadata.

Exit evidence: released core artifacts, immutable digests, fixture results and a compatibility window. A proposal in
this repository is not exit evidence.

## M1–M2: invariant Dart client alpha

Target gate: **G2 — Generated SDK alpha**

- Pin the adopted core contract by version and digest.
- Build deterministic Dart generation and canonical exact-value codecs.
- Implement transport, Problem Details, ETag, idempotency and cursor abstractions.
- Add fake-server and released-core contract suites.
- Publish an internal alpha only; do not advertise graphical parity.

Exit evidence: clean regeneration, zero diff on repeat generation, public API review and contract conformance on all
supported Dart runtimes.

## M2–M3: dynamic business and client surfaces

Target gate: **G3 — Dynamic runtime alpha**

- Implement policy-filtered business catalog transport independent of generated models.
- Validate runtime schemas and manifests against the adopted bounded grammar.
- Add immutable manifest/value models with typed unsupported-vocabulary results; host screen models remain client-owned.
- Cache by server-provided generation/checksum and invalidate on authority changes.
- Prove activate/disable/upgrade lifecycle removal without loading executable extension code.

Exit evidence: extension lifecycle fixtures, schema-fuzz tests, locale/accessibility model fixtures and no-code static
analysis gates.

## M3–M4: native authorization and context beta

Target gate: **G4 — Native authorization/context beta**

- Integrate the adopted authorization flow behind an application-supplied provider.
- Support secure credential storage adapters without a platform-storage dependency in core models.
- Implement explicit site/organization/workspace selection and invalidation.
- Add retry classification, clock handling and redacted diagnostics.
- Run token theft, redirect, downgrade, context-confusion and local-storage abuse cases.

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
