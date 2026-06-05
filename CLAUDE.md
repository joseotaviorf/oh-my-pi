@AGENTS.md

## For Claude Code

The canonical, tool-agnostic instructions live in `AGENTS.md` (imported above) — including
the always-on **uv toolchain rules** (never run bare `python3`/`pip`/`venv`/pyenv).

Claude Code does **not** auto-read `.cursor/rules/*.mdc` or `.cursor/skills/`. When a task
touches DAGs, SQL, naming, metadata, or a specific workflow, read the relevant
`.cursor/rules/*.mdc` and `.cursor/skills/<name>/SKILL.md` on demand — `AGENTS.md`'s
"Where detailed rules live" section is the index.
