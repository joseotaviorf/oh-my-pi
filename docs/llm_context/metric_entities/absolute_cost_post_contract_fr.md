# Absolute Cost Post-Contract (For Rent)

## Ownership

**Data Owner:**
- felipe.abreu@quintoandar.com.br

**Data Steward:**
- jacqueline.gomez@quintoandar.com.br
- livia.borges@quintoandar.com.br

## Overview

**Absolute Cost Post-Contract (For Rent)** is the net Operations cost for the **Post-Contract** area within the For Rent business vertical, limited to the **Onboarding**, **Ongoing**, and **Offboarding** `P&L Line 2` components. It is a subset of [Absolute Cost Ops Total (For Rent)](./absolute_cost_ops_total_fr.md): the same `Operations` P&L line, restricted to rows owned by `BeCe L2 = 'Felipe Abreu'` and to the three unitized cost phases.

The metric returns the **net liquid value** — costs and revenues offset each other according to the source sign convention (costs predominantly negative, credits/revenue offsets positive).

This metric differs from the total For Rent Operations cost (which sums all `BeCe L2` owners and all `P&L Line 2` values, including overhead and tax credit) and from unit-cost metrics (which divide a single `P&L Line 2` component by a volume denominator).

Related metrics: [Absolute Cost Ops Total (For Rent)](./absolute_cost_ops_total_fr.md), [Onboarding Unit Cost (For Rent)](./onboarding_uc_fr.md), [Ongoing Unit Cost (For Rent)](./ongoing_uc_fr.md), [Offboarding Unit Cost (For Rent)](./offboarding_uc_fr.md).

**Exists exclusively for For Rent.**

## Related Business Entities

- Finance Revenue and Cost

## Catalog

| Metric | Type |
| :---- | :---- |
| Absolute Cost Post-Contract (For Rent) | OKR |

## MBR

**Name** Post Contract
**Category** Cost of Service

## Glossary and Synonyms

- **custo Pós-Contrato**, **Post-Contract cost**, **Absolute Cost Post-Contract**, **cost of service Post-Contract For Rent** → this metric

## Scope

**Included**: `Operations` cost lines (`P&L Line 1 = 'Operations'`) under `BeCe Business = 'For Rent'` where `BeCe L2 = 'Felipe Abreu'` and `P&L Line 2` IN (`Onboarding`, `Ongoing`, `Offboarding`), with a populated `Reporting Group` (`reporting_group <> '-'`), for `version = 'Actuals'`.

**Excluded**:

- `Operations Overhead`, `Operations Tax Credit`, and any other `P&L Line 2` outside the three Post-Contract phases
- Rows with `reporting_group = '-'` (placeholder / unclassified)
- Operations costs from other `BeCe L2` owners within For Rent
- Operations costs from other business verticals (`For Sale`, `Corporate`, etc.)
- Non-Operations P&L lines (`Sales`, `Marketing`, `G&A`, revenues, derived results)
- Unit-cost views (those use a single `P&L Line 2` and a volume denominator)

## Calculation

Filtering only on `bece_business = 'For Rent'` and `pl_line_1 = 'Operations'` produces the **total** For Rent Operations cost, not the Post-Contract figure. Omitting the `bece_l2` filter overstates the Post-Contract metric by including costs owned by other organizational areas. Omitting the `pl_line_2` restriction includes overhead and tax credit lines that are not part of Post-Contract absolute cost.

The correct calculation is:

```
Absolute Cost Post-Contract (For Rent) = SUM(<YYYYMM amount>)
```

where each amount comes from rows matching the canonical filter below. Amounts are summed **as recorded** — do not apply `ABS()`. Costs are predominantly **negative** and revenue offsets / tax credits may be **positive**; the result is the net liquid Operations figure for Post-Contract.

### Canonical Filter

