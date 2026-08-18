# Contract instructions

These instructions apply under `contracts/` in addition to the repository-level `AGENTS.md`.

- Proposal control documents remain `status: proposal` and `authoritative: false` until core adopts them. Schemas
  and examples remain visibly proposal-scoped through their identifiers and descriptions.
- Do not copy or silently repair core OpenAPI here; changes to normative server contracts belong in `kumwe/app`.
- Close and bound schemas, keep identifiers stable, and use synthetic examples only.
- Do not allow arbitrary URLs, request paths, executable code, templates, handlers, credentials, or unbounded data.
- Update the contract index, documentation, validator coverage, and examples together.
- Run `dart run tool/validate_contracts.dart contracts` for every contract change.
