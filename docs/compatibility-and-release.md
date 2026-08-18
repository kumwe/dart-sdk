# Compatibility and release policy

## Version domains

Four versions move independently:

| Domain | Owner | Purpose |
| --- | --- | --- |
| Kumwe core release | `kumwe/app` | Server runtime and complete release artifacts |
| Core machine-contract generation | `kumwe/app` | REST/errors/auth and auxiliary schemas |
| Client-surface generation | `kumwe/app` after adoption | Declarative extension/client vocabulary |
| Dart SDK version | This repository | Public Dart API, implementation and supported matrix |

The SDK never assumes equal numbers imply compatibility.

## Proposal versions

Files under `contracts/` use `0.y.z-proposal.n`. They are review coordinates only. They are neither a supported
server range nor a commitment to preserve the proposal indefinitely.

When core adopts a contract, it assigns an authoritative identifier and version. The proposal-to-adopted mapping is
recorded in the contract index; proposal identifiers are not served forever as aliases unless core explicitly
chooses that compatibility behavior.

## SDK semantic versioning

Before 1.0, minor SDK releases may refine public API, but each release includes migration notes. After 1.0:

- **patch** fixes behavior without changing public Dart signatures, wire generation or advertised profiles;
- **minor** adds backward-compatible APIs, optional contract support or a newly qualified profile;
- **major** removes/renames public APIs, raises a minimum core generation incompatibly, or changes value semantics.

Security withdrawal may require an exceptional supported-range change. It follows the emergency process in
[Contract lifecycle](contract-lifecycle.md).

## Public Dart API

The public API is the package entry point and types explicitly documented as public. Files under internal source
paths, generated implementation details and test fixtures are not public contracts.

Compatibility checks cover:

- exported library/type/member signatures;
- enum/sealed subtype exhaustiveness policy;
- serialization behavior of public values;
- equality/hash semantics;
- stable failure and capability identifiers; and
- deprecation annotations and migration links.

Adding an enum value can break exhaustive consumers. Open vocabularies use validated value classes rather than
closed Dart enums unless the wire contract freezes the set for the compatibility window.

## Core support window

Every SDK release states an explicit inclusive lower and exclusive upper core range plus exact supported machine
contract generations. The initial stable target is at least two currently supported core minor generations or a
documented time window agreed with core maintainers; the actual value must be adopted jointly before 1.0.

Support requires fixture execution, not syntactic version matching. A deployment outside the matrix receives a typed
compatibility failure unless the application opts into an explicitly experimental policy.

## Runtime contract negotiation

Startup discovery compares stable contract IDs and semantic versions:

- missing required contract: session/profile unavailable;
- newer compatible minor: accept known vocabulary and report unknown optional contributions;
- newer required vocabulary: reject affected surface, not the whole process when isolation is safe;
- deprecated contract: work during the published window and emit a structured diagnostic;
- withdrawn/denylisted contract: fail closed with migration guidance.

No request downgrades silently to a weaker authentication, context or validation generation.

## Deprecation

A public SDK API is deprecated for at least one normal minor release and one documented migration window before
removal, except for emergency security withdrawal. Deprecation documentation names:

- replacement;
- earliest removal version/date;
- affected core generations/profiles; and
- behavior changes, including cache or retry implications.

Core contract deprecation follows core's adopted policy and must be machine-readable to the SDK.

## Release artifacts

A stable release includes:

- Dart package and generated API documentation;
- source commit and dependency lock evidence;
- pinned core artifact identifiers and SHA-256 digests;
- generator and contract-policy versions;
- compatibility/profile matrix;
- conformance, platform and security gate report;
- migration/deprecation notes;
- known unsupported/external-browser capabilities, explicitly outside every advertised native profile; and
- artifact checksum/signature/provenance where the distribution channel supports them.

Generated source must reproduce byte-for-byte from the published inputs.

## Release gates

| Gate | Required evidence |
| --- | --- |
| Contract integrity | Adopted artifacts, digests and schema validation |
| API compatibility | Public API diff against previous release |
| Generation determinism | Two clean generations with zero diff |
| Core matrix | Cross-repo fixtures on every supported core version |
| Runtime matrix | Supported Dart runtimes; host OS/Flutter qualification remains in `kumwe/client` |
| Security | Abuse cases, dependency/secret scans and redaction tests |
| Quality | Analysis, unit/property/fuzz/integration tests and coverage policy |
| Documentation | Current profiles, limits, migration and API docs agree |
| Package | Clean consumer project resolves, builds and runs fixture |

A skipped required gate blocks release or narrows the advertised support matrix. It is never recorded as passing.

## Profile versioning

Profiles (`business_companion`, `cms_management`, and future parity/sync profiles) have requirement sets in the
contract index. Adding a profile is a minor SDK feature only after its full conformance suite passes. Removing an
advertised profile or making a required operation browser-only is breaking.

## Changelog discipline

Release notes separate:

- added SDK behavior;
- adopted/upgraded core contracts;
- compatibility and deprecation changes;
- security changes;
- fixed defects; and
- known unsupported capabilities.

They do not describe roadmap objectives as delivered behavior.
