# {readable_doc_title}: {metastore_schema}

## People Data Catalog

*{Optional section — place **before** [Contents](#contents). **Delete** this entire section **and** its **Contents** entry if the team wants no catalog pointer in git at all (GitHub-only readers then have no in-repo link to the hub).}*

*{**Do not** duplicate catalog fields (**Scope**, **Progress**, **Owner**, **Confidence level**, **Document updated at**, etc.) as a **markdown table** in this file. That table is **not** linked to the **People Data Catalog** **Confluence Database** and would **diverge** from the source of truth. **Canonical metadata** lives in the Database on the hub page; editors maintain rows and **Document updated at** there.}*

*{**New catalog rows:** In the Database, use **Progress** **`In review`** and **Confidence level** **`Low`** until owners change them. **Creating the row**, pasting the **database / row link** on this schema’s **Confluence** page, and **re-embedding** that link after a full-body Markdown sync are **manual** (Atlassian MCP does not create or edit Databases; **`updateConfluencePage`** can drop embeds).}*

*{When the section ends with a **catalog row** link (deep link to a Database entry), finish the explanatory sentence, add a **blank line**, then put `[link text](row-url)` on its **own** paragraph—clearer spacing in GitHub and Confluence than an inline link at the end of the same line.}*

This schema’s wiki page is listed under **[People Data Catalog](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/4635951235/People+Data+Catalog)** in Confluence, together with other People DW 2.0 datasets. **On the wiki page** for this dataset, **embed or link** the Catalog database (or this schema’s row) so readers see live fields—use the link or embed URL from Confluence after the row exists.

## Contents

- [People Data Catalog](#people-data-catalog) *{optional — remove with the section above if unused}*
- [Description](#description)
- [Scope](#scope)
- [Future scope](#future-scope) *{remove this line if you omit the section}*
- [Out of scope](#out-of-scope)
- [Tables](#tables)
- [Data model](#data-model)
- [Full data model on GitHub](#full-data-model-on-github) *{optional — remove Contents line and subsection if you omit the companion file}*
- [Executive summary](#executive-summary)
- [Business logic](#business-logic)
- [{Metric family} (calculation rules)](#{anchor-for-example-tenure-metrics-calculation-rules}) *{optional — remove this line if you omit the subsection}*
- [Data dictionary](#data-dictionary)
- [How to use](#how-to-use)
- [Sensitivity and access](#sensitivity-and-access)

---

## Description

*{One paragraph: what **`{metastore_schema}`** delivers for the business — main topics, value, and product-facing source names (e.g. PIN). Keep distinct from [Executive summary](#executive-summary); avoid repeating the full grain list here.}*

## Scope

*{**✅** bullets — what **is** in this schema/DAG: entities, time/history behavior at a high level, and main reporting uses. Mirror the People Data Dictionary tone.}*

**✅ {Topic}** — {Short explanation.}

**✅ {Topic}** — {Short explanation.}

## Future scope

*{**⏳** bullets — only if there is a credible roadmap or known gap narrative. **Delete this entire section** if there is nothing to promise.}*

**⏳ {Possible extension}** — {When upstream or product makes it available / how it differs from current scope.}

## Out of scope

*{**❌** bullets — what is **not** modeled here; point readers to **real** sibling schemas (`dags/` or DataHub). Do not invent `dw_*` names — verify in the repo.}*

**❌ {Adjacent domain}** — {Why it is not here and where to go instead, e.g. **`{related_schema}`**.}

**❌ {Adjacent domain}** — {Same pattern.}

---

## Tables

Explore schemas and column-level detail in **DataHub** (lineage and definitions). Add **Explore in GitHub** pointing to the matching **`queries/{layer}/{table}.sql`** file (default branch **`master`**) so engineers can open the query next to the DataHub schema.

| Table | Explore in DataHub | Explore in GitHub |
|-------|-------------------|-------------------|
| `{table_a}` | [Open schema](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.{metastore_schema}.{table_a},PROD)/Schema?is_lineage_mode=false&schemaFilter=) | [View SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/{domain}/{dag_name}/queries/dw/{table_a}.sql) |
| `{table_b}` | [Open schema](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.{metastore_schema}.{table_b},PROD)/Schema?is_lineage_mode=false&schemaFilter=) | [View SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/{domain}/{dag_name}/queries/dw/{table_b}.sql) |

**URL pattern (GitHub):** `https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/{domain}/{dag_name}/queries/dw/{table_name}.sql` — replace `{layer}` if the DAG outputs tables under another layer folder (e.g. `queries/metric/`).

---

## Data model

**Grain**

- **`{table_a}`:** {one row per … — business wording; for historical tables describe periods and “what changed” without SCD/slowly-changing jargon}
- **`{table_b}`:** {one row per … — same rule}

{Short join explanation in plain language.}

![{Alt text describing the model}](assets/{image}.png)

### Full data model on GitHub

*{Optional companion file — use when the team wants **relationship diagrams** and join cheatsheets on **GitHub** while the Confluence page stays business-oriented. **Do not** duplicate full column inventories here — **DataHub** is authoritative for columns and types. Create **`docs/data_model.md`** (or `{dag}_data_model.md`) with grain, relationships, and joins; in this main doc add: (1) a **Contents** link to `#full-data-model-on-github`, (2) an **absolute** link to the file on the default branch, e.g. `https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/{domain}/{dag_name}/docs/data_model.md`, and (3) a **relative** link `[data_model.md](data_model.md)` for browsing inside the repo. Use **plain-language** link text in this main file (e.g. relationship overview for technical readers) — **no** diagram-tool or markup names. **Do not** paste large diagram blocks into the Confluence-target body if Confluence is the primary reader — link out instead. If you skip the companion file, remove this subsection and the Contents entry.}*

---

## Executive summary

{Two to four sentences: value for the business and what questions the schema answers. Avoid internal system names consumers do not use; prefer the product name for HR/CRM sources (e.g. **PIN** for QuintoAndar People master data — do not lead with vendor names like Oracle HCM in narrative text).}

### Key concepts

- {Filters, joins, metrics — business language}

### Refresh and availability

{If the DAG is dataset-scheduled without cron, state the **layer SLA** when the team has one — e.g. People **DW** availability by **8:00** once per day. Otherwise: daily / intraday as applicable.}

### Granularity

- `{metastore_schema}.{table_a}`: {one row per …}
- `{metastore_schema}.{table_b}`: {one row per …}

### Where to find the data

**Schema:** `{metastore_schema}` · **Airflow pipeline:** `bietlejuice.{dag_name}`

---

## Business logic

### Who is included

{Population in **business** terms — e.g. active employees and contractors, exclusions such as pending hires or test accounts. Do **not** paste raw technical filters (table names, assignment type codes) unless translated for the reader.}

### {Subsection per table or topic}

{Narrative; optional small tables for states or categories.}

**Reporting tip:** {One or two sentences.}

### {Derived metrics} (calculation rules)

*{Optional subsection — include when SQL computes non-obvious metrics (e.g. tenure, ratios). Plain-language rules: reference date, inputs, transfers or “stint” behavior; cite repo paths such as `dags/{domain}/{dag_name}/queries/{layer}/{table}.sql` and `metadata/{layer}/{table}.yml`. Add a **Contents** link and cross-links from the data dictionary **Notes** column. Remove this section if not applicable.}*

### Terms and column-level rules

Point readers to **DataHub metadata** for official definitions of metrics, flags, and categories. **Do not** duplicate long glossaries in this page if the same text belongs in `metadata/{layer}/{table}.yml` — the doc should **reference** DataHub as the source of truth for formulas and evolution.

---

## Data dictionary

Summary columns only. **Authoritative** descriptions: **DataHub** (links in [Tables](#tables)).

## `{metastore_schema}.{table_a}`

| Column | Business definition | Notes |
|--------|---------------------|-------|

## `{metastore_schema}.{table_b}`

| Column | Business definition | Notes |
|--------|---------------------|-------|

---

## How to use

Lead with **KPI-style business questions** (short intro + bullet list): e.g. headcount by cost center, turnover or exits by org slice, composition by job family — match the domain. If the DAG outputs **only dimensions**, add one sentence that **counts and rates** are **not** stored here; they come from **fact** tables (e.g. `dw_people.fact_employees`) **joined** to this schema. Then one **subsection per question**: plain-language **Question**, optional **pattern** or cross-schema note, and **example SQL** — include **`GROUP BY` / `COUNT(DISTINCT)`** examples when they illustrate KPIs. Prefer joins consumers actually use. When the answer lives in another schema (e.g. job on the monthly fact from `dw_compensation.dim_job`), say so explicitly. **Example SQL** must follow **`.cursor/rules/sql_conventions.mdc`** and column naming in **`naming_conventions.mdc`** (UPPERCASE keywords, descriptive `AS` table aliases, explicit columns, formatted joins; no `SELECT *`).

### {Business question 1 — e.g. headcount by cost center (aggregated)}

**Question:** {Plain-language question.}

```sql
-- Example SQL: match sql_conventions.mdc (UPPERCASE keywords, descriptive aliases, explicit columns).
SELECT
    {columns}
FROM
    {schema}.{table} AS {descriptive_alias}
WHERE
    {predicates}
```

### {Business question 2}

**Question:** {…}

```sql
{…}
```

---

## Sensitivity and access

{LGPD / internal policy / who may use the data.}

{Optional closing line: engineering detail lives in repo metadata and DAG declarations — not required for typical business readers.}
