# Tooling instructions

These instructions apply under `tool/` in addition to the repository-level `AGENTS.md`.

- Tool output must be deterministic and actionable in local development and CI.
- Validate structure and references generically; do not hard-code today's endpoint counts or names.
- Fail closed on contract defects that would make generated Dart ambiguous or unsafe.
- Keep tools pure Dart unless an adopted build decision explicitly adds another runtime.
- Add unit coverage when changing reusable validation behavior.
