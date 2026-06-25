---
name: map-table-usage
description: >-
  Map production usage of a lake/DW table for deprecation or migration decisions:
  pipeline consumers (repo scan), Superset catalog, Trino runtime
  executions, and Databricks direct reads. Produces a deprecation-analysis report,
  queries appendix, and CSV raw data. Optional replacement-equivalence section
  when the user asks to compare a substitute table. Use when the user says "Map the
  usage of table X" or "Map the usage of table X and its replacement by Y".
---

# Map Table Usage

End-to-end playbook to answer: **who uses table X, how much, and can we deprecate it?**

Reference material (read on demand):

- SQL templates → [reference/queries.md](reference/queries.md)
- Report skeleton → [reference/report-template.md](reference/report-template.md)
- Queries doc → generate via `scripts/export_queries_md.py` (see Step 5)

---

## Activation (strict)

| User says | Replacement section | Equivalence tests |
| --- | --- | --- |
| **Map the usage of table X** | **Skip** | **Skip** |
| **Map the usage of table X and its replacement by Y** | **Include** | **Include** |

Parse `X` and `Y` as `schema.table` (e.g. `dw_public.dim_house_listing`, `dw_rent.dim_house_listing`).

If the table name is ambiguous, ask once before proceeding.

---

## Parameters (defaults)

| Parameter | Default | Notes |
| --- | --- | --- |
| Window 90d | today − 90d → today | Primary KPI window |
| Window 30d | today − 30d → today | Recent trend |
| UC catalog | `quintoandar_prod` | Governance tables live here on Databricks |
| Output dir | `table_usage_map/<schema>__<table>/<YYYY-MM-DD>/` | Create under repo root |

**File slug:** `<schema>__<table>` (e.g. `dw_public__dim_house_listing`).

**Deliverables** (always):

1. `<slug>_usage_deprecation_analysis.md` — main report
2. `<slug>_usage_queries.md` — full SQL + index (via `export_queries_md.py`; see Step 5)
3. `<slug>_raw_data/*.csv` — one CSV per query result + `pipeline_consumers.csv` (Pipeline)

Do **not** commit deliverables unless the user asks.

---

## Execution engine (Databricks only)

Governance queries (report sections 2–4) **must** run on **Databricks Spark SQL** via the official batch script —
same Commands API 1.2 pattern as [databricks-emr-migration](../databricks-emr-migration/SKILL.md)
(`DatabricksAPI`, profile `PROD`, user-supplied cluster).

**Do not** run governance SQL through Trino MCP — it returns `PERMISSION_DENIED` on
`datalake_trino.*`, `datalake_superset.*`, and related UC tables.

### Cluster (mandatory — ask the user)

Before sections 2–4, **always ask** for a running Databricks **all-purpose** cluster id. Pass it as
`--cluster`. Do **not** auto-discover clusters (`databricks clusters list`) or silently reuse
session files from other skills.

### Batch runner

```bash
uv run python .cursor/skills/map-table-usage/scripts/run_governance_batch.py \
  --schema dw_public \
  --table fact_house_listings \
  --cluster <CLUSTER_ID> \
  --profile PROD \
  --catalog quintoandar_prod \
  --output-dir table_usage_map/dw_public__fact_house_listings/$(date +%Y-%m-%d)
```

Output goes directly to `{output_dir}/{slug}_raw_data/*.csv` — one file per query result.
Date windows, catalog, and cluster go in the **analysis header** and `{slug}_usage_queries.md`
(not auxiliary CSVs). Reuses `DatabricksAPI` from
`.cursor/skills/databricks-emr-migration/databricks_client.py`.

**Lean query set (6 SQL + post-processing, ~1–1.5 min total):**

