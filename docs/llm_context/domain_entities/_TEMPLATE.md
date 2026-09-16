# {Entity Name}

<!--
WRITING GUIDE — delete this block before committing.

Audience: TARS (text-to-SQL AI agent) and human analysts.
Goal: give TARS enough routing context to pick the right table and write correct SQL
      for any reasonable question about this domain entity.

Rules:
  • Plain language. No DataHub URNs in prose — catalog links live in `## DataHub catalog`.
  • CI publishes to DataHub from this MD via `generate_and_push_datahub_entities.py`.
  • Every table section must state grain, key dedup flags, and common join keys.
  • **RENT / SALE scope:** every `schema.table` entry must state explicitly whether the table is **just rent**, **just sale**, **both** (with `business_context` or equivalent filter), or **neither** (house-level / cross-product). **Do not use “RENT only” / “SALE only” for table scope** — in this repo “only” often means non-hybrid; hybrids can still exist. TARS must not label a table as rent or sale unless that scope is written in this doc for that table.
  • Every synonym that has a Portuguese name should be listed in the Glossary and Synonyms table.
  • Golden Queries: the single most important / most-asked metric for this entity.
  • Cross-link to sibling .md files instead of duplicating their content.
  • File name: lowercase_snake_case.md (matches the entity slug in the YAML).
-->

## Ownership

<!--
Data Steward: maintains this document day-to-day and is the first point of contact for
questions — at least one email is REQUIRED. Domain docs have no Data Owner role: the
steward is the single point of contact. (Metric docs still carry both, because there
the Data Owner is accountable for the business definition of the number.) Not folded
into the DataHub Data Product description (see EXCLUDE_HEADING_PATTERNS in
generate_and_push_datahub_entities.py) — it is routing metadata, not narrative content.
-->

**Data Steward:**
- {data_steward_email@quintoandar.com.br}

---

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

---

## Glossary and Synonyms

<!--
List every Portuguese / internal term that analysts or stakeholders might use
when asking questions, and its meaning. TARS uses this table to map user language
to canonical column values and table names.
-->

| Term | Meaning | Notes |
|------|---------|-------|
| **{PT term}** | {EN equivalent} | {Optional: canonical column value or filter this maps to.} |
| **{PT term 2}** | {EN equivalent 2} | |

---

## Tables

<!--
Use-case routing table. Column "You need…" should be written the way a business
user would phrase the need. "Schema / table" is the canonical answer (concrete
`schema.table`). TARS uses this to decide which table to query before writing SQL.
No DataHub links here — those are auto-generated.
-->

| You need… | Schema / table |
|-----------|----------------|
| {High-level use case, e.g. "Daily overdue timeline per invoice"} | `{dw_schema}.{fact_table}` — **{just rent / just sale / both + filter}** |
| {Another use case} | `{dw_schema}.{dim_table}` — **{just rent / just sale / both + filter}** |
| {Cross-entity use case referencing another schema} | `{other_schema}.{table}` (see [`{sibling}.md`]({sibling}.md)) — **{scope if not obvious from sibling}** |

---

## Key Metrics

<!--
Split into two subsections when metric entities exist for this domain:

1. **Official metrics (metric entities)** — table or bullets linking to
   ../metric_entities/*.md for MBR/OKR/source-of-truth numbers. TARS must route here
   when the user asks for an official, weighted, or canonical metric by name.

2. **Component / exploratory metrics** — ad-hoc measures computable from this entity's
   tables (volume, rates, distributions). State the WHAT and canonical column; do NOT
   duplicate official formulas from metric entities.

If no metric entity exists yet, a single bullet list is fine.
-->

Use [Official metrics (metric entities)](#official-metrics-metric-entities) below when the question asks for an **official**, **MBR**, or **OKR** number.

### Official metrics (metric entities)

| When you need… | Metric entity |
|----------------|---------------|
| {Official metric name or family} | [`{metric_entity_slug}.md`](../metric_entities/{metric_entity_slug}.md) |

### Component / exploratory metrics

- **{Metric name}:** {One-line description. Reference the canonical column, e.g. `fact_table.column_name`.}
- **{Metric name 2}:** {One-line description.}

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
- Don't tell the user a table is **For Rent** or **For Sale** unless this document **explicitly** states that scope on the table row or section — do not infer from schema name (`dw_rent`, `dw_sale`) or column names alone.
- {Another anti-pattern.}

---

## Golden Queries

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
