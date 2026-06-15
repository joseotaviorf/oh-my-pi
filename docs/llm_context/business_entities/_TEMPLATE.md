# {Entity Name}

<!--
WRITING GUIDE — delete this block before committing.

Audience: TARS (text-to-SQL AI agent) and human analysts.
Goal: give TARS enough routing context to pick the right table and write correct SQL
      for any reasonable question about this business entity.

Rules:
  • Plain language. No DataHub URNs in prose — catalog links live in `## DataHub catalog`.
  • CI publishes to DataHub from this MD via `generate_and_push_datahub_entities.py`.
  • Every table section must state grain, key dedup flags, and common join keys.
  • Every synonym that has a Portuguese name should be listed in the Synonyms table.
  • Golden query: the single most important / most-asked metric for this entity.
  • Cross-link to sibling .md files instead of duplicating their content.
  • File name: lowercase_snake_case.md (matches the entity slug in the YAML).
-->

## Overview

<!--
3–6 bullets covering: what the entity is, its lifecycle, where it lives in the
data architecture, upstream source systems, and pointers to related entities.
-->

- **Objective:** {What business problem this entity solves or what process it tracks.}
- **Asset status / lifecycle:** {Where in the lifecycle data enters and exits.}
- **Typical actions / events:** {The key things that happen to this entity.}
- **Common metrics:** {2–4 KPIs most often asked about.}
- **Source systems:** {Upstream operational systems feeding this entity (e.g. Retsuko, Zendesk, Trato Feito).}
- **Related entities:** For {adjacent concept}, see [`{sibling}.md`]({sibling}.md).

DW schemas described here: **`{dw_schema_a}`** and **`{dw_schema_b}`** (add or remove as needed).

---

## Synonyms

<!--
List every Portuguese / internal term that analysts or stakeholders might use
when asking questions. TARS uses this table to map user language to canonical
column values and table names.
-->

| Term | Meaning | Notes |
|------|---------|-------|
| **{PT term}** | {EN equivalent} | {Optional: canonical column value or filter this maps to.} |
| **{PT term 2}** | {EN equivalent 2} | |

---

## Where to query what

<!--
Use-case routing table. Column "You need…" should be written the way a business
user would phrase the need. "Schema / table" is the canonical answer.
TARS uses this to decide which table to query before writing SQL.
No DataHub links here — those are auto-generated.
-->

| You need… | Schema / table |
|-----------|----------------|
| {High-level use case, e.g. "Daily overdue timeline per invoice"} | `{dw_schema}.{fact_table}` |
| {Another use case} | `{dw_schema}.{dim_table}` |
| {Cross-entity use case referencing another schema} | `{other_schema}.{table}` (see [`{sibling}.md`]({sibling}.md)) |

---

## `{dw_schema_name}`

<!--
One H2 section per DW schema. State purpose and pipeline cadence.
-->

**Purpose:** {One sentence on what this schema covers.}

**Pipeline:** `query_delta`, layer `dw`, schema **`{dw_schema_name}`**, {full / incremental} load. Triggered {daily / hourly} by {trigger name}.

### `{fact_table_name}`

<!--
Grain is the most important thing TARS needs to know. State it in bold.
Then list key field groups in a two-column table.
Call out critical filter flags as blockquotes.
-->

Grain: **one row per {grain description, e.g. invoice × contract × dt_reference (daily)}**.
`{sk_primary_key}` is hashed from {hash source fields}.

> **Filter:** always apply `{dedup_flag} = true` for {use-case, e.g. "month-end cuts to get one row per invoice per month"}.

| Topic | Fields |
|-------|--------|
| Keys / links | `{sk_primary}`, `{id_foreign}`, `{sk_other_dim}` |
| {Topic, e.g. Status} | `{field_a}`, `{field_b}` (**`{enum_field}`**: {value1}, {value2}, {value3}) |
| {Topic, e.g. Amounts} | `{amount_field}`, `{net_amount_field}` |
| {Topic, e.g. Flags} | `{is_flag}`, `{has_flag}` |
| {Topic, e.g. Dates} | `{dt_field}`, `{ts_field}` |

### `{dim_table_name}`

Grain: **one row per {grain description}**.

| Topic | Fields |
|-------|--------|
| Keys | `{sk_key}` |
| Attributes | `{attr_a}`, `{attr_b}` |

---

## `{dw_schema_name_2}`

<!--
Add additional H2 sections for each DW schema. Remove this block if there is
only one schema.
-->

**Purpose:** {One sentence.}

**Pipeline:** `query_delta`, schema **`{dw_schema_name_2}`**, full load.

### `{table_name}`

Grain: **one row per {grain description}**.

| Topic | Fields |
|-------|--------|
| Keys | `{sk_key}`, `{id_key}` |
| Attributes | `{field}` |

---

## Relationships with other entities

<!--
State cardinality and join keys. Use "↔" for bidirectional joins.
Avoid duplicating content that lives in sibling .md files — link instead.
-->

- **{Entity A} ↔ {Entity B}:** join on `{join_key}` aligns with `{other_schema}.{other_table}`.
- **{This entity} → {Other entity}:** `{fk_column}` references `{other_schema}.{dim_table}.{pk_column}`.
- **{Metric overlap}:** For {metric name}, union with `{other_schema}.{other_table}`; see [`{sibling}.md`]({sibling}.md).

---

## Dos and don'ts

<!--
Operational pitfalls that TARS or analysts commonly hit. Be specific:
wrong schema names, missing filters, cast issues, methodology distinctions.
-->

**Do:**

- {Positive rule, e.g. "For month-end cuts on `fact_*_timeline`, confirm whether the metric needs `is_most_recent_record_month = true`".}
- {Specify methodology variant where applicable, e.g. "Always state T1 vs T2 vs T3 explicitly — column names encode the methodology."}

**Don't:**

- {Anti-pattern, e.g. "Confuse `{schema_a}` with `{schema_b}` — they are different DAGs with different grains."}
- {Another anti-pattern.}

---

## Golden query: {Query Name}

<!--
The single most important SQL template for this entity. Should demonstrate:
  • The canonical metric (most-asked KPI).
  • Correct grain, dedup flags, and date spine.
  • Typical join pattern if cross-schema.
Add an inline note on date functions and any filters the caller must adjust.
-->

{One sentence on what this query computes and why it is the canonical starting point.}

```sql
SELECT
    {date_or_group_by_column},
    {dimension_column},
    {metric_expression}           AS {metric_alias}
FROM {dw_schema}.{primary_table}
-- optional join
LEFT JOIN {dw_schema}.{dim_table}
    ON {primary_table}.{fk} = {dim_table}.{pk}
WHERE {dedup_flag} = true
  AND {date_column} BETWEEN {start_expr} AND {end_expr}
GROUP BY 1, 2
ORDER BY 1 DESC, 2;
```

> **Note:** `{date_add}` / `{last_day_of_month}` follow Trino/Presto syntax.
> Adjust date functions and `{enum_values}` to match your environment.