| Query / artifact | Report section | Gates / report |
| --- | --- | --- |
| `superset_catalog_stats` | 2 — Superset (catalog) | charts, datasets, ACTIVE/DEPRECATED |
| `superset_active_charts` | 2 — Superset (catalog) | chart-by-chart list: name, URL, owners |
| `trino_usage_bundle` | 3 — Trino, 5 — Contacts | 1 scan → 4 derived Trino CSVs |
| `metabase_active_cards` | 5 — Contacts | card-by-card list: name, URL, creator |
| `databricks_all_readers` | 4 — Databricks, 5 — Contacts | all readers; generates `databricks_reads.csv` |
| `superset_active_contacts` | 5 — Contacts | owners of ACTIVE charts with views |

**Derived (Python, no extra SQL):** `trino_runtime_by_tool`, `trino_superset_reason`,
`metabase_summary`, `trino_adhoc_executors`, `trino_adhoc_top`, `metabase_card_contacts`,
`databricks_reads` — see `postprocess_csvs.py`.

Removed vs v13: 5 Trino scans → 1 bundle; `metabase_top_cards`, `trino_adhoc_top`,
`metabase_card_contacts`, `databricks_reads` as separate queries.

Re-run after partial failure: add `--skip-existing` to keep successful CSVs.

**Critical UC paths** (common mistakes):

| Wrong | Correct |
| --- | --- |
| `hive.datalake_databricks.daily_table_usage_per_user` | `{catalog}.datalake_databricks.daily_table_usage_per_user` |
| `datalake_databricks.databricks.*` | `{catalog}.datalake_databricks.*` |
| `query_reason` on `query_information` | use `query_usage_information.query_reason` |

**Filter keys** for table `schema.table`:

- Trino governance: `database_name = '<schema>' AND table_name = '<table>'`
- Superset catalog: `id_lake_table = '<schema>.<table>'`
- Databricks audit: `table_full_name = '{catalog}.<schema>.<table>'`

Use `{schema}`, `{table}`, `{catalog}`, `{start_90d}`, `{end_90d}` placeholders from
[reference/queries.md](reference/queries.md).

---

## Workflow checklist

Copy and track:

```
Map table usage progress:
- [ ] 0. Parse X (and Y if replacement mode)
- [ ] 1. Pipeline — repo scan + `extract_pipeline_columns.py`
- [ ] 1b. [replacement only] Define grain (`join_cols`, `compare_cols`) → equivalence SQL + optional period / value_map / near-miss CSVs
- [ ] Ask user for Databricks all-purpose cluster id
- [ ] 2–4. Run run_governance_batch.py → CSVs in `{slug}_raw_data/`
- [ ] 5. Contacts — report section 5 (CSVs per channel; no consolidated merge)
- [ ] 6. Write report + `export_queries_md.py` → queries doc
- [ ] 7. Verdict + go/no-go matrix
```

---

## Step 0 — Parse target

From `schema.table` derive:

- `table_full_uc` = `{catalog}.schema.table`
- `id_lake_table` = `schema.table`
- Output slug = `schema__table`

---

## Step 1 — Pipeline consumers (repo)

**Goal:** DAGs whose `.sql` files reference the table (production change list).

```bash
rg -l '<schema>\.<table>' dags/ --glob '*.sql'
```

For each file, extract: DAG folder, squad (from path), output layer/table, **columns used**.

### Column extraction (mandatory)

Run the helper — do **not** hand-write "join fhl" or alias shorthand:

```bash
uv run python .cursor/skills/map-table-usage/scripts/extract_pipeline_columns.py \
  --schema dw_public \
  --table fact_house_listings \
  --output table_usage_map/<slug>/<date>/<slug>_raw_data/pipeline_consumers.csv
```

**Report column name:** `Columns used` (not "Primary use"). Also export **`dag_owner`** (declaration) and **`output_table_owner`** (metadata YAML when it exists).

**Format rules:**

| Rule | Example |
| --- | --- |
| List real `{schema}.{table}` column names | `sk_contract, sk_house_listing, sk_region` |
| Comma-separated, snake_case, sorted | `sk_contract, sk_owner, sk_region` |
| **Never** use SQL aliases (`fhl`, `rf`, …) | ~~join fhl~~ · ~~fhl → sk_region~~ |
| **Never** describe join mechanics only | ~~join on sk_contract~~ |
| Include JOIN keys, SELECT, WHERE, GROUP BY refs | all `alias.col` where alias binds to target table |
| Review script output | drop false positives; add missed cols after reading SQL |

