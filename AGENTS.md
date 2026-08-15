# Working on the Kumwe Dart SDK

This repository is the client-side companion to Kumwe core. It is contract-driven: a convenient Dart API is never
allowed to invent server behavior.

## Read first

| Document | Governs |
| --- | --- |
| [`docs/status.md`](docs/status.md) | Observed current capability and gate state |
| [`docs/contract-lifecycle.md`](docs/contract-lifecycle.md) | Core/SDK ownership and adoption workflow |
| [`docs/architecture.md`](docs/architecture.md) | Dependency direction and the invariant/runtime split |
| [`docs/security.md`](docs/security.md) | Credential, context, extension and data-safety rules |
| [`docs/compatibility-and-release.md`](docs/compatibility-and-release.md) | Versioning and publication gates |
| [`contracts/README.md`](contracts/README.md) | Status and validation of machine-readable proposals |

`docs/roadmap.md` is forward work. `docs/status.md` is the current evidence-backed state. Do not mark a roadmap
item complete by rewriting its objective; record the observed result and evidence in status.

## Source-of-truth rules

1. Kumwe core owns its REST/OpenAPI, authentication, errors, runtime metadata and extension contribution contracts.
2. This repository owns Dart API design, generation policy, client conformance and packaging.
3. Documents under `contracts/` are proposals until the same contract is adopted in core with a version,
   compatibility fixture and release evidence.
4. A proposal control document must use `status: proposal` and `authoritative: false`. Proposal schemas and examples
   instead use proposal identifiers and descriptions; never present any of them as adopted contracts.
5. Do not copy the audited core OpenAPI into this repository. Pin an adopted upstream artifact by release and digest.
6. If code and docs disagree, state the discrepancy. Do not document the desired behavior as current behavior.

## Architectural constraints

- Keep generated invariant endpoints separate from runtime schema interpretation.
- Generated models must not depend on Flutter. Flutter presentation adapters may depend on the Dart client model.
- Extension data is declarative and bounded. Never download, evaluate or dynamically load extension-owned Dart,
  JavaScript, WASM, Twig, native libraries or arbitrary expressions.
- Never allow a manifest to supply an arbitrary HTTP path, executable handler, template path or credential.
- Server authorization, validation and concurrency are authoritative. Client-side checks improve interaction only.
- Exact decimal, money and quantity values remain strings/closed objects; never convert them through binary floats.
- Missing and denied business resources may be intentionally indistinguishable. Preserve that behavior.
- Cache keys include site, actor/credential family, organization/workspace, authorization generation, trusted runtime
  generation and definition checksum whenever the server exposes them.
- Offline mutation and background synchronization require an adopted sync profile. Do not infer them from
  idempotency alone.

## Documentation and contract changes

- Update cross-links and the contract index with every new proposal.
- Every JSON object schema is closed with `additionalProperties: false` unless the open map is explicitly bounded
  with `maxProperties`, `propertyNames` and a value schema.
- Bound every string, array, object map and recursive structure.
- Examples must validate against the schema they name and use obviously synthetic identifiers and checksums.
- Security-sensitive behavior needs misuse cases in `docs/security.md` and conformance coverage in
  `docs/quality-and-conformance.md`.
- A decision that constrains future implementations belongs in `docs/decisions/`; do not bury it in a roadmap row.

## Checks before handoff

At minimum:

```bash
git diff --check
find contracts -name '*.json' -print0 | xargs -0 -n1 jq empty
```

When the repository's schema validator is available, validate every proposal and example against its declared
schema. Run Dart formatting, analysis and tests for any source change. Do not weaken a gate to make a proposal pass.

## Security

Do not commit tokens, credentials, production URLs, personal data or realistic secrets. The SDK must receive
tokens from an application-owned authorization provider and store them only through an application-selected secure
credential adapter. It must never accept a user's Kumwe password or authenticator code.
