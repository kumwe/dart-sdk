# Architecture decision records

These decisions govern this repository. “Accepted” means the SDK architecture follows the decision; it does not
mean Kumwe core has adopted a proposed wire contract.

| ADR | Decision | Status |
| --- | --- | --- |
| [0001](0001-two-plane-sdk.md) | Separate generated invariant APIs from runtime schema transport | Accepted |
| [0002](0002-client-extensions-are-data.md) | Client extension contributions are bounded data, never executable code | Accepted |
| [0003](0003-core-owns-wire-contracts.md) | Core owns adopted wire contracts; SDK pins released artifacts | Accepted |
| [0004](0004-sdk-never-collects-user-credentials.md) | The SDK never collects user credentials or step-up factors | Accepted |
| [0005](0005-offline-sync-is-a-separate-profile.md) | Offline synchronization is a separate adopted profile | Accepted |
| [0006](0006-native-authorization-is-pkce-first.md) | Native authorization is PKCE-first through an external user agent | Superseded in part by 0007 |
| [0007](0007-authentication-link-is-the-primary-sign-in.md) | The authentication link is the primary end-user sign-in | Accepted |

New ADRs use the next four-digit number and link affected contracts, security controls, conformance gates and
superseded decisions. A changed decision is superseded by a new ADR rather than silently rewritten.
