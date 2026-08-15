# ADR 0004: the SDK never collects user credentials

- Status: Accepted
- Date: 2026-08-15

## Context

The audited core has cookie-backed administrator/portal sign-in and session-bound high-impact step-up, while REST
uses pre-issued bearer tokens. Asking a Flutter SDK to post user passwords or authenticator codes to undocumented
routes would duplicate authentication UI, expand secret exposure and bypass the reviewed session boundary.

## Decision

The SDK receives opaque tokens through an application-supplied `KumweAuthorizationProvider`. It does not accept
passwords, authenticator codes, recovery codes or browser cookies. A production native user flow must be adopted by
core and use an external user-agent or comparably reviewed authorization protocol.

High-impact native actions remain unsupported until core adopts a remote step-up protocol. An external-browser
handoff is outside native parity. The SDK never weakens the limitation by collecting factors itself.

## Consequences

- Authentication and secure persistence remain replaceable platform concerns.
- Manual tokens can support controlled development/integration use, not production user login claims.
- Administrator/portal parity remains blocked until core exposes a suitable flow.
- Token and context metadata need a public discovery contract.

## Rejected alternatives

- Reuse cookie login in an embedded WebView: couples the SDK to browser internals and exposes credentials/session.
- Add username/password grant behavior: no adopted core contract and poor modern security posture.
- Send step-up secrets through MCP or generic REST: contradicts the current proof-consumer boundary.