Apply on `datalake_luigijr_ops_finance_clean.finance_revenue_cost_2025` or `finance_revenue_cost_2026` (see [table selection](../business_entities/finance_revenue_cost.md#table-selection-by-year)):

```sql
bece_business = 'For Rent'
AND bece_l2 = 'Felipe Abreu'
AND pl_line_1 = 'Operations'
AND pl_line_2 IN ('Onboarding', 'Ongoing', 'Offboarding')
AND reporting_group <> '-'
AND version = 'Actuals'
```

Column names in the uploaded table are **lowercased**, **spaces replaced by underscores**, and **`&` removed** (e.g. `BeCe L2` → `bece_l2`, `P&L Line 1` → `pl_line_1`).

**Warning**: Omitting `bece_l2 = 'Felipe Abreu'` or the `pl_line_2` restriction returns a broader Operations total, not the Post-Contract subset. Omitting `reporting_group <> '-'` includes placeholder rows.

### Nuances

**Period selection**: Months are not a categorical column. Select the target month by reading the corresponding `YYYYMM` column (e.g. `"202603"` for March 2026) from the table for that year. Period column names are unaffected by the lower/underscore transform. To build a time series, unpivot the relevant `YYYYMM` columns — see the golden query below.

**Organizational hierarchy drift**: `bece_l2` assignments can change between reporting cycles (reorganizations). Retrospective reconciliation against historical MBA reports may diverge if ownership was reclassified after the original close.

**Empty cells**: Treat empty period cells as missing, not as zero.

**Sign convention**: Sum raw amounts without `ABS()`. A negative result indicates net cost; a positive result indicates net revenue offset exceeding costs within the filtered scope.

**Type casting**: Period columns are stored as `varchar` after upload. Cast to numeric before aggregating: `TRY_CAST(REPLACE(f."<YYYYMM>", ',', '') AS DOUBLE)`.

| Parameter   | Description                                                                                                                      |
| :---- | :---- |
| `<YYYYMM>`  | Target month column name (e.g. `202603`). Query the table for the matching calendar year.                                        |

**Fallback**: If the requested `YYYYMM` column is empty for `version = 'Actuals'`, the metric is undefined for that period — do not fall back to a different `version` silently.

## Dos and Don'ts

**Do:**

- Always filter `bece_business = 'For Rent'`, `bece_l2 = 'Felipe Abreu'`, `pl_line_1 = 'Operations'`
- Restrict `pl_line_2` to `Onboarding`, `Ongoing`, `Offboarding`
- Exclude placeholder rows: `reporting_group <> '-'`
- Use `version = 'Actuals'` for the standard realized-cost metric
- Query `finance_revenue_cost_2025` or `finance_revenue_cost_2026` according to the target year
- Sum raw amounts — do **not** apply `ABS()`; the metric is net liquid, not absolute
- Use lowercased, underscore-separated column names as they appear post-upload

**Don't:**

- Omit the `bece_l2` filter — that produces the total For Rent cost, not Post-Contract
- Include `Operations Overhead` or `Operations Tax Credit` — they are outside Post-Contract absolute cost
- Include rows with `reporting_group = '-'`
- Omit the `version` filter — this mixes scenarios and produces wrong totals
- Assume a `month` or `period` dimension column exists — months are wide `YYYYMM` columns
- Treat empty cells as zero
- Apply `ABS()` — this metric is net liquid, not absolute cost
- Confuse this metric with unit-cost metrics (Onboarding / Ongoing / Offboarding UC)

## Targets and OKRs

The canonical filter uses `version = 'Actuals'` for realized costs. The same `YYYYMM` column can produce **different metric values** for other scenarios:

| Scenario | Typical `version` value                          | Use case                 |
| -------- | ------------------------------------------------ | ------------------------ |
| Actuals  | `Actuals`                                        | Realized / closed costs  |
| Budget   | `Budget <YYYY> - <MM>` (label varies by refresh) | Budget comparison        |
| Forecast | `Forecast 5+7` (label may vary)                  | Forward-looking forecast |
| OKR      | `OKR100 <YYYY> - <MM>` (label may vary)          | OKR target scenario      |

**Always pair the target `YYYYMM` column with the matching `version`.** For the standard Actuals metric, use `version = 'Actuals'`. Exact `version` labels may change between monthly refreshes — confirm available values before querying.

**Budget (Target)** — orçamento mensal do custo Pós-Contrato For Rent na tabela financeira.

- **Source table:** `datalake_luigijr_ops_finance_clean.finance_revenue_cost_2025` / `finance_revenue_cost_2026` (ver [table selection](../business_entities/finance_revenue_cost.md#table-selection-by-year))
- **Filter key / metric name:** coluna `version` = `Budget <YYYY> - <MM>` (label varia por refresh); aplicar o mesmo canonical filter de Calculation com `version` substituído
- **Period grain:** mensal — coluna `YYYYMM` wide-format
- **Aliases / search terms:** orçamento, budget, target, custo Pós-Contrato
- **Caveat:** labels exatos podem mudar entre refreshes; nunca agregar across `version` values

**OKR** — meta de período (OKR100) na mesma tabela.

- **Source table:** `datalake_luigijr_ops_finance_clean.finance_revenue_cost_2025` / `finance_revenue_cost_2026`
- **Filter key / metric name:** coluna `version` = `OKR100 <YYYY> - <MM>` (label varia por refresh); aplicar o mesmo canonical filter de Calculation com `version` substituído
- **Period grain:** mensal — coluna `YYYYMM`
- **Aliases / search terms:** meta, OKR, OKR100
- **Caveat:** confirmar labels disponíveis antes de consultar; parear `YYYYMM` + `version`

## Golden Queries

Single-month net Post-Contract cost (Actuals), written for March 2026.

```sql
SELECT
    -- Change the "202603" column to the target month (YYYYMM).
    SUM(TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)) AS absolute_cost_post_contract_fr
-- Change the _2026 suffix to the calendar year of the month above (_2025 or _2026).
FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026 f
WHERE f.bece_business = 'For Rent'
  AND f.bece_l2 = 'Felipe Abreu'
  AND f.pl_line_1 = 'Operations'
  AND f.pl_line_2 IN ('Onboarding', 'Ongoing', 'Offboarding')
  AND f.reporting_group <> '-'
  AND f.version = 'Actuals'
  AND TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE) IS NOT NULL;
```

Monthly time series for Actuals across 2025 and 2026. Extend the `VALUES` lists as new `YYYYMM` columns become available.

```sql
SELECT
    t.period_yyyymm,
    SUM(TRY_CAST(REPLACE(t.amount, ',', '') AS DOUBLE)) AS absolute_cost_post_contract_fr
FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2025 f
CROSS JOIN LATERAL (
    VALUES
        ('202501', f."202501"),
        ('202502', f."202502"),
        ('202503', f."202503"),
        ('202504', f."202504"),
        ('202505', f."202505"),
        ('202506', f."202506"),
        ('202507', f."202507"),
        ('202508', f."202508"),
        ('202509', f."202509"),
        ('202510', f."202510"),
        ('202511', f."202511"),
        ('202512', f."202512")
) AS t(period_yyyymm, amount)
WHERE f.bece_business = 'For Rent'
  AND f.bece_l2 = 'Felipe Abreu'
  AND f.pl_line_1 = 'Operations'
  AND f.pl_line_2 IN ('Onboarding', 'Ongoing', 'Offboarding')
  AND f.reporting_group <> '-'
  AND f.version = 'Actuals'
  AND TRY_CAST(REPLACE(t.amount, ',', '') AS DOUBLE) IS NOT NULL
GROUP BY 1

UNION ALL

SELECT
    t.period_yyyymm,
    SUM(TRY_CAST(REPLACE(t.amount, ',', '') AS DOUBLE)) AS absolute_cost_post_contract_fr
FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026 f
CROSS JOIN LATERAL (
    VALUES
        ('202601', f."202601"),
        ('202602', f."202602"),
        ('202603', f."202603")
) AS t(period_yyyymm, amount)
WHERE f.bece_business = 'For Rent'
  AND f.bece_l2 = 'Felipe Abreu'
  AND f.pl_line_1 = 'Operations'
  AND f.pl_line_2 IN ('Onboarding', 'Ongoing', 'Offboarding')
  AND f.reporting_group <> '-'
  AND f.version = 'Actuals'
  AND TRY_CAST(REPLACE(t.amount, ',', '') AS DOUBLE) IS NOT NULL
GROUP BY 1
ORDER BY 1;
```

Side-by-side comparison with total For Rent cost for the same period (Actuals), written for March 2026:

```sql
SELECT
    -- Change every "202603" column reference to the target month (YYYYMM).
    SUM(TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)) AS absolute_cost_ops_total_fr,
    SUM(TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)) FILTER (
        WHERE f.bece_l2 = 'Felipe Abreu'
          AND f.pl_line_2 IN ('Onboarding', 'Ongoing', 'Offboarding')
    ) AS absolute_cost_post_contract_fr
-- Change the _2026 suffix to the calendar year of the month above (_2025 or _2026).
FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026 f
WHERE f.bece_business = 'For Rent'
  AND f.pl_line_1 = 'Operations'
  AND f.reporting_group <> '-'
  AND f.version = 'Actuals'
  AND TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE) IS NOT NULL;
```

To compare budget or OKR scenarios for the same month, change `version` and keep all other filters — never aggregate across versions in one pass.
