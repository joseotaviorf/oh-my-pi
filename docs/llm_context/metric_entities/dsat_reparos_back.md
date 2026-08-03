# DSat Reparos Back (BPO Performance)

## Ownership

**Data Owner:**

- [joao.mariani@quintoandar.com.br](mailto:joao.mariani@quintoandar.com.br)

**Data Steward:**

- [victor.prado@quintoandar.com.br](mailto:victor.prado@quintoandar.com.br)
- [alef.vieira@quintoandar.com.br](mailto:alef.vieira@quintoandar.com.br)
- [diego.carvalho@quintoandar.com.br](mailto:diego.carvalho@quintoandar.com.br)
- [romario.nascimento@quintoandar.com.br](mailto:romario.nascimento@quintoandar.com.br)

## Overview

**DSat Reparos Back** is the family of metrics that measures customer support quality and dissatisfaction for the **Repairs Back** operation, integrating legacy and current data from the **Salesforce** and **Zendesk** platforms.

Consolidated data lives in `dw_bpo_performance.satisfaction_salesforce` and `dw_bpo_performance.cases_perspective`. Because the same ticket can appear across different data-load captures or system logs, this dataset applies **primary-key deduplication** (`sk_answer_csat` / `case_number`) and **de-duplication of consecutive surveys for the same case/client type** (`rn_case`) before the rate is computed — a naive `COUNT` over the raw union of both sources double-counts reloaded snapshots and repeated CSAT responses.

The primary metric produced by this pipeline is **DSat Reparos Back** (Repairs Back Dissatisfaction Rate).

## Related Business Entities

- Ticket
- Satisfaction
- Department

## Catalog

| Metric | Type |
| :---- | :---- |
| DSat Reparos Back | OKR |

## MBR

**Name** Post Contract
**Category** CS Quality

## Glossary and Synonyms

- **DSat**, **DSat Reparos**, **DSat Reparos Back**, **DSat Reparos Ongoing**, **Taxa de Insatisfação Reparos Back** → % of CSAT responses rated dissatisfied (1 or 2) within the Repairs Back universe.
- **CSAT Score**, **first_csat_score** → Score given by the customer in the satisfaction survey (1-to-5 scale).
- **sk_answer_csat** → Unique key of the CSAT survey event. On Zendesk, it is derived from `case_number` itself.

## Scope

**Included**:

- Satisfaction surveys with a recorded rating (`first_csat_score IS NOT NULL`).
- Responses from the BPO Performance tables belonging to the **Repairs Back** departments on the Salesforce and Zendesk platforms:
  - **Salesforce (`record_type_name`)**: `'Solicitação de Reparos'`, `'Reembolso de Reparos'`, `'Reparos - Contestação de responsibillidade ou criticidade'`.
  - **Zendesk (`last_department`)**: `'ReparAção Emergencial [BACK]'`, `'Reparos PP Multi [BACK]'`, `'Reparos [BACK]'`, `'Reembolso de Reparos [Back]'`, `'Autosserviço Reparos [BACK]'`, `'Triagem [Porto]'`, `'Atendimento [Porto]'`, `'Triagem Reparos [Back]'`, `'ReparAção (Piloto Urgente)'`, `'ReparAção Comum [BACK]'`, `'FullService [BACK]'`.

**Excluded**:

- Cases with no ticket identifier (`case_number IS NULL`).
- Surveys with no recorded satisfaction score (`first_csat_score IS NULL`).
- Duplicate load records (`rn > 1`) or secondary re-evaluations of the same case/client type (`rn_case > 1`).
- Any other department that does not belong to the Repairs Back scope listed above.

### Temporal Reference Axis

| Metric | Temporal Axis | Rationale |
| :---- | :---- | :---- |
| **DSat Reparos Back** | `CAST(first_csat_ts_response AS DATE)` | Exact date and time the customer submitted the first CSAT response. |

> **Warning:** Never use the `ts_load` column for time-trend analysis of this metric. `ts_load` represents only the data-pipeline load timestamp (the load date into the Data Warehouse), not the business-event moment.

## Calculation

DSat Reparos Back measures the share of evaluated surveys rated **1 or 2** out of the total answered surveys, within the Repairs Back scope. It must always be computed over the deduplicated view (`rn = 1` and `rn_case = 1`) — computing it directly over the raw union of `satisfaction_salesforce` and `cases_perspective` double-counts reloaded snapshots and repeated case surveys.

The correct calculation is:

