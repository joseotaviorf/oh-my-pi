# Report template — table usage / deprecation analysis

Use this skeleton for `<slug>_usage_deprecation_analysis.md`. Replace placeholders.

**Reference example:** `dw_public__fact_house_listings_usage_deprecation_analysis.md` (full reader guidance).

**Agent rule:** sections **2–5** must include **all** explanatory blocks below (`What it measures`, glossary, `How to read`, `What it means`, `Read ≠ execution`, `How to read:`). Do not publish data-only sections.

---

```markdown
# Usage and deprecation analysis — `{schema}.{table}`

**Report date:** {report_date}  
**Primary window:** {start_90d} → {end_90d} (90 days)  
**Recent window:** {start_30d} → {end_90d} (30 days)  
**Sources:** `bi-etl-ejuice` repo scan · Databricks Spark SQL (Trino governance + Databricks audit)  
**Raw data (CSV):** [`{slug}_raw_data/`]({slug}_raw_data/)  
**SQL queries:** [`{slug}_usage_queries.md`]({slug}_usage_queries.md)

---

## Executive verdict

| Criterion | Result |
| --- | --- |
| **Immediate deprecation** | **{YES/NO} RECOMMENDED** |
| **Primary reason** | {one line} |
| **Substitute validated** | {only if replacement mode: `{replacement_schema}.{replacement_table}` — N/N OK} |
| **Suggested path** | {migration / monitor / none} |

---

## Deprecation analysis template

## 1. Pipeline dependencies

**Source:** repo scan — `.sql` files referencing `{schema}.{table}`.

### Consumers ({N} tables · {M} DAGs)

| DAG | Squad | DAG owner | Table owner (metadata) | Layer | Output table | Columns used |
| --- | --- | --- | --- | --- | --- | --- |
| ... | ... | ... | ... | ... | ... | `sk_contract, sk_house_listing, sk_region` |

**Owners (publish concrete values — never the generic metadata path footnote):**

- **Producer** `{schema}.{table}`: **`{producer_owner}`** (`{producer_dag}/metadata/{layer}/{table}.yml`).
- **Consumer** `{output_table}`: **`{output_table_owner}`** (`{consumer_dag}/metadata/{layer}/{output_table}.yml`) — one line per consumer when metadata exists.
- Reverse exports without metadata YAML (column shows —): single line — **Consumers without metadata YAML:** contact **DAG owner** / squad from the inventory table above.

**Columns used:** real columns from `{schema}.{table}` referenced in that SQL (comma-separated).
Never aliases (`fhl`) or vague join notes (`join fhl on sk_contract`).
Generated via `extract_pipeline_columns.py`; agent validates before publishing.

**By squad** — summary table.

### Section 1 summary

> **Verdict:** {emoji} **{label}** — {one short sentence: pipeline consumers; in replacement mode, include substitute headline (e.g. validated / pending Forno).}

<!-- INCLUDE ONLY IN REPLACEMENT MODE -->

### Can we replace with `{replacement_schema}.{replacement_table}`?

**Answer: {Yes/No}.** {One plain-language sentence — what each table stores and why the swap works or not.}

#### What each table stores

| | `{schema}.{table}` | `{replacement_schema}.{replacement_table}` |
| --- | --- | --- |
| **Role** | {business description — layer/pipeline} | {business description} |
| **Upstream source** | {schema.table source} | {schema.table source} |
| **Granularity** | 1 row per listing version (`sk_house_listing`) — multiple rows per property | Same, unless data proves otherwise |
| **Rows in prod** | {N} ({N} distinct SKs, if duplicates exist) | {N} |
| **Version columns** | {ts_listing_version_*, version, …} | {same or real differences} |

**Do not confuse:** *listing* = ad/listing version (`sk_house_listing`), not the property (`id_house`). Both tables may have multiple rows per property. The relevant comparison is **upstream source**, **SK coverage**, and **uniqueness** — do not assume the DW is "current state only" without checking metadata/SQL.

#### Do records match between the two tables?

We compare on grain **`{join_cols}`** ({grain_description}):

| Question | Answer | Period |
| --- | ---: | --- |
| Records that exist **only** in `{schema}.{table}` | **{N}** ({pct}% of source table) | {one-line summary from `replacement_equivalence_diff_by_period.csv`, or —} |
| Records that exist **only** in `{replacement_schema}.{replacement_table}` | **{N}** ({pct}% of substitute) | {one-line summary, or —} |
| Records present **in both** (on `{join_cols}`) | **{N}** ({pct_source}% of source · {pct_substitute}% of substitute) | — |

**Answer % rule:** denominator = exclusive count + in_both count **on that side** (from `replacement_equivalence_diff.csv`). Round to one decimal; use comma as decimal separator (e.g. `1,3%`). Do not repeat counts in the synthesis sentence below.

**Period column** (exclusive rows only; omit when `{period_col}` was not used):

- **One calendar year** → `All in {YYYY}` or `All in {YYYY} ({Mon–Mon})` when a few months dominate.
- **Multiple years** → `{min_year}–{max_year}; mostly {YYYY or YYYY–YYYY}` — one short phrase, no full breakdown.

{One plain-language synthesis sentence — partial overlap, identical, duplicate keys, row-level EXCEPT, etc.}

Numeric detail: [`replacement_equivalence_summary.csv`]({slug}_raw_data/replacement_equivalence_summary.csv) · [`replacement_equivalence_diff.csv`]({slug}_raw_data/replacement_equivalence_diff.csv) · [`replacement_equivalence_diff_by_period.csv`]({slug}_raw_data/replacement_equivalence_diff_by_period.csv) *(omit link if not run)* · [`replacement_equivalence_overlap_attributes.csv`]({slug}_raw_data/replacement_equivalence_overlap_attributes.csv) · [`replacement_equivalence_value_map.csv`]({slug}_raw_data/replacement_equivalence_value_map.csv) *(omit if not run)* · [`replacement_equivalence_near_miss.csv`]({slug}_raw_data/replacement_equivalence_near_miss.csv) *(omit if not run)*

#### What's different in the data today

<!-- PERFECT MATCH: 0 exclusives on both sides AND overlap attributes 100% (or single-key grain with 0 exclusives).
     Publish ONE short paragraph only — no Q&A table, no label map, no "What to do about … only in one table". -->

**Prod parity:** identical key coverage and field values on overlap ({list fields at 100%}). Migration is **`{schema}` → `{replacement_schema}` schema prefix** in SQL (+ Superset dataset refresh where applicable). Numeric audit: CSVs linked above.

<!-- PARTIAL MATCH: exclusives > 0 OR field drift on overlap. Keep short Q&A; add near-miss row when composite key includes ts_start. -->

Match table above = *which* keys/periods are exclusive and *when*. Below = field gaps, near-misses, labels, and next steps. **Do not repeat** exclusive counts here.

| Question | Answer |
| --- | --- |
| **Fields on in-both rows?** | List each `{compare_col}` with match **{N%}** (from `replacement_equivalence_overlap_attributes.csv`). |
| **Are exclusives near-misses?** | **Mostly yes** — see logic trees below. **Closest row** = on the other table, same `{entity_cols}`, the row whose `{ts_col}` is **nearest in time**; **≤60s** ⇒ near-miss. [`replacement_equivalence_near_miss.csv`]({slug}_raw_data/replacement_equivalence_near_miss.csv) |
| **Why exclusives exist?** | Different upstream pipelines — timestamp rounding, event order, or keys one side never emits. Mostly **{Period summary}**. |
| **If consumer reads Y?** | Describe join impact using the **actual consumer join keys** — not assumed timestamps unless the consumer SQL uses them. |

**Near-miss logic trees** *(publish when near-miss CSV was run; round % to integers; show **both** sub-group % and % of total exclusives on the ≤60s / >60s branches)*:

**Only in `{schema}.{table}` (~{N_source_excl} exclusives) — exact key absent in substitute:**

```
└── ~{N_source_excl} only in source
    ├── ~{pct_no_entity}% — `{entity_cols}` never appear together on substitute
    └── ~{pct_same_entity_diff_ts}% — same `{entity_cols}` on substitute, different `{ts_col}`
        ├── ~{pct_subgroup_le60}% of this sub-group (= ~{pct_total_le60}% of total) — nearest substitute `{ts_col}` ≤60s
        └── ~{pct_subgroup_gt60}% of this sub-group — `{ts_col}` >60s (incl. ~{pct_total_gt1d}% of total >1 day)
