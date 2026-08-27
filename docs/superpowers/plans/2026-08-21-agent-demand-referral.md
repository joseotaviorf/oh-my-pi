# Agent demand referral (TQC offer grain) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship one enrich table of agent-sourced Sale demand at **TQC-offer grain** for AAREDE-504, and record AAREDE-507 as compose-only (no daily physical table).

**Architecture:** `query_delta` DAG `enrich_agent_performance` writes `datalake_agent_performance.agent_demand_referral`. Spine is `datalake_sale_offer_flows.offer_specialists` where `id_user_agent_lead_referral IS NOT NULL` (SalesFlow kind `AGENT_LEAD_REFERRAL`). Join `datalake_sale_offer.sale_offer` for buyer/house/offer timestamps. Do not read `agent_lead_referral` or `unified_lead_referral_flow` as the fact spine. Daily sent/confirmed/BP family (`fact_agent_demand_sourcing_daily`) is **not** built; AAREDE-509 later `GROUP BY id_user, dt_offer`.

**Tech Stack:** Airflow DAG Builder, Spark 3.5 / EMR `query_delta`, Delta, governance metadata YAML, Inmetro DQ YAML.

## Global Constraints

- Dual-runtime SQL: no `QUALIFY`, no `GROUP BY ALL`, no `IFF`, no 3-arg `DATEDIFF`, no variant `column:key`.
- Enrich may read clean/enrich only (not DW). No sandbox BPS.
- No raw PII in the new enrich table (no name/email/phone from `offer_specialists`).
- DAG declaration `.yml` only; after declaration edits run `make create-dag-files`.
- ConfigurationService / `{load_start_date}` only if incremental; this table is **full** extract (~50k rows).
- `custom_schema: agent_performance` → metastore `datalake_agent_performance` (same stem as `dw_agent_performance`).
- Do not re-union Sheets ∪ `agent_lead_referral`.
- v1 SALE / TQC-on-offer only. No TQA/RENT, no 509 SSOT, no windows/rates, no Matias reverse.
- Do not commit unless the user asks.

## Phase 0 Decision Log

- scope: AAREDE-504 physical enrich + AAREDE-507 Go/No-Go as compose-only
- out-of-scope: AAREDE-509, TQA/RENT, Sheets re-union, windows, Matias reverse, physical daily table
- success-criteria: plan agreed this session; code later. Later: Forno + metadata + Jira 507 No-Go
- tqc-definition: TQC = sale **offer** with specialist `AGENT_LEAD_REFERRAL` (`offer_specialists`)
- not-tqc: `agent_lead_referral` / `unified_lead_referral_flow` = invite/link product (user: MGM), not the TQC performance fact
- grain: one row per TQC-attributed offer (`id_offer`)
- table-name: `agent_demand_referral` (no TQC in name; `sourcing_channel` holds TQC)
- referral-type: AGENT / EXECUTIVE / AGENT_AND_EXECUTIVE / OTHER vs offer agent vs consultant
- agent-keys: `id_agent`, `id_agent_data`, `id_partner`, `uuid_agent`, `uuid_person` from accreditation
- user-attrs: affiliation, agent_status, agent_profile, demand-acquisition flag; no name/email/phone/CRECI
- event-vs-daily: **one** offer-grain enrich (504). **no** 507 daily table. 509 is later agent-day SSOT for all families, not a second TQC table
- two-tables: no. Do not ship 504+507. Do not keep a parallel TQC projection beside `offer_specialists` unless the thin Agents contract is that one table
- dag-home: `dags/agents/enrich_agent_performance/`
- schema: `datalake_agent_performance.agent_demand_referral`
- bp-join: none. TQC **is** the offer. Visit conversion is VBBA, not this table
- delivery: plan file only until user says implement
- edge-cases: activation jobs extra-filter `id_user_agent_lead_referral = id_user_agent` (self TQC). This table keeps **all** TQC specialists on the offer
- test-coverage: Inmetro unique/complete on `id_offer`; recon query vs `offer_specialists` count

## Source compare (prod Trino 2026-08-21)

