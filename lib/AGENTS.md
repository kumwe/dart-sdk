# Library instructions

These instructions apply under `lib/` in addition to the repository-level `AGENTS.md`.

- Keep this package pure Dart; production library code must not import Flutter.
- Keep generated invariant APIs separate from handwritten runtime-schema transport.
- Preserve immutable public values, explicit context, safe error semantics, and credential redaction.
- Do not encode server business policy, hidden defaults, or UI behavior in the SDK.
- Never execute extension-supplied code or accept arbitrary extension request paths.
- Add focused tests for every public behavior and security boundary.
