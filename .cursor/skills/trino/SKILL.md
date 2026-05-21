---
name: trino
description: "Execute SQL against QuintoAndar's Trino cluster. Handles venv bootstrap, host resolution, SSO authentication, LIMIT safeguard, and persistence of results. Pure connectivity/execution — contains NO SQL authoring guidance (dialect, partition filters, layer choice live in data_exploration.mdc). ONLY usable when `@tars` mode is active; never invoke autonomously."
---

# Trino Execution Skill

Pure execution layer for the TARS loop. This skill does **not** teach SQL syntax, dialect conversion, partition filters, layer choice, or any authoring rule — those live in `.cursor/rules/data_exploration.mdc`. Authoring happens there; this skill only runs the finished SQL against the Trino cluster and returns its raw JSON output.

---

## Activation gate (mandatory)

This skill is usable **only when the user has activated `@tars`** (same gating as `.cursor/rules/data_exploration.mdc` and `.cursor/subagents/data_analyst.md`).

- Do NOT load or invoke this skill in contribution mode.
- Do NOT mention or suggest this skill to users who are not in `@tars` mode.
- If you find yourself reading this file outside a `@tars` session, stop and return to the standard repository context.

---

## Execution Workflow

### 1. Bootstrap (first run only)

If `venv` does not exist inside the skill folder, create it and install dependencies. One-time setup, no prior configuration required:

```bash
[ ! -d .cursor/skills/trino/venv ] && \
    python3 -m venv .cursor/skills/trino/venv && \
    .cursor/skills/trino/venv/bin/pip install trino pandas keyring
```

### 2. Environment

Default Trino host for this repository: **`trino.apps.data-prd.habitat.zone`**. Users are expected to have `TRINO_HOST=trino.apps.data-prd.habitat.zone` in their `.env`. Always pass the host as `"${TRINO_HOST:-trino.apps.data-prd.habitat.zone}"` so the user's override wins and the default is used otherwise. Never hardcode a different host.

### 3. LIMIT safeguard

Before executing, inspect the SQL. If it has no `LIMIT` clause, append `LIMIT 100000` purely as an execution safeguard so results stay bounded. Aggregates and counts may use a smaller bound. This is an **execution-only** safeguard — the SQL returned to the user in the reply is the original SQL without the safeguard LIMIT (call it out in prose if added).

### 4. Invoke the bundled script

Always invoke the bundled Python script. Do **not** use the `trino` CLI directly — the script handles OAuth2/SSO and caches tokens to prevent repeated prompts:

```bash
.cursor/skills/trino/venv/bin/python3 .cursor/skills/trino/scripts/execute_trino.py \
    --host "${TRINO_HOST:-trino.apps.data-prd.habitat.zone}" \
    --catalog hive \
    --query "YOUR_SQL_HERE" \
    --external-auth
```

**Mandatory flags:**
- `--query`: the SQL to execute.
- `--host "${TRINO_HOST:-trino.apps.data-prd.habitat.zone}"`: always pass exactly this pattern.
- `--external-auth`: always include for SSO environments.

**Optional flags:**
- `--port`: defaults to 443 (HTTPS).
- `--schema`: target a specific schema within the catalog.

Single quotes inside the SQL must be escaped with `'\''` when embedded in the shell string.

### 5. Output contract

The script prints exactly one JSON object to stdout:

- On success: `{ "status": "success", "columns": [...], "data": [[...], ...], "count": N }`.
- On failure: `{ "status": "error", "message": "..." }`.

### 6. Persist the full result

Save the script's stdout **verbatim** (never copy-paste, never truncate) to:

```
<cursor_project_folder>/tars_query_results/<session_id>__<entry_index>.json
```

`<cursor_project_folder>` is the directory that contains `agent-transcripts/` and `terminals/`. **Never** save to the workspace root (`bi-etl-ejuice/`) — always use the Cursor project folder. `<session_id>` and `<entry_index>` are provided by the TARS loop (see `.cursor/subagents/data_analyst.md`). Create the `tars_query_results/` folder on first write. Use shell redirection (`> "<path>"`) — not file-write tools.

### 7. Error handling

If the JSON has `status: "error"`, do NOT retry silently:
- Surface the Trino error message to the user.
- Still save the error JSON to the result file (the file must exist even on failure — the TARS loop references it).
- Wait for the user to confirm a fix before re-executing.

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
