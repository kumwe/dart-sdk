# 0008 — Fence asynchronous session acquisition by generation

Status: Accepted. This is a local SDK lifecycle decision; it adopts no server wire contract.

## Context

At SDK source `88f4c82d575d65005fc75e367bff9f4e0f65d056`, interactive token requests
bypassed the sign-out guard used by silent acquisition. Overlapping interactive
requests could adopt results in completion order, and a stale refresh failure
could disable a newer successful interactive session. A delayed duplicate 401
invalidation could also clear a replacement acquired by another caller.

## Decision

An explicit interactive attempt starts a new acquisition generation. Sign-out
also advances it and remains terminal; opening another session uses another
`KumweSession` instance. Silent callers share the current guarded acquisition.
Only the current generation may adopt a token or escalate its lifecycle state.
An obsolete successful result throws `KumweAuthenticationException`; a provider
failure keeps its existing error behavior without changing the newer session.
Completion clears the in-flight slot only if that slot still names that work.

A 401 handler retains the failed token and generation across asynchronous
invalidation, then rechecks both before changing state. A newer current token
survives even if its provider reused the same credential reference.

The provider owns credential storage and must invalidate the exact named
credential, never an unrelated current credential or an entire global cache.
Discarding a superseded result must preserve a currently held credential with
the same reference. While a newer acquisition is pending, disposal waits for
that result or a generation change, then rechecks current ownership. Sign-out
wakes deferred disposal without waiting for the pending provider result. Thus
an obsolete successful caller may wait for newer work before its refusal;
provider failures retain their normal propagation. The SDK adds no token manager, authentication endpoint or
new public method. Provider and OS storage integration remain host concerns.

## Evidence and consequences

The deterministic public-API tests in
[`session_lifecycle_boundaries_test.dart`](../../test/session/session_lifecycle_boundaries_test.dart)
control provider completions and invalidations without network requests or elapsed-time assertions.
They cover obsolete success/error, terminal sign-out, reference reuse, shared
acquisition ownership and delayed duplicate rejection. Existing one-refresh-only,
context-binding and expiry tests remain package-owned.

See [Security](../security.md#session-acquisition-lifecycle) and
[Quality and conformance](../quality-and-conformance.md#package-owned-client-boundaries).
