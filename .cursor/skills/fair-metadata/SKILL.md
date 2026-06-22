---
name: fair-metadata
description: "FAIR metadata audit and remediation by user scope (repo folder, YAML domain allowlist, owner, table). Disambiguate repo folder vs YAML domain. PLAN default — no metadata YAML edits until explicit execute approval. Gate A Trino kick-off in reference/owner_remediation.md. Read reference/plan_gate.md first."
---

# FAIR metadata

Single skill for **audit** and **remediation** of governance YAML. Read [`reference/plan_gate.md`](reference/plan_gate.md) first.

## Scope rule (mandatory)

**Gates A, B, and C run on the closed inventory that matches the user's request** — resolve scope in Step 0 ([`reference/scoping.md`](reference/scoping.md)) before auditing. Do not substitute PR diff, BugBot comment paths, or CI-changed files when the user asked for a domain, table, owner, or DAG.

| User request | Scope inventory |
|--------------|-----------------|
| Entire **repo folder** (e.g. `for_rent` → `dags/for_rent/`) | All `dags/{folder}/**/metadata/**/*.yml` — see [`reference/domain_disambiguation.md`](reference/domain_disambiguation.md) |
| **YAML `domain:`** (e.g. `Data Ops & Governance`) | All metadata with that allowlist value (repo-wide `rg`) — no CLI flag |
| Specific owner | All metadata YAML with that `owner:` (optionally narrowed by repo folder) |
| Single table / FQN | All layers for `database_name.table_name` |
| Single DAG | All `dags/{folder}/{dag}/metadata/**/*.yml` |
| **PR / branch validation** | Files changed vs `origin/master` — use **`make validate-fair-metadata`**, not a wide `--audit --domain …` |

**Repo folder vs YAML `domain:`:** `--domain` on the CLI is the **folder basename** under `dags/`; metadata `domain:` must be an **allowlist** value (often different — e.g. `for_rent` → `For Rent`, `governance` → `Data Ops & Governance`). Default to **folder** when the user names a domain folder; use **AskQuestion** when ambiguous. See [`reference/domain_disambiguation.md`](reference/domain_disambiguation.md).

Resolve scope first → publish **closed inventory** (`N files`) → run **Gates A, B, and C** on that inventory only.

**PR diff** limits **Woodpecker CI** and typical **EXECUTE batch size** (~10 tables) — it is the scope **only when the user asked to validate the PR**, not when they asked to audit a domain or table.

---

## Trino and context

| Task | How |
|------|-----|
| Scope inventory, Gate B (substantive descriptions) | `make audit-fair-metadata-scope` + read declarations |
| Gate A owner ACTIVE | [`reference/owner_remediation.md`](reference/owner_remediation.md) — Trino kick-off (`mcp_auth` when MCP enabled) + owner SQL |
| Business semantics | **`docs/llm_context/**`** + repo SQL; bounded Trino samples when unclear |

**Trino failure or UNVERIFIED owners:** only after kick-off in `owner_remediation.md` — **AskQuestion** to acknowledge risk and continue PLAN. That acknowledgment does **not** authorize EXECUTE.

For CI-only red builds without FAIR scope work, use **`fix-ci-failure`**.

---

## Three gates (scope inventory)

Run on **every file in the closed scope inventory** before the PLAN deliverable (raw column docs optional — see table):

| Gate | What | Tool |
|------|------|------|
| **A — Owners** | Every distinct `owner:` disposition recorded (ACTIVE via Trino, replacement, or UNVERIFIED in plan) | [`owner_remediation.md`](reference/owner_remediation.md) + owner SQL |
| **B — Descriptions** | Substantive **table** (F2-01) + **column** (F2-02) descriptions on **clean / core / enrich / dw / metric** | `make audit-fair-metadata-scope domain=…` or `--audit --domain …` |
| **C — Physical Layout** | Partition/z-order from declaration reflected in metadata descriptions (**all layers**) | Read `*_declaration.yml` + metadata — see **Gate C** below |
| **Raw (optional)** | Column docs on raw encouraged, **not required** | Scope audit prints a raw summary only — never blocks |

Owner, domain, and min description length: **`validate-metadata-files-content`** (Yamale). Raw `columns:` optional — not a CI gate.

### Gate C — physical layout (agent-only)

Interoperable check (not in CI or `checks_result_json`). Runs at PR time from the declaration file — unlike **I1-01**, which requires deploy and metastore snapshot.

For **each metadata file in scope** (any layer — raw, clean, core, enrich, dw, metric):

1. Read the DAG `*_declaration.yml` in the same folder.
2. Infer layer from the metadata path (`metadata/raw/` → raw, `metadata/clean/` → clean, etc.).
3. Resolve effective **partitions** and **z-order** for that layer:
   - **raw:** `raw_partitions` → `partitions` → `default_raw_partitions` → `default_partitions`
   - **clean:** `clean_partitions` → `partitions` → `default_clean_partitions` → `default_partitions`
   - **core / enrich / dw / metric:** `partitions` → `default_partitions`
   - **z-order (raw):** `raw_z_order_by` → `z_order_by`
   - **z-order (clean):** `clean_z_order_by` → `z_order_by`
   - **z-order (other layers):** `z_order_by`
   - Table-level keys in `tables_customization` override workflow defaults.