| Source | Grain | Role | Scale |
|---|---|---|---|
| `offer_specialists` TQC | offer | **TQC SSOT for this epic** | ~42k–49k offers with `id_user_agent_lead_referral`; ts from 2024-04 |
| `unified_lead_referral_flow` | invite | Sheets Old ∪ product New | ~320k; Old ~28k from 2021; New ≈ ALR |
| `agent_lead_referral` | invite | Product invites (REFERRAL / SERVICE_LINK / SCHEDULING_LINK) | ~292k from 2023-08; ~224 RENT |

Overlap: ~99.95% of TQC offers join a unified invite on `(id_buyer, id_user_agent_lead_referral)`. That does **not** make the invite table the TQC fact. TQC-on-offer origins: REFERRAL 37.4k, SERVICE_LINK 11.0k, SCHEDULING_LINK 300, no invite 24.

AAREDE-504 DoD “invite → confirmed → BP” is **not** this v1 contract. v1 contract: TQC offers. Invite funnel stays in For Sale `enrich_tqc_referral` if anyone still needs it.

## File map

| Path | Responsibility |
|---|---|
| `dags/agents/enrich_agent_performance/enrich_agent_performance_declaration.yml` | DAG + full extract + merge on `id_offer` |
| `dags/agents/enrich_agent_performance/enrich_agent_performance_cluster.yml` | EMR preset |
| `dags/agents/enrich_agent_performance/queries/enrich/agent_demand_referral.sql` | TQC offer projection |
| `dags/agents/enrich_agent_performance/metadata/enrich/agent_demand_referral.yml` | FAIR + lineage |
| `dags/agents/enrich_agent_performance/data_quality/enrich/agent_demand_referral.yml` | PK + size |
| `docs/llm_context/business_entities/agents_programs.md` | Correct TQC SSOT vs invite table |

---

### Task 1: Scaffold DAG declaration + cluster

**Files:**
- Create: `dags/agents/enrich_agent_performance/enrich_agent_performance_declaration.yml`
- Create: `dags/agents/enrich_agent_performance/enrich_agent_performance_cluster.yml`

**Interfaces:**
- Consumes: none
- Produces: DAG name `enrich_agent_performance`, schema `datalake_agent_performance`, table `agent_demand_referral`

- [ ] **Step 1: Write cluster YAML**

```yaml
cluster:
  type: emr_7_12_consolidation_s_memory_fleet_cluster
```

Same family as `enrich_agent_payments`. Table is tiny; right-size later if needed.

- [ ] **Step 2: Write declaration YAML**

```yaml
dag:
  name: enrich_agent_performance
  owner: Data Agents
  schedule_start_date: 2026, 8, 21
  schedule_interval: "0 7 * * *"
  documentation:
    dag_purpose: |
      Agents Performance enrich for TQC (agent-sourced Sale demand) at offer grain.
      One table: agent_demand_referral. Daily aggregates compose in AAREDE-509.
      Does not rebuild TQC Sheets union (owned by enrich_tqc_referral).
workflow:
  type: query_delta
  layer: enrich
  custom_schema: agent_performance
  default_extraction_type: full
  tables_customization:
    agent_demand_referral:
      extraction_type: full
      merge_on:
        - id_offer
      z_order_by:
        - id_user_agent_lead_referral
        - dt_offer
```

No `default_partitions` year/month/day unless SQL emits them. Prefer `dt_offer` DATE column + `z_order_by`; skip hive-style y/m/d unless the team standard for this schema requires them. If CI/cluster templates require partitions, add `year`, `month`, `day` from `dt_offer` in Task 2 SQL and set `partitions: [year, month, day]` here.

- [ ] **Step 3: Generate `_dag.py`**

Run from repo root:

```bash
make create-dag-files
```

Expected: `dags/agents/enrich_agent_performance/enrich_agent_performance_dag.py` generated. Do not hand-edit it.

- [ ] **Step 4: Commit (only if user asked)**

