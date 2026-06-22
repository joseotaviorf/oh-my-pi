---
name: trino
description: "Execute SQL against QuintoAndar's Trino cluster. Dependencies are declared inline (PEP 723) and resolved by `uv run --script`; handles host resolution, SSO authentication, LIMIT safeguard, and persistence of results. Pure connectivity/execution — contains NO SQL authoring guidance (dialect, partition filters, layer choice live in data_exploration.mdc for @tars, or fair-metadata reference docs for metadata gov). Usable when `@tars` is active, or when invoked by the `fair-metadata` skill (owner ACTIVE + bounded description samples)."
---

# Trino Execution Skill

Pure execution layer for the TARS loop. This skill does **not** teach SQL syntax, dialect conversion, partition filters, layer choice, or any authoring rule — those live in `.cursor/rules/data_exploration.mdc`. Authoring happens there; this skill only runs the finished SQL against the Trino cluster and returns its raw JSON output.

---

## Activation gate (mandatory)

Usable when the user activated **`@tars`**, or when **`fair-metadata`** invokes this skill (owner ACTIVE + bounded samples — **not** the Tars loop: no `tars_track_record.jsonl` or `tars_query_results/`).

- Do NOT invoke for general ad-hoc SQL outside `@tars` or `fair-metadata`.
- Do NOT tell the user to add `@tars` for fair-metadata work.

---

## Execution Workflow

### 1. Environment

Default Trino host for this repository: **`trino.apps.data-prd.habitat.zone`**. Users are expected to have `TRINO_HOST=trino.apps.data-prd.habitat.zone` in their `.env`. Always pass the host as `"${TRINO_HOST:-trino.apps.data-prd.habitat.zone}"` so the user's override wins and the default is used otherwise. Never hardcode a different host.

The bundled script declares its dependencies inline via a PEP 723 header (`trino`, `pandas`, `keyring`). `uv run --script` resolves them from the global uv cache on first use and reuses them afterwards — there is no venv to bootstrap, and nothing is written under the skill folder. Never run bare `python3` or `pip install` here.

### 2. LIMIT safeguard

Before executing, inspect the SQL. If it has no `LIMIT` clause, append `LIMIT 100000` purely as an execution safeguard so results stay bounded. Aggregates and counts may use a smaller bound. This is an **execution-only** safeguard — the SQL returned to the user in the reply is the original SQL without the safeguard LIMIT (call it out in prose if added).

### 3. Invoke the bundled script

Always invoke the bundled script via `uv run --script`. Do **not** use the `trino` CLI directly — the script handles OAuth2/SSO and caches tokens (via `keyring`) to prevent repeated prompts:

```bash
uv run --script .cursor/skills/trino/scripts/execute_trino.py \
    --host "${TRINO_HOST:-trino.apps.data-prd.habitat.zone}" \
    --catalog hive \
    --query "YOUR_SQL_HERE" \
    --external-auth
```

(The script's shebang is `#!/usr/bin/env -S uv run --script`, so `./.cursor/skills/trino/scripts/execute_trino.py …` also works once it is executable — same uv-resolved deps either way.)

**Mandatory flags:**
- `--query`: the SQL to execute.
- `--host "${TRINO_HOST:-trino.apps.data-prd.habitat.zone}"`: always pass exactly this pattern.
- `--external-auth`: always include for SSO environments.

**Optional flags:**
- `--port`: defaults to 443 (HTTPS).
- `--schema`: target a specific schema within the catalog.

Single quotes inside the SQL must be escaped with `'\''` when embedded in the shell string.

### 4. Output contract

The script prints exactly one JSON object to stdout:

- On success: `{ "status": "success", "columns": [...], "data": [[...], ...], "count": N }`.
- On failure: `{ "status": "error", "message": "..." }`.

### 5. Persist the full result

**`@tars` session:** save stdout verbatim to `<cursor_project_folder>/tars_query_results/<session_id>__<entry_index>.json` (see `data_analyst.md`).

**`fair-metadata`:** chat preview is enough for owner checks; do not use TARS persistence.

### 6. Error handling

If the JSON has `status: "error"`, do NOT retry silently:
- Surface the Trino error message to the user.
- **`fair-metadata`:** follow `owner_remediation.md` — **AskQuestion** before metadata YAML edits if owners cannot be validated.
- **`@tars` session:** still save the error JSON to the result file when applicable.
- Wait for the user to confirm a fix before re-executing (or user acknowledgment to proceed without Gate A).

---

## Common errors

| Symptom | Cause | Fix |
|---|---|---|
| Memory limit exceeded | Query scans too much data | Tighten partition filters on the correct partition columns for the table (verify via declaration or metadata YAML — see `data_exploration.mdc`) |
| Authentication prompt loop | Token cache missing/expired | Re-run once; the script caches the token after first SSO round-trip |
| Host resolution error | `TRINO_HOST` set to a stale value | Unset or set to `trino.apps.data-prd.habitat.zone` |

---

## Out of scope for this skill

The following belong to `.cursor/rules/data_exploration.mdc`, not here:

- SQL dialect conversion (Databricks → Trino).
- Layer priority (DW → enrich → clean → metric).
- Partition filters (`year`, `month`, `day`), column verification, entity routing.
- Response shape (Markdown preview, row-count summary, case i vs case ii rendering).
- `SELECT *` policy, deduplication patterns, type-safe JOINs.

If you catch yourself answering one of those questions from this file, stop — the rule is the authority.

---

## Reference

- [Trino Official Documentation](https://trino.io/docs/current/)
