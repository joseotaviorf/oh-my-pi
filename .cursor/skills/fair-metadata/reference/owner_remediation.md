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

Then verify ACTIVE with `@tars` + `sql/check_owner_active.sql` before EXECUTE.

## When to stop and ask the user

| Situation | Action |
|-----------|--------|
| `owner` missing or empty | **Ask user** which corporate email to set |
| Invalid format (not `*@quintoandar.com.br`) | **Ask user** for a valid replacement |
| Email not ACTIVE in org_chart | **Ask user** for a replacement |
| Status UNVERIFIED (offline audit) | Run `@tars` before EXECUTE |

User may approve a batch mapping: *“use `x@quintoandar.com.br` for all tables owned by inactive `y@…` in DAG Z”* — record in plan, re-verify `x` is ACTIVE via Trino.

## How to verify (online only)

| Method | When |
|--------|------|
| **`make audit-fair-metadata-scope` Gate A** | Offline — lists owners; flags MISSING only |
| **Trino `sql/check_owner_active.sql`** | `@tars` — authoritative for ACTIVE |
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

## After user confirms

1. Set `owner:` on all layers for the same logical table in scope.
2. Re-run `make audit-fair-metadata-scope` Gate A on the **same user scope**.
3. Note in PR which owners changed and why.