```

**Only in `{replacement_schema}.{replacement_table}` (~{N_substitute_excl} exclusives) — exact key absent in source:**

```
└── ~{N_substitute_excl} only in substitute
    ├── ~{pct_no_entity_sub}% — `{entity_cols}` never appear together on source
    └── ~{pct_same_entity_diff_ts_sub}% — same `{entity_cols}` on source, different `{ts_col}`
        ├── ~{pct_subgroup_le60_sub}% of this sub-group (= ~{pct_total_le60_sub}% of total) — nearest source `{ts_col}` ≤60s
        └── ~{pct_subgroup_gt60_sub}% of this sub-group — `{ts_col}` >60s (incl. ~{pct_total_gt1d_sub}% of total >1 day)
```

Denominators: `{pct_no_entity}` / `{pct_same_entity_diff_ts}` = % of **that side's exclusives**; `{pct_subgroup_*}` = % of the **same-entity-diff-ts sub-group**; `{pct_total_*}` = % of **all exclusives on that side**.

**Value map** (in-both rows; skip when all pairs are 1:1 — rename to the drifting column, e.g. `status_detail`):

| `{schema}.{table}` | `{replacement_schema}.{replacement_table}` | Rows |
| --- | --- | ---: |
| `{source_value}` | `{substitute_value}` | {N} |

{One line if ambiguous pairs exist.}

#### What to do about keys only in one table

<!-- Omit this entire subsection when 0 exclusives on BOTH sides (perfect match). -->

| Situation | Action |
| --- | --- |
| **~{N} only in DW** | Forno on `{consumer_table}` with enrich CTE + label map; accept or backfill if metrics drift. |
| **~{N} only in enrich** | Same Forno; owner validates new attributions. |
| **Near-miss `{ts_col}` (≤60s)** | Investigate timestamp/event-order rules before treating as true gap. |
| **Exclusives in {period}** | {One line — e.g. fix 2025 backfill before swap.} |
| **Before deprecating source** | Forno parity · value-map / `CASE` for drifting categorical cols · owner sign-off. |

#### Pipeline impact

{If 0 consumers: "No pipeline consumers — swap technically viable from a dependency standpoint."}

{If ≥1 consumer: simple table}

| Consuming table | Why it {accepts / does not accept} the substitute |
| --- | --- |
| `{output_table}` | {plain-language reason — missing columns, different grain, etc.} |

**Next step if you want to deprecate:** {concrete action}.

<!-- When a full-query test per consumer was run, add optional subsection
"#### SQL test per consumer" with rows/columns/nulls/checksum — only with real results. -->

<!-- END REPLACEMENT MODE -->

---

## 2. Superset — catalog dependency

**What it measures:** Superset charts whose **SQL references the table** — catalog snapshot in `datalake_superset` (no date filter). **Superset only** in this section. Metabase usage is in **section 3**.

| Term | Meaning |
| --- | --- |
| **Chart** | Saved visualization linked to a dataset whose SQL includes the table |
| **Dataset** | Superset data source that references the table in the lake |
| **ACTIVE / DEPRECATED** | Governance status in the Superset catalog (`entity_status`) |

| Metric | Value | Period |
| --- | ---: | --- |
| Charts in catalog | {distinct_charts} | Snapshot |
| ↳ Distinct datasets | {distinct_datasets} | Snapshot |
| ↳ ACTIVE | {active_charts} | Snapshot |
| ↳ DEPRECATED | {deprecated_charts} | Snapshot |
| Charts with views | {charts_with_views_90d} | Last 90 days (`last_90d_views`) |

Chart-by-chart list (name, URL, owners, views): [`superset_active_charts.csv`]({slug}_raw_data/superset_active_charts.csv)

### Section 2 summary

> **Verdict:** {emoji} **{label}** — {one short sentence with primary metric}.

---

## 3. Trino queries — executions

**What it measures:** queries that **actually read** the table, recorded in the Trino audit. Unlike section 2: here we count **execution**, not catalog presence of a chart.

**Windows:** **90d** `{start_90d} → {end_90d}` · **30d (recent)** `{start_30d} → {end_90d}` — all tables below include both when applicable.

**How to read the summary table**

| Column | Meaning |
| --- | --- |
| **Executions** | Distinct queries that touched the table in the period |
| **Distinct users** | Accounts that ran at least one query — **includes** Superset automatic refresh (e.g. user `default`) |
| **Avg users/day** | On average, how many distinct users queried per day (same user criteria above) — includes automatic refresh |
| **(30d)** | Same metrics in the last 30 days — recent usage |

### Summary by tool

| Tool | Executions (90d) | Distinct users (90d) | Avg users/day | Executions (30d) | Distinct users (30d) |
| --- | ---: | ---: | ---: | ---: | ---: |
| ... | ... | ... | ... | ... | ... |

<!-- INCLUDE ONLY WHEN `other` appears as a row in `trino_runtime_by_tool.csv` (omit entirely when absent) -->

**What `other` means:** literal value of `tool` in `datalake_trino.query_usage_information` (from the Trino query resource group). Covers executions **not** tagged as Superset, Metabase, Yellowbricks, CDP, or MCP — ad-hoc SQL, internal integrations, or JDBC clients without a dedicated label.

{One sentence from `trino_adhoc_executors.csv` **where `tool = 'other'`** (not `trino_adhoc_top.csv`, which mixes all ad-hoc tools): name the top executor(s) and what they imply — e.g. `datahub_trino_internal` → DataHub catalog/lineage automation; a human `@quintoandar.com.br` → ad-hoc analyst query. Prefix with **In this report:**}

<!-- END `other` note -->

### Superset — query origin (`query_reason`)

Source: `trino_superset_reason.csv` (includes 90d and 30d).

| Origin | 90d | 30d | What it means |
| --- | ---: | ---: | --- |
| `from dashboard` | ... | ... | Load or interaction via **dashboard** |
| `from chart` | ... | ... | Direct **chart** open (outside dashboard) |
| `from filter` | ... | ... | Filter or cross-filter applied on dashboard |
| `exploratory` | ... | ... | **SQL Lab** / ad-hoc exploration in Superset |

### Metabase — query origin

| Origin | 90d | 30d | What it means |
| --- | ---: | ---: | --- |
| `saved cards` | {metabase_executions_cards_90d} | {metabase_executions_cards_30d} | Executions of saved Metabase reports |
| `distinct saved cards` | {distinct_cards_90d} | {distinct_cards_30d} | Distinct saved reports executed in Metabase |
| `no card` | {metabase_executions_sem_card_90d} | {metabase_executions_sem_card_30d} | Executions via manual SQL in Metabase |

### Ad-hoc — top executors by tool (`yellowbricks`, `other`, `cdp`)

Source: `trino_adhoc_top.csv`. Ad-hoc SQL outside Superset/Metabase.

| Tool | User | 90d | 30d | What it means |
| --- | --- | ---: | ---: | --- |
| `{tool}` | `{executor_user}` | ... | ... | Ad-hoc SQL / agent / integration executions |

Full list: [`trino_adhoc_top.csv`]({slug}_raw_data/trino_adhoc_top.csv)

### Section 3 summary

> **Verdict:** {emoji} **{label}** — {one short sentence; max 2–3 key numbers}

---

## 4. Direct Databricks access — reads

**What it measures:** read access to the table in the **Databricks audit** — notebooks, jobs, Spark SQL, and service principals (`read_operations`). Complements section 3 (Trino executions).

**Windows:** **90d** `{start_90d} → {end_90d}` · **30d (recent)** `{start_30d} → {end_90d}`

**Read ≠ execution:** in section 3, an **execution** is one distinct SQL query in Trino (counted by `id_query` — “Run” or chart refresh). Here, a **read** is each event where the Databricks audit records a **READ** on the table (`generateTemporaryTableCredential`) — the platform authorized access for a notebook, job, or Spark SQL. **A single job or notebook can produce many reads** (Spark stages, distinct cells, daily scheduled reruns). Totals are **not** comparable 1:1 with Trino executions.

### Summary

| Metric | 90d | 30d | What it means |
| --- | ---: | ---: | --- |
| Reads | {reads_90d} | {reads_30d} | READ operations in Databricks audit — each event that records a table read (notebook, job, SQL); **not** distinct query count; one execution may produce many reads |
| Distinct readers | {readers_90d} | {readers_30d} | Distinct accounts (`user_email`) with at least one read |
| Avg readers/day | {avg_readers_day_90d} | — | Distinct readers (90d) ÷ 90 — daily reach proxy |

Source: `grain=TOTAL` row in [`databricks_reads.csv`]({slug}_raw_data/databricks_reads.csv).

### Top readers

| Reader | Reads (90d) | Reads (30d) | What it means |
| --- | ---: | ---: | --- |
| ... | ... | ... | Service principal / human user / service account (annotate top rows) |

Full list (top 25 + total): [`databricks_reads.csv`]({slug}_raw_data/databricks_reads.csv). All readers: [`databricks_all_readers.csv`]({slug}_raw_data/databricks_all_readers.csv)

### Section 4 summary

> **Verdict:** {emoji} **{label}** — {one short sentence; reads/readers 90d; top SP if applicable}.

---

## 5. Contacts — who to reach about deprecation

**What it measures:** who to contact about **consumption** of the table — downstream pipeline, BI, and Databricks. **Does not include** the producer of the evaluated table (section 1).

### Pipeline — SQL consumers

Only DAGs whose `.sql` **reads** the table. Owner = output table metadata when it exists; otherwise squad/DAG owner.

| Contact | DAG | Consuming tables |
| --- | --- | --- |
| {contact} | `{dag}` | {tables} |

Source: [`pipeline_consumers.csv`]({slug}_raw_data/pipeline_consumers.csv)

### Superset — catalog owners

Source: [`superset_active_contacts.csv`]({slug}_raw_data/superset_active_contacts.csv)

**How to read:**

- **Contact** — chart owner in the Superset catalog (business, technical, or last owner).
- **Charts** — distinct ACTIVE charts whose dataset SQL references the table and had views in the period (source: `datalake_superset.logs`).

| Contact | Charts (90d) | Charts (30d) |
| --- | ---: | ---: |
| ... | ... | ... |

To see **which charts** (name + URL): [`superset_active_charts.csv`]({slug}_raw_data/superset_active_charts.csv)

### Metabase — card creators with executions

Source: [`metabase_card_contacts.csv`]({slug}_raw_data/metabase_card_contacts.csv)

**How to read:**

- **Contact** — card creator (`report_card`); not necessarily who executed.
- **Cards (90d)** — distinct Metabase reports whose SQL **read** the table in the Trino audit in the last 90 days.
- **Executions** — distinct queries (`id_query`) from those cards that touched the table; includes scheduled refresh and executions by other users.

| Contact | Cards (90d) | Executions (90d) | Executions (30d) |
| --- | ---: | ---: | ---: |
| ... | ... | ... | ... |

To see **which cards** (name + URL): [`metabase_active_cards.csv`]({slug}_raw_data/metabase_active_cards.csv)

### Databricks — direct reads (top humans)

Source: [`databricks_all_readers.csv`]({slug}_raw_data/databricks_all_readers.csv)

**How to read:**

- **Contact** — `user_email` in Databricks audit: human (`@`), service principal (UUID), or service account.
- **Reads** — READ operations in `daily_table_usage_per_user`; not distinct query count; one notebook or job may generate multiple reads.

| Contact | Reads (90d) | Reads (30d) |
| --- | ---: | ---: |
| ... | ... | ... |

Full list (humans, SPs, and service accounts): [`databricks_all_readers.csv`]({slug}_raw_data/databricks_all_readers.csv)

### Ad-hoc — SQL executors (Trino)

Source: [`trino_adhoc_executors.csv`]({slug}_raw_data/trino_adhoc_executors.csv)

**How to read:**

- **Tool** — channel in Trino audit (`yellowbricks`, `other`, `cdp`, `mcp`); SQL outside Superset/Metabase.
- **Contact** — `executor_user` who ran the query; may include service accounts and automated agents.
- **Executions** — distinct queries (`id_query`) that read the table; includes ad-hoc SQL and integrations.

| Tool | Contact | Executions (90d) | Executions (30d) |
| --- | --- | ---: | ---: |
| ... | ... | ... | ... |

Full list: [`trino_adhoc_executors.csv`]({slug}_raw_data/trino_adhoc_executors.csv)

> **Verdict:** {emoji} **{label}** — {one-sentence synthesis; e.g. "broad outreach: pipeline, Superset, …"}.

---

## Decision matrix (go / no-go)

Final checklist: each **gate** tests one usage dimension. **Passed = YES** only if the minimum criterion was met. **Any NO** prevents immediate deprecation.

| # | What it checks | To deprecate | Current situation | Ref. | Passed? |
| --- | --- | --- | --- | --- | --- |
| 1 | Pipeline consumption | 0 consumers | ... | §1 | ... |
| 2 | Superset ACTIVE charts | 0 charts w/ views | ... | §2 | ... |
| 3 | Trino usage (reach) | < 2 users/day stable | ... | §3 | ... |
| 4 | Databricks reads | 0 or migrated | ... | §4 | ... |
| 5 | Automated job (SP) | Job identified and migrated | ... | §4 | ... |
| 6 | Stale table | No use > 6 months | ... | §3–4 | ... |
<!-- gate 6 ONLY in replacement mode — renumber "Stale table" to 7 when present -->
<!-- | 6 | Substitute + equivalence | Validated | ... | §1b | ... | -->
<!-- | 7 | Stale table | No use > 6 months | ... | §3–4 | ... | -->
<!-- end -->

> **Result:** **{N}/{total}** gates · **Deprecation {blocked/allowed}.**

```
---