Static analysis is best-effort — agent validates against the `.sql` when the script marks
`(none detected — review manually)` or lists suspicious names.

Optionally cross-check `dags/dependencies.yaml` and invoke
[impact-analysis](../impact-analysis/SKILL.md) for metadata/declaration deps — pipeline
section focuses on **SQL consumers**.

**Report section 1:** inventory table (with **Columns used**) → **concrete owner lines** (Producer + Consumer per metadata file) → **Verdict** (before the replacement subsection) → per-section verdict.

**Owners in §1 (mandatory):** after the consumer table, list **real `owner` values** from metadata YAML — never publish the template footnote `` `owner` in `metadata/<layer>/<table>.yml` ``. Pattern: **Producer** `{schema}.{table}`: **`{email or squad}`** (`{path}`); **Consumer** `{output_table}`: **`{owner}`** (`{path}`) for each consumer with metadata; one summary line for reverse exports without metadata (column — → DAG owner / squad).

### Step 1b — Replacement equivalence (ONLY if user named Y)

**Skip entirely** unless activation phrase includes **"and its replacement by Y"**.

**Step 1b.0 — Define grain (mandatory before any SQL):**

1. Read metadata YAML + producer SQL for source and substitute.
2. Document `{grain_description}`, `{join_cols}`, `{compare_cols}` in the report.
3. Build `{grain_key_expr}` and `{join_predicate}` from `{join_cols}` — **never assume** fixed columns like `status` or `city_group`.
4. Optionally set `{period_col}`, `{entity_cols}`, `{ts_col}` for period breakdown / near-miss.