```bash
git add dags/agents/enrich_agent_performance/enrich_agent_performance_declaration.yml \
        dags/agents/enrich_agent_performance/enrich_agent_performance_cluster.yml \
        dags/agents/enrich_agent_performance/enrich_agent_performance_dag.py
git commit -m "$(cat <<'EOF'
feat(agents): scaffold enrich_agent_performance DAG for TQC offer grain

EOF
)"
```

---

### Task 2: SQL + metadata for `agent_demand_referral`

**Files:**
- Create: `dags/agents/enrich_agent_performance/queries/enrich/agent_demand_referral.sql`
- Create: `dags/agents/enrich_agent_performance/metadata/enrich/agent_demand_referral.yml`

**Interfaces:**
- Consumes: `datalake_sale_offer_flows.offer_specialists`, `datalake_sale_offer.sale_offer`
- Produces: `datalake_agent_performance.agent_demand_referral` grain `id_offer`

Column contract (order: IDs → characteristics → booleans → dates → timestamps):

| Column | Meaning |
|---|---|
| `id_offer` | PK. Sale offer with TQC specialist |
| `id_user_agent_lead_referral` | EBDB `id_user` of TQC agent (join to hub / 509 spine) |
| `id_agent_lead_referral` | SalesFlow specialist id (pass-through) |
| `id_buyer` | Buyer on the offer |
| `id_house` | Listing on the offer |
| `id_user_agent` | Offer AGENT specialist (`id_user_agent` on `offer_specialists`) — visit/deal agent, may differ from TQC agent |
| `sourcing_channel` | Literal `'TQC'` |
| `is_self_tqc` | `id_user_agent_lead_referral = id_user_agent` (activation-style flag; do not filter the table on it) |
| `dt_offer` | `DATE(ts_offer_submitted)` — coincident day for 507/509 counts |
| `ts_offer_submitted` | Offer submitted |
| `ts_agent_lead_referral_updated` | Specialist row stamp (attribution, not offer day) |

Do **not** store consultant/agent names or emails.

- [ ] **Step 1: Write SQL**

```sql
SELECT
    os.id_offer,
    os.id_user_agent_lead_referral,
    os.id_agent_lead_referral,
    so.id_buyer,
    so.id_house,
    os.id_user_agent,
    'TQC' AS sourcing_channel,
    (os.id_user_agent_lead_referral = os.id_user_agent) AS is_self_tqc,
    DATE(so.ts_offer_submitted) AS dt_offer,
    so.ts_offer_submitted,
    os.ts_agent_lead_referral_updated
FROM
    datalake_sale_offer_flows.offer_specialists AS os
INNER JOIN
    datalake_sale_offer.sale_offer AS so
        ON os.id_offer = so.id_offer
WHERE
    os.id_user_agent_lead_referral IS NOT NULL
```

If declaration uses year/month/day partitions, append:

```sql
    , YEAR(DATE(so.ts_offer_submitted)) AS year
    , MONTH(DATE(so.ts_offer_submitted)) AS month
    , DAY(DATE(so.ts_offer_submitted)) AS day
```

- [ ] **Step 2: EMR lint**

Apply `.cursor/skills/databricks-emr-sql-lint/SKILL.md` on the new `.sql`. Expected: zero findings (no `QUALIFY`).

- [ ] **Step 3: Write metadata YAML**

