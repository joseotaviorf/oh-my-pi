# Owner remediation (F2-01) — Gate A

Part of the **plan-first** workflow: [`remediation_plan.md`](remediation_plan.md). Do not change `owner` in YAML until the user approves the plan **and** has answered owner questions below.

**Never** assign or copy `owner` without verifying the email is an **ACTIVE** QuintoAndar employee. **Never** invent a fallback owner.

## Scope-wide owner sweep (mandatory)

Gate A applies to **every distinct `owner:` in the scope inventory** — not only files in the PR diff.

1. Resolve scope → list all metadata YAML paths ([`scoping.md`](scoping.md)).
2. Extract distinct owners (emails, including `(missing)`).
3. Verify **each** owner is ACTIVE **online** — **do not skip** because “most files look fine” or CI passed.

```bash
make audit-fair-metadata-scope domain=governance
# Gate A section lists: owner | file_count | MISSING | UNVERIFIED
```

Then complete **Trino kick-off** below before marking any owner UNVERIFIED.

## Trino kick-off (mandatory — before UNVERIFIED)

Complete **before** posting the remediation plan. Do **not** edit `trino/SKILL.md` for MCP auth.

1. **Trino MCP** (`plugin-trino-mcp-Trino MCP`): if listed and STATUS requires auth → call **`mcp_auth`** with `{}` via `CallMcpTool` in the **first** tool turn that needs Trino. Tell the user to complete browser OAuth.
2. Run owner SQL via MCP **`execute_query`** (preferred; fully qualified table names).
3. **Fallback** if MCP is absent or still fails after auth: `execute_trino.py` per `trino/SKILL.md` (`--external-auth`).
4. Only after 1–3 fail → **AskQuestion** (UNVERIFIED) below.

**Forbidden:** inferring “Trino indisponível nesta sessão” when MCP is enabled but `mcp_auth` was never called.

### Owner SQL

| Scope | File |
|-------|------|
| Many owners | [`sql/check_owners_active_batch.sql`](../sql/check_owners_active_batch.sql) — replace `IN (...)` |
| Single owner | [`sql/check_owner_active.sql`](../sql/check_owner_active.sql) |

- Row with `assignment_status_type = 'ACTIVE'` → **ACTIVE**
- Email in scope but no row → **INACTIVE** → AskQuestion
- `(missing)` from offline audit → AskQuestion in **PLAN**, not EXECUTE

Chat preview is enough; do not use TARS `tars_query_results/` persistence.

## When to stop and ask the user

| Situation | Action |
|-----------|--------|
| `owner` missing or empty | **AskQuestion in PLAN** which corporate email to set — not deferred to EXECUTE |
| Invalid format (not `*@quintoandar.com.br`) | **Ask user** for a valid replacement |
| Email not ACTIVE in org_chart | **Ask user** for a replacement |
| Status UNVERIFIED (offline audit) | Complete Trino kick-off, then run owner SQL |
| Trino MCP listed, not authenticated yet | **Call `mcp_auth`** — do not mark UNVERIFIED |
| Auth attempted + query still fails | **AskQuestion** — user must acknowledge owners not validated; continue PLAN only (see below) |
| Trino ran but owner status unclear | Same **AskQuestion** — do not edit YAML until answered |

User may approve a batch mapping: *“use `x@quintoandar.com.br` for all tables owned by inactive `y@…` in DAG Z”* — record in plan, re-verify `x` is ACTIVE via Trino when Trino is available.

## Trino failure or owners still UNVERIFIED (mandatory AskQuestion)

When **`trino/SKILL.md`** cannot run (connection, SSO, timeout) **or** any distinct owner in scope remains **UNVERIFIED** / not confirmed ACTIVE after the owner SQL attempt:

1. **Stop** before **EXECUTE** and before any Write/StrReplace on `dags/**/metadata/**`.
2. Use **AskQuestion** with explicit risk — user must opt in to proceed without online Gate A.

Example options:

| Option | Label (adapt to user language) |
|--------|--------------------------------|
| Proceed | Estou ciente: owners **não** foram validados no Trino — continuar o PLAN |
| Block | Não seguir — vou resolver Trino / validar owners primeiro |

3. Record in the plan or chat: Trino error (if any), list of UNVERIFIED owners, and the user’s choice.
4. If the user selects Proceed → continue PLAN (post full remediation plan, end turn). **This AskQuestion does not authorize EXECUTE.** If they block → help fix Trino or wait.

**Forbidden:** continuing EXECUTE, committing owner fields, or assuming ACTIVE because CI passed or “most owners look fine”.

## How to verify (online only)

| Method | When |
|--------|------|
| **`make audit-fair-metadata-scope` Gate A** | Offline — lists owners; flags MISSING only |
| **Trino `sql/check_owner_active.sql`** | `trino/SKILL.md` — authoritative for ACTIVE |
| **`checks_result_json`** `owner_not_active_employee` | Lake row exists |
| **Production `enrich_fairness_assessment`** | org_chart join after deploy |

Woodpecker CI **does not** call org_chart — **CI verde ≠ owner ACTIVE**.

## What to ask the user — use **AskQuestion**

When any owner in scope needs a new email, **stop** and use **AskQuestion** after online verification.

Include: owner email, file count in scope, issue (missing / invalid / INACTIVE), affected FQNs sample.

**Do not** offer colleague emails unless each was verified ACTIVE in this session.

## Forbidden patterns

- Skipping owners not mentioned by BugBot or CI
- Copying `owner` from sibling YAML without verifying ACTIVE online
- Squad default email without user confirmation
- Keeping inactive owner because CI passed
- PR author / agent operator as replacement unless user names that email
- Marking UNVERIFIED without **`mcp_auth`** when Trino MCP is enabled
- Deferring missing-owner **AskQuestion** to EXECUTE batches

## After user confirms

1. Set `owner:` on all layers for the same logical table in scope.
2. Re-run `make audit-fair-metadata-scope` Gate A on the **same user scope**.
3. Note in PR which owners changed and why.
