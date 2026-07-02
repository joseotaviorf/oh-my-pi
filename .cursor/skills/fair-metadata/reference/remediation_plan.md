# Remediation plan (mandatory deliverable)

Enforced by [`plan_gate.md`](plan_gate.md). Post this plan and **end the turn** before any metadata YAML edit.

## Phase A — Resolve scope and run gates

### A0. Scope inventory (mandatory first step)

Match user intent exactly — inventory table lives in [`scoping.md`](scoping.md) (do not re-derive it here). Publish: `**Scope:** …` and `**Inventory:** N file(s)`.

### A1. Local gates (mandatory on full inventory)

```bash
make audit-fair-metadata-scope domain=<scope>
# or: --owner … --fqn … --dag …
```

Report Gate A (owners), Gate B (F2-01 table + F2-02 columns on clean+), Gate C (physical layout on all layers), and raw-layer summary (optional column docs — not blocking).

### A2. Lake (`trino/SKILL.md`, supplementary)

`sql/list_tables_for_remediation.sql` + `checks_result_json` for production tier — does **not** replace A1.

---

## Phase B — Validate owners (Gate A — none skipped)

Every distinct owner in the inventory — see [`owner_remediation.md`](owner_remediation.md) (Trino kick-off with `mcp_auth` when MCP enabled). Missing owners → **AskQuestion in PLAN**, not deferred to EXECUTE.

---

## Phase C — Owner changes → **AskQuestion**

If any owner is missing, invalid, or not ACTIVE → **AskQuestion** before EXECUTE.

---

## Phase D — Plan document (post in chat)

```markdown
## FAIR metadata remediation plan — [scope]

**Scope:** repo folder `dags/governance/` | owner=x@… | fqn=db.table | dag=governance/metabase
**Inventory:** N metadata file(s)

### Gate summary
| Gate | Status | Notes |
|------|--------|-------|
| A Owners | PASS / FAIL | distinct owners: … |
| B Substantive descriptions | PASS / FAIL | N file(s) failing F2-01/F2-02; M additional file(s) flagged on swap-test review (script-passing but generic) |
| C Physical layout | PASS / FAIL | N table(s) missing partition/z-order docs |
| Raw (optional) | PASS / FAIL | N raw file(s) with columns: |

### Owners requiring your decision
| owner | files in scope | status | proposed |
|-------|--------------|--------|----------|

### Proposed changes (max ~10 tables / PR)
| priority | FQN | file path | reason | before → after |
|----------|-----|-----------|--------|-----------------|

`reason` = `F2 failure` (script-flagged) or `quality improvement` (already passes F2 but fails the swap test — see [`description_remediation.md`](description_remediation.md)). Both kinds are in scope; do not omit `quality improvement` rows just because Gate B shows 0 failures.

**Waiting for your approval before editing any metadata files.**
```

---

## Phase E — Execute (explicit approval only)

1. Edit approved rows; respect [`woodpecker_layer_gates.md`](woodpecker_layer_gates.md) and [`description_remediation.md`](description_remediation.md).
2. Re-run `make audit-fair-metadata-scope` on **same user scope**.
3. Run CI validators on branch.
4. Commit / PR only if user asks.