```
DSat Reparos Back =
    COUNT(DISTINCT sk_answer_csat WHERE first_csat_score IN (1, 2))
    / COUNT(DISTINCT sk_answer_csat WHERE first_csat_score IS NOT NULL)
```

where:

- **Numerator**: number of distinct survey responses (`sk_answer_csat`) with a dissatisfaction rating (`first_csat_score IN (1, 2)`).
- **Denominator**: total number of distinct survey responses with a valid satisfaction score (`first_csat_score IS NOT NULL`).

### Canonical Filter

Apply on the deduplicated union of `dw_bpo_performance.satisfaction_salesforce` (Salesforce) and `dw_bpo_performance.cases_perspective` (Zendesk) — see [Nuances](#nuances) for the exact dedup logic:

```sql
-- After the UNION ALL and the rn / rn_case window functions:
rn = 1
AND rn_case = 1

-- Salesforce branch:
record_type_name IN (
    'Solicitação de Reparos', 'Reembolso de Reparos',
    'Reparos - Contestação de responsibillidade ou criticidade'
)
AND case_number IS NOT NULL

-- Zendesk branch:
first_csat_score IS NOT NULL
AND last_department IN (
    'ReparAção Emergencial [BACK]', 'Reparos PP Multi [BACK]', 'Reparos [BACK]',
    'Reembolso de Reparos [Back]', 'Autosserviço Reparos [BACK]', 'Triagem [Porto]',
    'Atendimento [Porto]', 'Triagem Reparos [Back]', 'ReparAção (Piloto Urgente)',
    'ReparAção Comum [BACK]', 'FullService [BACK]'
)
```

**Warning**: Omitting the `record_type_name` (Salesforce) or `last_department` (Zendesk) filters pollutes the metric with Front Office contacts or other verticals that are out of the Repairs Back scope.

### Nuances

The `respostas` view unions the two sources and must apply both dedup window functions before any aggregation. Never hardcode a pre-aggregated rate — always recompute numerator and denominator from this deduplicated view.

| Column | Description |
| :----- | :---------- |
| `rn` | Load-window dedup: `ROW_NUMBER() OVER (PARTITION BY sk_answer_csat ORDER BY ts_load DESC)` on Zendesk (`PARTITION BY case_number`); the Salesforce branch is hardcoded to `1` because it carries no reload duplication. Mandatory filter: `rn = 1` (keeps only the most recently loaded snapshot). |
| `rn_case` | First-response dedup: `ROW_NUMBER() OVER (PARTITION BY case_number, client_type ORDER BY first_csat_ts_response ASC)` on Zendesk; the Salesforce branch is hardcoded to `1`. Mandatory filter: `rn_case = 1` (keeps only the first CSAT response the customer gave for that case). |
| `sk_answer_csat` | Treat as a string when unioning both sources — on Zendesk it is derived via `CAST(case_number AS VARCHAR)`. |
| `Platform` | Literal `'SalesForce'` / `'Zendesk'` tag added to every row of the union — always keep it to identify which source a row came from. |

**Join key**: none — the two sources are combined with `UNION ALL`, not a join, and each branch is deduplicated independently before the union.

**Fallback**: not applicable — there is no external parameter table for this metric.

## Dos and Don'ts

**Do:**

- Always apply the dedup window filter (`rn = 1` and `rn_case = 1`) when querying the raw sources.
- Use `first_csat_ts_response` for time-based filters and grouping (daily, weekly, monthly).
- Treat `sk_answer_csat` as a string/varchar when unioning the sources (Zendesk casts `case_number` via `CAST`).
- Identify the source platform via the `Platform` column (`SalesForce` or `Zendesk`) when unifying both sides.

**Don't:**

- Don't calculate the rate using `ts_load` as the time reference.
- Don't forget to filter `case_number IS NOT NULL` and `first_csat_score IS NOT NULL`.
- Don't omit the `record_type_name` (Salesforce) or `last_department` (Zendesk) filters — doing so pollutes the metric with Front Office contacts or other verticals outside the Repairs Back scope.

## Golden Queries

Both queries apply the same deduplicated `respostas` view; what differs is the aggregation layer. Trino dialect.

### Query 1 — Deduplicated Consolidated View (`respostas`)

The reusable base view: unions Salesforce and Zendesk Repairs Back responses and applies the dedup window filters. Use this pattern as the `WITH respostas AS (...)` CTE for any Repairs Back CSAT query.

```sql
WITH respostas AS (
    SELECT
        sk_answer_csat,
        case_number,
        first_csat_ts_response,
        first_csat_score,
        record_type_name AS last_department,
        client_type_csat AS client_type,
        criticidade,
        ts_load,
        'SalesForce' AS platform,
        1 AS rn,
        1 AS rn_case
    FROM dw_bpo_performance.satisfaction_salesforce
    WHERE record_type_name IN (
            'Solicitação de Reparos', 'Reembolso de Reparos',
            'Reparos - Contestação de responsibillidade ou criticidade'
        )
        AND case_number IS NOT NULL

    UNION ALL

    SELECT
        CAST(case_number AS VARCHAR) AS sk_answer_csat,
        case_number,
        first_csat_ts_response,
        first_csat_score,
        last_department,
        client_type,
        criticidade_ro AS criticidade,
        ts_load,
        'Zendesk' AS platform,
        ROW_NUMBER() OVER (PARTITION BY case_number ORDER BY ts_load DESC) AS rn,
        ROW_NUMBER() OVER (PARTITION BY case_number, client_type ORDER BY first_csat_ts_response ASC) AS rn_case
    FROM dw_bpo_performance.cases_perspective
    WHERE first_csat_score IS NOT NULL
        AND last_department IN (
            'ReparAção Emergencial [BACK]', 'Reparos PP Multi [BACK]', 'Reparos [BACK]',
            'Reembolso de Reparos [Back]', 'Autosserviço Reparos [BACK]', 'Triagem [Porto]',
            'Atendimento [Porto]', 'Triagem Reparos [Back]', 'ReparAção (Piloto Urgente)',
            'ReparAção Comum [BACK]', 'FullService [BACK]'
        )
)
SELECT *
FROM respostas
WHERE rn = 1
    AND rn_case = 1
```

### Query 2 — DSat Reparos Back (Monthly)

The official consolidated metric: applies the `respostas` component from Query 1, then computes the monthly dissatisfaction rate.

```sql
WITH respostas AS (
    SELECT
        sk_answer_csat,
        case_number,
        first_csat_ts_response,
        first_csat_score,
        record_type_name AS last_department,
        client_type_csat AS client_type,
        criticidade,
        ts_load,
        'SalesForce' AS platform,
        1 AS rn,
        1 AS rn_case
    FROM dw_bpo_performance.satisfaction_salesforce
    WHERE record_type_name IN (
            'Solicitação de Reparos', 'Reembolso de Reparos',
            'Reparos - Contestação de responsibillidade ou criticidade'
        )
        AND case_number IS NOT NULL

    UNION ALL

    SELECT
        CAST(case_number AS VARCHAR) AS sk_answer_csat,
        case_number,
        first_csat_ts_response,
        first_csat_score,
        last_department,
        client_type,
        CAST(NULL AS VARCHAR) AS criticidade,
        ts_load,
        'Zendesk' AS platform,
        ROW_NUMBER() OVER (PARTITION BY case_number ORDER BY ts_load DESC) AS rn,
        ROW_NUMBER() OVER (PARTITION BY case_number, client_type ORDER BY first_csat_ts_response ASC) AS rn_case
    FROM dw_bpo_performance.cases_perspective
    WHERE first_csat_score IS NOT NULL
        AND last_department IN (
            'ReparAção Emergencial [BACK]', 'Reparos PP Multi [BACK]', 'Reparos [BACK]',
            'Reembolso de Reparos [Back]', 'Autosserviço Reparos [BACK]', 'Triagem [Porto]',
            'Atendimento [Porto]', 'Triagem Reparos [Back]', 'ReparAção (Piloto Urgente)',
            'ReparAção Comum [BACK]', 'FullService [BACK]'
        )
)
SELECT
    DATE_TRUNC('month', CAST(first_csat_ts_response AS DATE)) AS ref_month,
    COUNT(DISTINCT CASE WHEN first_csat_score IN (1, 2) THEN sk_answer_csat END) AS total_dsat_answers,
    COUNT(DISTINCT CASE WHEN first_csat_score IS NOT NULL THEN sk_answer_csat END) AS total_evaluated_answers,
    CAST(COUNT(DISTINCT CASE WHEN first_csat_score IN (1, 2) THEN sk_answer_csat END) AS DOUBLE)
        / NULLIF(CAST(COUNT(DISTINCT CASE WHEN first_csat_score IS NOT NULL THEN sk_answer_csat END) AS DOUBLE), 0) AS dsat_reparos_back_rate
FROM respostas
WHERE rn = 1
    AND rn_case = 1
    AND first_csat_ts_response IS NOT NULL
GROUP BY 1
ORDER BY 1 DESC
```
