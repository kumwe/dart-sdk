# ADR 0005: offline synchronization is a separate profile

- Status: Accepted
- Date: 2026-08-15

## Context

Core has useful non-foreclosure foundations: caller-created record/operation IDs, business replay windows, strong
versions and a client-asserted capture instant in an internal aggregate command. It does not have a client delta
feed, durable mutation-push envelope, tombstones, conflict protocol, attachment synchronization or decided document
numbering under disconnection.

An HTTP retry queue is not an offline synchronization design. Authorization and policy may change during an outage,
and a timed-out request may already have committed.

## Decision

The baseline SDK is online-first. Offline synchronization enters only as a separately versioned profile after core
adopts a durable change/push/conflict protocol and resolves document-numbering semantics. Cache and future ports may
avoid foreclosing the profile, but no public API implies offline correctness before conformance exists.

## Consequences

- Idempotency support is used for retries, not marketed as offline operation.
- Local caches are disposable and not authoritative.
- A future sync package can have different storage, encryption, migration and lifecycle obligations.
- Point-of-sale/offline profile work remains gated by core product decisions.

## Rejected alternatives

- Queue arbitrary REST calls: loses dependencies, context changes, partial acknowledgements and conflict semantics.
- Read internal integration events: they are not policy-filtered client contracts.
- Last-write-wins: violates optimistic concurrency and financial/operational integrity.
