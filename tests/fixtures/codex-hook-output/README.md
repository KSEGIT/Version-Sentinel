# Codex hook output contracts

These unmodified JSON schemas come from OpenAI Codex tag `rust-v0.171.0`:

- [SessionStart](https://github.com/openai/codex/blob/rust-v0.171.0/codex-rs/hooks/schema/generated/session-start.command.output.schema.json)
- [PreToolUse](https://github.com/openai/codex/blob/rust-v0.171.0/codex-rs/hooks/schema/generated/pre-tool-use.command.output.schema.json)
- [PostToolUse](https://github.com/openai/codex/blob/rust-v0.171.0/codex-rs/hooks/schema/generated/post-tool-use.command.output.schema.json)

All three files also match the schemas at `rust-v0.171.0-alpha.13`, the Codex
version bundled with the affected desktop app. For example, see its
[SessionStart schema](https://github.com/openai/codex/blob/rust-v0.171.0-alpha.13/codex-rs/hooks/schema/generated/session-start.command.output.schema.json).

The schemas are licensed under Apache-2.0. `UPSTREAM-LICENSE` and
`UPSTREAM-NOTICE` are copied from that desktop tag's
[LICENSE](https://github.com/openai/codex/blob/rust-v0.171.0-alpha.13/LICENSE) and
[NOTICE](https://github.com/openai/codex/blob/rust-v0.171.0-alpha.13/NOTICE).

The [wire types](https://github.com/openai/codex/blob/rust-v0.171.0/codex-rs/hooks/src/schema.rs)
reject unknown fields. Context belongs inside `hookSpecificOutput`, not at the root.
The test checks the subset used by Version Sentinel output with Python's standard
library; it is not a general JSON Schema validator. Refresh these files from the
same upstream tag when updating the host contract.
