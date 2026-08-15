# Test instructions

These instructions apply under `test/` in addition to the repository-level `AGENTS.md`.

- Keep tests deterministic, network-independent, and free of real credentials or production data.
- Cover success, protocol failure, malformed input, immutability, redaction, and cross-context isolation.
- Test public behavior rather than implementation details where practical.
- A regression fixture must explain the contract or security behavior it protects.
- Do not weaken assertions to accommodate an invalid upstream contract.
