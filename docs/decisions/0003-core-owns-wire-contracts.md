# ADR 0003: core owns wire contracts

- Status: Accepted
- Date: 2026-08-15

## Context

The SDK needs contracts that the audited core does not yet expose, including native application authorization, stable problem
codes and client-surface discovery. Defining JSON in this repository can advance design, but an SDK document cannot
make a server endpoint exist or require core to preserve it.

## Decision

`kumwe/app` is authoritative for adopted REST, authentication, errors, runtime metadata and extension contribution
contracts. This repository may publish clearly marked proposals. Adoption requires core runtime, schemas, fixtures,
compatibility policy and a released immutable artifact. The SDK imports that release by version and digest.

Local proposal identifiers are not treated as compatible aliases for adopted identifiers unless core explicitly
declares them.

## Consequences

- No circular source-of-truth dispute exists.
- Cross-repository work has an explicit adoption handoff.
- SDK implementation may be blocked on core rather than using speculative behavior.
- Releases require a compatibility matrix and immutable upstream artifacts.

## Rejected alternatives

- Let the SDK repository define server contracts unilaterally: unenforceable and prone to drift.
- Scrape documentation/runtime behavior: loses machine compatibility and stable errors.
- Vendor a mutable branch snapshot: cannot support reproducible releases.