4. If both lists are empty → **SKIP**.
5. Otherwise, check that metadata **descriptions** mention those columns and advise filtering on them (partition pruning, z-order data skipping). Table `description` should summarize the layout when config exists.
6. **Example:** `dags/growth/hightouch_logs/metadata/clean/sync_runs_trino.yml`.

On EXECUTE: append layout guidance to existing column/table descriptions — do not replace business semantics. Do not invent columns not present in the declaration. Follow **YAML shape** in [`reference/description_remediation.md`](reference/description_remediation.md) so `validate-fair-metadata` can parse the file (invalid YAML fails CI before F2 checks).

```bash
# Example: full governance domain audit
make audit-fair-metadata-scope domain=governance

# Example: single owner across repo
uv run --project packages/bietlejuice-runtime python \
  -m bietlejuice.governance.fairness_assessment.validate_metadata_cli \
  --audit --owner 'name@quintoandar.com.br'

# Example: single table (all layers)
make audit-fair-metadata-scope fqn=datalake_metabase_clean.metabase_table
```

**Done criteria:** Gate A disposition — no MISSING `owner:` without user decision; each owner ACTIVE (Trino), replaced via AskQuestion, or UNVERIFIED with PLAN acknowledgment **recorded in the remediation plan** (UNVERIFIED ≠ ACTIVE). Gate B — 0 F2-01/F2-02 description failures in clean+; Gate C — 0 tables with declaration layout config missing partition/z-order docs in metadata.

---

## Modes

| Phase | Trigger | Allowed | Forbidden |
|-------|---------|---------|-----------|
| **PLAN** (default) | audite / melhore FAIR / remediar domain or owner | Scope audit, Trino, read repo, AskQuestion, plan in chat | Edit `dags/**/metadata/**` |
| **EXECUTE** | “pode executar”, “approved”, “go ahead”, “aplica o plano”, “executa o plano” | Edit approved paths; re-run gates + CI validators | Execute without completed PLAN checklist |

Ambiguous replies (“ok”, “continua”) → stay in PLAN.

---

## PLAN (Steps 0–2 — then stop)

### Step 0 — Resolve scope and audit

1. **Disambiguate domain names** for **any** domain or product line request — [`reference/domain_disambiguation.md`](reference/domain_disambiguation.md) (repo folder vs YAML allowlist).
2. **Scope:** [`reference/scoping.md`](reference/scoping.md) — match user intent exactly.
3. **Inventory:** list all YAML paths; count `N files`; show in plan (include repo folder vs YAML `domain:` in the plan header).
4. **Gates B/C (offline):** run `make audit-fair-metadata-scope …` (or CLI `--audit` with scope flags); apply Gate C per subsection above on the inventory.
5. **Gate A (online):** [`reference/owner_remediation.md`](reference/owner_remediation.md) — Trino kick-off + owner SQL.
6. **Lake (optional):** [`sql/list_tables_for_remediation.sql`](sql/list_tables_for_remediation.sql) via `trino/SKILL.md` for production `checks_result_json` — supplements local gates, does not replace them.

### Step 1 — Owners

[`reference/owner_remediation.md`](reference/owner_remediation.md). Every distinct owner must be ACTIVE, **AskQuestion** for replacement (missing / invalid / inactive), or UNVERIFIED only after kick-off failure. **None skipped.** Do **not** defer missing-owner decisions to EXECUTE batches.

### Step 2 — Post plan and stop

Template: [`reference/remediation_plan.md`](reference/remediation_plan.md) Phase D. Include scope inventory + gate summary. Close with:

> Waiting for your approval before editing any metadata files.

**End the turn.** No YAML edits in the same response.

---

## EXECUTE (Step 3 — after explicit approval)

Prerequisites: [`reference/plan_gate.md`](reference/plan_gate.md) checklist (all items).

1. Edit files from the approved plan (max ~10 tables/PR); [`reference/woodpecker_layer_gates.md`](reference/woodpecker_layer_gates.md).
2. Descriptions: [`reference/description_remediation.md`](reference/description_remediation.md).
3. Re-run **scope audit** on the same user scope + CI validators on the branch:

```bash
make audit-fair-metadata-scope domain=<scope>
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-metadata-files-content
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-fair-metadata
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-lineage-consistency
```

4. Commit only if the user asks.

---

## References

| File | Purpose |
|------|---------|
| **`reference/plan_gate.md`** | Mandatory gate |
| `reference/scoping.md` | Scope resolution |
| `reference/domain_disambiguation.md` | Repo folder vs YAML `domain:` allowlist (all domains) |
| `reference/remediation_plan.md` | Plan template |
| `reference/owner_remediation.md` | Gate A — Trino kick-off + dispositions + AskQuestion |
| `reference/description_remediation.md` | Gate B |
| `reference/woodpecker_layer_gates.md` | Layer rules + CI |
| `docs/governance/fair_domains_playbook.md` | Domains playbook entry point |

## Do not

- Shrink audit scope to PR diff or BugBot comments
- Skip owners in the inventory (“most are fine”)
- Document columns on `metadata/raw/` or restore `-pii`/`-confidential` tags there
- Use governance-lake filler to pass F2-02
- Guess owners or substitute without **AskQuestion**
- Treat Trino/owner **AskQuestion** as execute approval — post the plan and wait for a separate explicit execute message
- Mark owners UNVERIFIED without calling **`mcp_auth`** when Trino MCP is enabled
- Defer missing-owner **AskQuestion** to EXECUTE — resolve in PLAN
