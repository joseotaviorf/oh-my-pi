@AGENTS.md

## For Claude Code

The canonical, tool-agnostic instructions live in `AGENTS.md` (imported above) — including
the always-on **uv toolchain rules** (never run bare `python3`/`pip`/`venv`/pyenv).

Claude Code does **not** auto-read `.cursor/rules/*.mdc`. Rules are Cursor-only; read the
relevant `.cursor/rules/*.mdc` on demand when a task touches DAGs, SQL, naming, or metadata.

**Skills** live in `.cursor/skills/` (source of truth). Claude Code discovers them via the
`.claude/skills` symlink → `.cursor/skills/` — same files, no duplication. Invoke with
`/skill-name` or read `.cursor/skills/<name>/SKILL.md` when a workflow applies.
`AGENTS.md`'s "Where detailed rules live" section is the index.