## Section rules

### Verdict pattern (sections 1–5)

Each section ends with a blockquote in fixed format:

```markdown
> **Verdict:** {emoji} **{Label}** — {sentence with key numbers}
```

| Emoji | Label | When to use |
| --- | --- | --- |
| 🔴 | **Blocks deprecation** | Material dependency or active usage in this dimension |
| 🟡 | **Attention** | Relevant usage with a gap to investigate (e.g. unidentified SP/job) or mixed signal |
| 🟢 | **Does not block deprecation** | No material usage in this dimension |

Rules:

- **One short sentence** after the label — max 2–3 key numbers; details stay in tables and CSVs.
- Use **only** these three labels — do not invent ad hoc labels (e.g. "Broad outreach").
- Section 5: same format; contact synthesis uses 🔴 when outreach confirms a blocker.
- Executive verdict (top) remains YES/NO table — no emoji.

- **Gate numbering:** usage-only = gates **1–6** with no gaps. Replacement mode = insert gate **6** (equivalence) and renumber stale to **7**.
- **Replacement subsection** (section 1 "Can we replace with `{replacement_schema}.{replacement_table}`?") — only when user activated replacement mode; **always after** the section 1 Verdict blockquote.
- **Gate 6** — only in replacement mode.
- **No** standalone **Recommended plan**, **Known gaps**, or **Metrics glossary** section — definitions stay inline in sections 1–5.
- **Reader guidance (sections 2–5) — mandatory, never omit:**
  - §2: **What it measures** + **Term \| Meaning** table before metrics.
  - §3: **What it measures** + **Windows** + **How to read the summary table** before data; **What `other` means** paragraph **only when** `other` is a row in `trino_runtime_by_tool.csv` (omit when absent) — cite executors from `trino_adhoc_executors.csv` filtered to `tool = 'other'`, not `trino_adhoc_top.csv`; origin/ad-hoc tables include **What it means** column.
  - §4: **What it measures** + **Windows** + full **Read ≠ execution** paragraph before data; summary and top readers include **What it means** column.
  - §5: **What it measures** at section top; each contact subsection starts with **How to read:** bullets before its table.
  - Reference: `dw_public__fact_house_listings_usage_deprecation_analysis.md`.
- **Usage-only mode:** no volumetry or narrative about sibling/canonical tables (e.g. do not compare
  `dw_public.*` vs `dw_rent.*` unless user named a replacement table). Section 1 covers only SQL files referencing the
  requested table.
- **Engine note in header:** `Databricks Spark SQL (governance via Commands API)` — not Trino MCP.
- **Headings (sections 1–5):** numbered section = `##`; subsections = `###` (e.g. Consumers, Summary by tool, Pipeline). Never `####` for subsection titles.
- **Queries doc link label:** `SQL queries` (not "Queries used").
