# {Entity Name}

> **Authoring checklist (delete before publishing)**
>
> 1. Set **Type** to *Process Guide* in DataHub.
> 2. Add tag **`tars-entity`** and assign the correct **Domain** (Fintech, Growth, etc.).
> 3. Set yourself and the domain data owner as **Owners**.
> 4. Fill the **Structured Properties** sidebar (see [AUTHORING_GUIDE.md](./AUTHORING_GUIDE.md)):
>    - `domain_urn` — e.g. `urn:li:domain:fintech`
>    - `data_product_id` — kebab-case slug, e.g. `my-entity`
>    - `primary_datasets` — comma-separated `schema.table` list
>    - `golden_query_stable_urn` — generate once: `urn:li:query:{uuid4}` (never change after first publish)
> 5. Replace every `{placeholder}` below with real content.
> 6. Save as **Draft**, ask your domain owner to review, then toggle **Published**.

---

## Overview

{2–4 sentences: what this business entity is, why analysts care, and where it lives in the data architecture.}

{Optional lifecycle bullets — each stage should reference a key column or flag:}
- **Stage 1** — description (`schema.table.column`)
- **Stage 2** — description (`schema.table.column`)

**Related entities:** For {adjacent concept}, see the {Entity Name} document in the same domain or ask your data steward.

Primary DW schemas: **`{dw_schema_a}`**, **`{dw_schema_b}`**.

---

## Glossary and Synonyms

| Term | Meaning | Technical mapping |
|------|---------|-------------------|
| **{PT-BR term}** | {English meaning} | `{schema.table.column}` or filter value |
| **{PT-BR term 2}** | {English meaning 2} | `{schema.table.column}` |

---

## Tables

| You need… | Use this table |
|-----------|----------------|
| {Most common analytical need} | `{dw_schema}.{fact_table}` |
| {Dimension / lookup need} | `{dw_schema}.{dim_table}` |
| {Cross-domain need} | `{other_schema}.{table}` |

**Critical rules:**

- {Mandatory filter, e.g. always apply `is_most_recent_record_month = true` for month-end cuts.}
- {Grain caveat, e.g. one row per invoice × day — do not double-count without dedup.}

---

## Key Metrics

- **{Metric name}** — `{column}` or `{formula}` on `{schema.table}`
- **{Metric name 2}** — `{column}` on `{schema.table}`

---

## Relationships with Other Entities

- **{Entity A} ↔ {Entity B}:** join on `{join_key}` with `{other_schema}.{other_table}`.
- **{This entity} → {Other entity}:** `{fk_column}` references `{other_schema}.{dim_table}.{pk_column}`.

---

## Dos and Don'ts

**Do:**

- {Specific positive rule with table/column reference.}
- {Methodology rule, e.g. always specify T1 vs T2 when using segmentation tables.}

**Don't:**

- {Common mistake, e.g. do not confuse `{schema_a}` with `{schema_b}` — different grains.}
- {Anti-pattern with filter or cast issue.}

---

## Golden Queries

### Query 1 — {Short descriptive name}

{One sentence describing what this query computes and when to use it.}

```sql
SELECT
    {date_or_group_column},
    {dimension_column},
    {metric_expression} AS {metric_alias}
FROM {dw_schema}.{primary_table}
WHERE {dedup_flag} = true
  AND {date_column} BETWEEN date_add('month', -13, current_date)
                        AND current_date
GROUP BY 1, 2
ORDER BY 1 DESC, 2;
```

> **Note:** SQL uses Trino syntax (`date_add`, `last_day_of_month`). Adjust date filters to your analysis window.

### Query 2 — {Optional second query}

{Description.}

```sql
-- Optional second golden query
SELECT ...
FROM {dw_schema}.{table}
WHERE ...
```

---

## DataHub catalog

_This section is auto-filled by the sync pipeline after your document is published and converted to a Data Product._

- **Data Product:** _(pending sync)_
- **Source document URN:** _(your document URN)_