```yaml
database_name: datalake_agent_performance
table_name: agent_demand_referral
domain: Agents
owner: gustavo.rompe@quintoandar.com.br
description: |
  One row per For Sale offer attributed to a TQC agent (SalesFlow specialist
  kind AGENT_LEAD_REFERRAL on offer_specialists). Grain is the offer, not the
  invite. Daily agent counts compose downstream (AAREDE-509) as COUNT of offers
  per id_user_agent_lead_referral and dt_offer. Invite/link tables
  (agent_lead_referral, unified_lead_referral_flow) are not this fact.
columns:
  id_offer:
    lineage:
      - datalake_sale_offer_flows.offer_specialists.id_offer
    description: Primary key. Sale offer that has a TQC (AGENT_LEAD_REFERRAL) specialist assigned.
  id_user_agent_lead_referral:
    lineage:
      - datalake_sale_offer_flows.offer_specialists.id_user_agent_lead_referral
    description: EBDB user id of the agent credited as TQC on this offer. Use this as the agent key for daily performance.
  id_agent_lead_referral:
    lineage:
      - datalake_sale_offer_flows.offer_specialists.id_agent_lead_referral
    description: SalesFlow specialist id for the AGENT_LEAD_REFERRAL kind on the offer's sales flow.
  id_buyer:
    lineage:
      - datalake_sale_offer.sale_offer.id_buyer
    description: EBDB user id of the buyer who submitted the offer attributed to the TQC agent.
  id_house:
    lineage:
      - datalake_sale_offer.sale_offer.id_house
    description: House id of the listing on the TQC-attributed sale offer.
  id_user_agent:
    lineage:
      - datalake_sale_offer_flows.offer_specialists.id_user_agent
    description: EBDB user id of the AGENT specialist on the same offer (visit/deal agent). May differ from the TQC agent.
  sourcing_channel:
    description: Demand-sourcing program on this row. Always TQC in v1 (offer-level AGENT_LEAD_REFERRAL).
  is_self_tqc:
    lineage:
      - datalake_sale_offer_flows.offer_specialists.id_user_agent_lead_referral
      - datalake_sale_offer_flows.offer_specialists.id_user_agent
    description: True when the TQC agent is also the offer AGENT specialist. Activation metrics historically require this; this table does not filter on it.
  dt_offer:
    lineage:
      - datalake_sale_offer.sale_offer.ts_offer_submitted
    description: Calendar date of offer submit. Use as dt_reference when composing daily TQC offer counts (coincident with conversion, not invite date).
  ts_offer_submitted:
    lineage:
      - datalake_sale_offer.sale_offer.ts_offer_submitted
    description: Timestamp when the buyer submitted the sale offer.
  ts_agent_lead_referral_updated:
    lineage:
      - datalake_sale_offer_flows.offer_specialists.ts_agent_lead_referral_updated
    description: Last update of the AGENT_LEAD_REFERRAL specialist row. Attribution stamp; do not use as the daily count date.
```

- [ ] **Step 4: Validate metadata vs SQL**

```bash
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-metadata-files-exist
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-metadata-files-content
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-lineage-consistency
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-fair-metadata
```

Expected: pass on the new files.

- [ ] **Step 5: Commit (only if user asked)**

```bash
git add dags/agents/enrich_agent_performance/queries/enrich/agent_demand_referral.sql \
        dags/agents/enrich_agent_performance/metadata/enrich/agent_demand_referral.yml
git commit -m "$(cat <<'EOF'
feat(agents): add TQC offer-grain agent_demand_referral enrich

EOF
)"
```

---

### Task 3: Data quality + recon

**Files:**
- Create: `dags/agents/enrich_agent_performance/data_quality/enrich/agent_demand_referral.yml`

**Interfaces:**
- Consumes: table from Task 2
- Produces: Inmetro checks; recon SQL for Forno/analysts

- [ ] **Step 1: Write DQ YAML**

```yaml
---
table_name: datalake_agent_performance.agent_demand_referral
alert_channel: "#agents-data-alarms"
table_level_validations:
  has_size:
    greater_than: 0
    severity_level: Error
column_level_validations:
  id_offer:
    is_complete:
      severity_level: Error
    is_unique:
      severity_level: Error
  id_user_agent_lead_referral:
    is_complete:
      severity_level: Error
  dt_offer:
    is_complete:
      severity_level: Error
  sourcing_channel:
    is_complete:
      severity_level: Error
    is_contained_in:
      values: ['TQC']
      severity_level: Error
```

If `id_offer` is not unique in `offer_specialists` (duplicate TQC rows), change grain to `(id_offer, id_user_agent_lead_referral)` and `merge_on` accordingly **before** shipping. Check in Trino:

```sql
SELECT COUNT(*) AS n, COUNT(DISTINCT id_offer) AS n_offers
FROM datalake_sale_offer_flows.offer_specialists
WHERE id_user_agent_lead_referral IS NOT NULL
```

