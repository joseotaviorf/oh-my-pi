---
name: trino
description: "Execute SQL against QuintoAndar's Trino cluster. Dependencies are declared inline (PEP 723) and resolved by `uv run --script`; handles host resolution, SSO authentication, and LIMIT safeguard. Pure connectivity/execution — contains NO SQL authoring guidance. Invoked by fair-metadata, other skills that need Trino, or explicit user request."
---

# Trino Execution Skill

Pure execution layer for running SQL against the Trino cluster. This skill does **not** teach SQL syntax, dialect conversion, partition filters, layer choice, or any authoring rule — those live in pipeline conventions (`sql_conventions.mdc`) or the invoking skill's reference docs (e.g. `fair-metadata`). This skill only runs finished SQL and returns its raw JSON output.

---

## When to use

Invoke when:

- **`fair-metadata`** needs owner ACTIVE checks or bounded description samples.
- **`debug-salesforce-sst-pipeline`** delegates bounded SST metric queries (including
  `events_type_volume` with `event_type = 'DLQ_RECOVERY'`).
- Another skill explicitly delegates Trino execution.
- The user explicitly asks to run a query against Trino.

Do **not** invoke for general ad-hoc SQL unless the user or an active skill requests it.

---

## Execution Workflow

### 1. Environment

Default Trino host for this repository: **`trino.apps.data-prd.habitat.zone`**. Users are expected to have `TRINO_HOST=trino.apps.data-prd.habitat.zone` in their `.env`. Always pass the host as `"${TRINO_HOST:-trino.apps.data-prd.habitat.zone}"` so the user's override wins and the default is used otherwise. Never hardcode a different host.

The bundled script declares its dependencies inline via a PEP 723 header (`trino`, `pandas`, `keyring`). `uv run --script` resolves them from the global uv cache on first use and reuses them afterwards — there is no venv to bootstrap, and nothing is written under the skill folder. Never run bare `python3` or `pip install` here.

Prefer **Trino MCP** (`mcp_auth` + `execute_query`) when the MCP server is available; use this skill as fallback.

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

Show the JSON (or a concise preview) in chat — do not write result files under the repo.

### 5. Error handling

If the JSON has `status: "error"`, do NOT retry silently:

- Surface the Trino error message to the user.
- **`fair-metadata`:** follow `owner_remediation.md` — **AskQuestion** before metadata YAML edits if owners cannot be validated.
- Wait for the user to confirm a fix before re-executing (or user acknowledgment to proceed without Gate A).

---

## Common errors

| Symptom | Cause | Fix |
|---|---|---|
| Memory limit exceeded | Query scans too much data | Tighten partition filters on the correct partition columns for the table (verify via declaration or metadata YAML) |
| Authentication prompt loop | Token cache missing/expired | Re-run once; the script caches the token after first SSO round-trip |
| Host resolution error | `TRINO_HOST` set to a stale value | Unset or set to `trino.apps.data-prd.habitat.zone` |

---

## Out of scope for this skill

- SQL dialect conversion (Databricks → Trino).
- Layer priority (DW → enrich → clean → metric).
- Partition filters (`year`, `month`, `day`), column verification, entity routing.
- Response shape (Markdown preview, row-count summary).
- `SELECT *` policy, deduplication patterns, type-safe JOINs.

If you catch yourself answering one of those questions from this file, stop — the invoking skill or pipeline conventions are the authority.

---

## Reference

- [Trino Official Documentation](https://trino.io/docs/current/)
