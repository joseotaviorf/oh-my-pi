---
name: fair-metadata
description: "FAIR metadata audit and remediation by user scope (repo folder, YAML domain allowlist, owner, table). Disambiguate repo folder vs YAML domain: for any domain or product line. PLAN default — no metadata YAML edits until explicit execute approval. Read reference/plan_gate.md first."
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

## `@tars` — when required

| Task | `@tars` required? |
|------|------------------|
| Scope inventory, Gate B (substantive descriptions) | No — local CLI + read declarations |
| Gate A owner ACTIVE via `org_chart` / lake | Yes — Trino [`sql/check_owner_active.sql`](sql/check_owner_active.sql) |
| Business semantics from lake samples / `llm_context` | Yes |

Without `@tars`, run Gate B locally; mark Gate A owners **UNVERIFIED** until Trino confirms ACTIVE. Do **not** block the audit turn — proceed with the plan and flag owners pending verification.

For CI-only red builds without FAIR scope work, use **`fix-ci-failure`**.

---

## Three gates (scope inventory)

Run on **every file in the closed scope inventory** before the PLAN deliverable (raw column docs optional — see table):

| Gate | What | Tool |
|------|------|------|
| **A — Owners** | Every distinct `owner:` present; ACTIVE verified **online** before EXECUTE | `@tars` + `check_owner_active.sql` (Gate A offline lists MISSING / UNVERIFIED only) |
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

On EXECUTE: append layout guidance to existing column/table descriptions — do not replace business semantics. Do not invent columns not present in the declaration.

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

**Done criteria:** Gate A — no MISSING owners without user decision; ACTIVE verified via `@tars` before EXECUTE; Gate B — 0 F2-01/F2-02 description failures in clean+; Gate C — 0 tables with declaration layout config missing partition/z-order docs in metadata.

---

## Modes

| Phase | Trigger | Allowed | Forbidden |
|-------|---------|---------|-----------|
| **PLAN** (default) | audite / melhore FAIR / remediar domain or owner | Scope audit, Trino, read repo, AskQuestion, plan in chat | Edit `dags/**/metadata/**` |
| **EXECUTE** | “pode executar”, “approved”, “go ahead”, “aplica o plano” | Edit approved paths; re-run gates + CI validators | Execute without completed PLAN checklist |

Ambiguous replies (“ok”, “continua”) → stay in PLAN.

---

## PLAN (Steps 0–2 — then stop)

### Step 0 — Resolve scope and audit

1. **Disambiguate domain names** for **any** domain or product line request — [`reference/domain_disambiguation.md`](reference/domain_disambiguation.md) (repo folder vs YAML allowlist).
2. **Scope:** [`reference/scoping.md`](reference/scoping.md) — match user intent exactly.
3. **Inventory:** list all YAML paths; count `N files`; show in plan (include repo folder vs YAML `domain:` in the plan header).
4. **Gates A/B/C:** run `make audit-fair-metadata-scope …` (or CLI `--audit` with scope flags); apply Gate C per subsection above on the inventory.
5. **Lake (optional, `@tars`):** [`sql/list_tables_for_remediation.sql`](sql/list_tables_for_remediation.sql) for production `checks_result_json` — supplements local gates, does not replace them.

### Step 1 — Owners

[`reference/owner_remediation.md`](reference/owner_remediation.md). Every distinct owner in scope must be ACTIVE or **AskQuestion** for replacement. **None skipped.**

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
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-fair-metadata
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-lineage-consistency
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-metadata-files-content
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
| `reference/owner_remediation.md` | Gate A |
| `reference/description_remediation.md` | Gate B |
| `reference/woodpecker_layer_gates.md` | Layer rules + CI |
| `docs/governance/fair_domains_playbook.md` | Domains playbook entry point |

## Do not

- Shrink audit scope to PR diff or BugBot comments
- Skip owners in the inventory (“most are fine”)
- Document columns on `metadata/raw/` or restore `-pii`/`-confidential` tags there
- Use governance-lake filler to pass F2-02
- Guess owners or substitute without **AskQuestion**