If `n > n_offers`, add `ROW_NUMBER` via subquery (EMR: wrap in CTE + `WHERE rn = 1`, not `QUALIFY`).

- [ ] **Step 2: Recon query (run in Trino after Forno; wrap SQL as CTE before table exists)**

```sql
WITH expected AS (
    SELECT COUNT(DISTINCT os.id_offer) AS n
    FROM datalake_sale_offer_flows.offer_specialists AS os
    INNER JOIN datalake_sale_offer.sale_offer AS so
        ON os.id_offer = so.id_offer
    WHERE os.id_user_agent_lead_referral IS NOT NULL
),
actual AS (
    SELECT COUNT(*) AS n
    FROM datalake_agent_performance.agent_demand_referral
)
SELECT expected.n AS n_expected, actual.n AS n_actual
FROM expected
CROSS JOIN actual
```

Expected: `n_expected = n_actual`.

AAREDE-507 compose example (do **not** persist):

```sql
SELECT
    id_user_agent_lead_referral AS id_user,
    dt_offer AS dt_reference,
    COUNT(*) AS demand__tqc_offers
FROM datalake_agent_performance.agent_demand_referral
GROUP BY
    id_user_agent_lead_referral,
    dt_offer
```

- [ ] **Step 3: Commit (only if user asked)**

```bash
git add dags/agents/enrich_agent_performance/data_quality/enrich/agent_demand_referral.yml
git commit -m "$(cat <<'EOF'
test(agents): add Inmetro uniqueness checks for agent_demand_referral

EOF
)"
```

---

### Task 4: Docs, Jira 507 No-Go, CI extras

**Files:**
- Modify: `docs/llm_context/business_entities/agents_programs.md` (TQC / TQA section and Tables row)
- Jira: AAREDE-507 comment (No-Go physical table)

**Interfaces:**
- Consumes: Phase 0 TQC definition
- Produces: analyst-facing SSOT text; ticket disposition

- [ ] **Step 1: Patch `agents_programs.md`**

Replace the TQC/TQA “no dedicated table / `agent_lead_referral`” guidance with:

- Performance TQC (Sale, offer credit): `datalake_agent_performance.agent_demand_referral` (after deploy) or `offer_specialists.id_user_agent_lead_referral IS NOT NULL`.
- Invite/link product (not TQC performance fact): `datalake_ebdb_clean.agent_lead_referral` and `datalake_tqc_referral.unified_lead_referral_flow`.
- Do not count invites as TQC offers. Do not count visits as TQC (that is VBBA).

- [ ] **Step 2: Regenerating `dags/dependencies.yaml` if SQL creates cross-DAG deps**

```bash
make dependencies-file
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-dependency-file-correctness
```

Expected: new edges from `enrich_sale_offer_flows` / `enrich_sale_offer` into `enrich_agent_performance`.

- [ ] **Step 3: Jira AAREDE-507**

Comment: **No-Go** as physical `fact_agent_demand_sourcing_daily`. Daily TQC offer counts compose in AAREDE-509 from `agent_demand_referral` (`dt_offer`, `id_user_agent_lead_referral`). Coincident date = offer submit, not invite, not specialist-updated.

- [ ] **Step 4: Forno (implementation phase, not this plan-only session)**

Mandatory before merge of the DAG PR: successful Forno Airflow run of `enrich_agent_performance`.

---

## Self-review

| Spec item | Task |
|---|---|
| AAREDE-504 table | Task 2 |
| Canonical sourcing_channel | `'TQC'` in SQL + DQ `is_contained_in` |
| BP / invite recon | Explicitly out of v1; 507 compose query in Task 3 |
| AAREDE-507 No-Go | Task 4 |
| Metadata/lineage | Task 2 |
| No Sheets re-union | Architecture + SQL sources |
| Event grain needed? | Yes: **offer event**, one table. No invite grain, no daily table |

## Execution

Plan saved. This session is **plan only**. When implementing: Subagent-Driven (recommended) or Inline Execution.