Templates: [reference/queries.md §1b](reference/queries.md#1b-replacement-equivalence) (generic) · examples A–D at end of §1b.

For each pipeline SQL consumer:

1. Run full query with `{schema}.{table}` and with `{replacement_schema}.{replacement_table}`.
2. Compare **volume** (row count), **null counts**, and **checksum** per scalar output column.
3. Prefer **full query**; if too heavy (>30 min), test the **fragment** that references the
   table and document `scenario=fragment_only` + reason.
4. If the test **was not run**, do **not** invent an OK/FAIL result — use **static analysis**
   (columns, join keys, grain) in the per-consumer table; state why the test was skipped.

Templates: [reference/queries.md §1b](reference/queries.md#1b-replacement-equivalence).

**Equivalence SQL (always):** summary · diff on `{grain_key_expr}` · overlap on `{compare_cols}`.

**Optional SQL:** row-level `EXCEPT` (passthrough mirrors) · `diff_by_period` (when `{period_col}` set and exclusives > 0) · `value_map` (categorical drift) · near-miss (when `{entity_cols}` + `{ts_col}` defined and exclusives > 0).

**Report section 1:** add subsection **"Can we replace with `{replacement_schema}.{replacement_table}`?"** **after** the section 1 Verdict. Structure for readability:

1. **Answer: Yes/No** — one plain-language sentence upfront.
2. **What each table stores** — side-by-side comparison (role, granularity, **`{join_cols}` grain**, row counts).
3. **Do records match?** — table with **Question · Answer · Period** (Answer = count + **% of that table**); state the **grain** in plain language (`{grain_description}`).
4. **What's different in the data today** — **Prod parity** one-liner when 0 exclusives + 100% fields / row `EXCEPT`; else short Q&A (+ near-miss row when run) · value map if categorical drift · “What to do …” **only if exclusives > 0**.
5. **Pipeline impact** — one row per consumer: table + why it accepts or rejects the substitute.

Run `replacement_equivalence_diff_by_period` when `{period_col}` is set and exclusives > 0; save CSV; derive **Period** text for the match table.

When exclusives > 0 **and** `{entity_cols}` + `{ts_col}` are defined, run **near-miss** SQL → `replacement_equivalence_near_miss.csv`. In the report: add the **Near-miss logic trees** block from [report-template.md](reference/report-template.md) (ASCII tree, two sides, both denominators on the ≤60s / >60s branches). Do **not** compress into a single prose sentence.

**What's different in the data today — branching:**

| Condition | Publish |
| --- | --- |
| **0 exclusives** + overlap fields **100%** | **One short “Prod parity” paragraph** — no Q&A table, no label map, **omit** “What to do about … only in one table”. |
| **Exclusives or field drift** | Short Q&A (incl. near-miss row when applicable) → label map (if label drift) → “What to do …” (only when exclusives > 0). |

Label map **before** “What to do …” when both are present. Keep answers to one line each.

Use **full table names** everywhere. Optional SQL test results only when actually executed. Never pair "Not executed" with invented OK/FAIL.

---

## Step 2 — Superset catalog (dependency in SQL)

**Prerequisite:** governance batch completed on Databricks (see **Execution engine**).

**Goal:** Superset products that **have the table in dataset SQL** — independent of run volume.

| Source | Governance table | Metric |
| --- | --- | --- |
| Superset | `{catalog}.datalake_superset.lake_tables_usage` + `slices` | distinct charts, ACTIVE vs DEPRECATED, views 90d |

Queries: [reference/queries.md §2](reference/queries.md#2-bi-catalog).

**Report section 2:** Superset catalog only — glossary (chart, dataset), **Period** column (snapshot +
`last_90d_views`). **Do not** put Metabase here (no catalog mapping in this skill).

---

## Step 3 — Trino runtime (executions)

**Prerequisite:** governance batch on Databricks (Trino **audit tables**, not Trino MCP).

**Goal:** real SQL executions that read the table in the last 90d — all tools, including Metabase.

| Source | Governance table | Metric |
| --- | --- | --- |
| All tools | `query_information` + `query_usage_information` | execs, users, avg users/day by tool |
| Metabase | same + `id_metabase_card` | distinct cards, card executions (`metabase_summary.csv`) |

Join:

- `{catalog}.datalake_trino.query_information` (table filter)
- `{catalog}.datalake_trino.query_usage_information` (`tool`, `query_reason`, executor)

**Primary KPI (human adoption):** distinct users **per day**, not total query count.

| Metric | Meaning |
| --- | --- |
| Avg users/day | AVG daily distinct `COALESCE(session_user, user)` by tool |
| Avg queries/day | total executions ÷ 90 (includes scheduled Superset refresh) |
| query_reason | Superset: `from dashboard`, `from filter`, `from chart`, `exploratory` |

**Human vs automatic (Superset):** executor `default` ≈ scheduled refresh (~automatic); email ≈ human.

Queries: [reference/queries.md §3](reference/queries.md#3-trino-runtime).

**Report section 3:** title **Trino queries — executions** (no "(90d)" only in title); 90d and 30d windows in
intro text. After **Summary by tool**, add **What `other` means** only when `other` appears in `trino_runtime_by_tool.csv` — explain the Trino resource-group label and cite top executors **with `tool = 'other'`** from `trino_adhoc_executors.csv` (not `trino_adhoc_top.csv`, which is the global top 15 across all ad-hoc tools); omit the paragraph when `other` is absent. Verdict: Superset + yellowbricks + Metabase, 90d **and** 30d metrics.

---

## Step 4 — Databricks direct reads

**Prerequisite:** governance batch on Databricks.

**Goal:** reads **outside Trino** — notebooks, jobs, SPs.

Table: `{catalog}.datalake_databricks.daily_table_usage_per_user`

| Column | Use |
| --- | --- |
| `user_email` | person or service-principal UUID |
| `read_operations` | READ operations in Databricks audit per day/user — **not** distinct query count |
| `table_full_name` | must match `table_full_uc` exactly |

Queries: [reference/queries.md §4](reference/queries.md#4-databricks-direct-reads).

**Report section 4:** title **— reads**, 90d/30d windows, **Read ≠ execution** paragraph,
summary table `| Metric | 90d | 30d | What it means |`, top readers
`| Reader | Reads (90d) | Reads (30d) | What it means |` (`databricks_reads.csv`).
Verdict with 90d **and** 30d + top SP if present (identify job manually if needed).

---

## Step 5 — Contacts (outreach)

**Goal:** who to contact by access type before deprecating.

**Batch:** `superset_active_contacts`, `metabase_card_contacts`, `metabase_active_cards`,
`databricks_all_readers` (+ pipeline via `extract_pipeline_columns.py`).

**Report section 5:** consumers only (exclude producer of the evaluated table — section 1).

| Subsection | Summary CSV | Detail CSV (name + URL when available) |
| --- | --- | --- |
| Pipeline | `pipeline_consumers.csv` | — |
| Superset | `superset_active_contacts.csv` | `superset_active_charts.csv` |
| Metabase | `metabase_card_contacts.csv` | `metabase_active_cards.csv` |
| Ad-hoc (Trino) | top in report | `trino_adhoc_executors.csv` |
| Databricks | top humans in report | `databricks_all_readers.csv` |

**Metabase (section 5):** include **How to read** as bullet points, in column order (Contact → Cards → Executions); one bullet for Executions (90d and 30d share the same definition).

**Superset (section 5):** same **How to read** pattern (Contact → Charts); Charts (90d) and Charts (30d) columns in `superset_active_contacts.csv`.

**Databricks (section 5):** same **How to read** pattern (Contact → Reads); Reads (90d) and Reads (30d) columns in `databricks_all_readers.csv`.

**Ad-hoc (section 5):** same **How to read** pattern (Tool → Contact → Executions); full list in `trino_adhoc_executors.csv` (`yellowbricks`, `other`, `cdp`, `mcp`).

**Do not include:** `trino_runtime_contacts` (redundant with Superset/yellowbricks in sections 3 and 5),
`deprecation_contacts.csv` (consolidated merge removed).

SPs and Databricks service accounts appear in `databricks_all_readers.csv` and section 4 (top readers).

---

## Step 6 — Report and queries doc

1. Fill [reference/report-template.md](reference/report-template.md).
2. Create `<slug>_usage_queries.md` via `export_queries_md.py` (or equivalent) with:
   - Link **Analysis report** (never use "Companion")
   - Parameters (dates, catalog, cluster)
   - Index **query → CSV → report section** (never use column header `§` — write "Report section")
   - **Full SQL** for each governance query (copied from `governance_queries.py` with dates substituted)
   - **Do not** include Pipeline section or reproduction appendix — the index is enough for Pipeline (no SQL)

```bash
uv run python .cursor/skills/map-table-usage/scripts/export_queries_md.py \
  --schema <schema> --table <table> --cluster <CLUSTER_ID> \
  --output table_usage_map/<slug>/<YYYY-MM-DD>/<slug>_usage_queries.md \
  --end-date <YYYY-MM-DD>
```

**Report header** includes windows, link to `{slug}_raw_data/` and link to
`{slug}_usage_queries.md`. **Do not** create a **Raw data** section — avoids repeating the header.

**Metric distribution:** embed definitions inline in sections 1–5 (no final glossary).

**Mandatory reader guidance (never omit in sections 2–5):** every published report must include the explanatory blocks from [reference/report-template.md](reference/report-template.md) — not just data tables. Checklist:

| Section | Required blocks |
| --- | --- |
| **2 Superset** | **What it measures** paragraph · **Term \| Meaning** glossary table · metrics table · verdict |
| **3 Trino** | **What it measures** · **Windows** line · **How to read the summary table** (Column \| Meaning) · summary by tool · **What `other` means** (conditional — only if `other` ∈ `trino_runtime_by_tool.csv`) · Superset/Metabase origin tables with **What it means** column · ad-hoc intro + **What it means** column · verdict |
| **4 Databricks** | **What it measures** · **Windows** · **Read ≠ execution** paragraph (full wording from template) · summary table with **What it means** · top readers with **What it means** · verdict |
| **5 Contacts** | **What it measures** · each subsection with **How to read:** bullets before the contact table · verdict |

Do **not** publish reports that jump straight from the section heading to numeric tables.

**Headings:** numbered sections 1–5 = `##`; subsections (Consumers, Summary by tool, Pipeline, etc.) = `###`. Never `####` for subsection titles.

**Verdict (sections 1–5):** blockquote `> **Verdict:** {emoji} **{Label}** — …`. **One short sentence** (max 2–3 key numbers). Labels: 🔴 Blocks · 🟡 Attention · 🟢 Does not block.

**Do not** include a "Known gaps" section unless the user explicitly asks.

---

## Step 7 — CSV raw data

Governance CSVs are written **directly** by `run_governance_batch.py` under
`{output_dir}/{slug}_raw_data/` — **6 SQL queries** + derived CSVs via `postprocess_csvs.py`.
No `_index.csv` or `_run_meta.csv`.

| File | Content |
| --- | --- |
| `{query_name}.csv` | Tabular result of the SQL query |
| Derived CSVs | `trino_runtime_by_tool`, `databricks_reads`, etc. — see `postprocess_csvs.py` |
| `pipeline_consumers.csv` | Columns used + `dag_owner` per consumer SQL (Pipeline / section 1) |

If any query fails, the batch **exits with error** — do not publish partial governance CSVs.

---

## Step 8 — Go / no-go matrix

**Matrix:** 1-sentence intro (what is a gate / Passed?) + table with columns `What it checks | To deprecate | Current situation | Ref. | Passed?`. Result in blockquote: `{N}/{total} gates · Deprecation {blocked/allowed}.`

**Do not** include **Recommended plan** or final glossary — metrics are already in sections 1–5.

| # | Gate | Typical deprecate threshold |
| --- | --- | --- |
| 1 | Pipeline prod consumers | 0 |
| 2 | Reverse export / critical product | 0 or migrated |
| 3 | Superset ACTIVE (charts w/ recent views) | 0 |
| 4 | Human users/day (Trino), stable 90d | < 2 |
| 5 | Automated Databricks job unidentified | 0 or migrated |
| 6 | Usage stale | no use > 6 months |
| 6r | **Substitute validated** | **Replacement mode only** — insert as gate 6; renumber stale to 7 |

**Usage-only mode:** gates **1–6** sequential (no substitute). **Replacement mode:** insert gate 6 (substitute) and renumber stale to **7** (total 7 gates).

Score gates PASS/FAIL · state **Deprecation recommended?** YES/NO with primary blockers.

---

## Parallelism and performance

- Use `run_governance_batch.py` — **6 SQL queries** + post-processing, default timeout 300s/query.
- Re-run with `--skip-existing` after partial batches.
- Repo scan: one `rg` pass is enough for Pipeline (section 1) inventory.

---

## Forbidden in usage-only mode

When the user did **not** say *"and its replacement by Y"*:

- **Do not** run volumetry or row-count queries on sibling/canonical tables (e.g. `dw_rent.*` when
  mapping `dw_public.*`).
- **Do not** mention substitute tables, canonical schemas, or "migration to dw_rent" unless the user
  explicitly named a replacement.
- **Do not** add section-1 subsections comparing public vs rent volumes.
- Pipeline (section 1) lists **only** consumers of the **requested** `schema.table`.

---

## Related skills

| Skill | When |
| --- | --- |
| [databricks-emr-migration](../databricks-emr-migration/SKILL.md) | Databricks Commands API client + cluster rules |
| [impact-analysis](../impact-analysis/SKILL.md) | Broader rename/removal impact (metadata + declarations) |
| [find-stale-dags](../find-stale-dags/SKILL.md) | Complementary — stale **DAG** vs stale **table usage** |

---

## Example activations

**Usage only:**

```
Map the usage of table dw_public.dim_house_listing
```

**Usage + replacement:**

```
Map the usage of table dw_public.dim_house_listing and its replacement by dw_rent.dim_house_listing
```
