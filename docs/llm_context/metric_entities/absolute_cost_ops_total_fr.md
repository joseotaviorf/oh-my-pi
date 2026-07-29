# Absolute Cost Ops Total (For Rent)

## Ownership

**Data Owner:**
- felipe.abreu@quintoandar.com.br

**Data Steward:**
- jacqueline.gomez@quintoandar.com.br
- livia.borges@quintoandar.com.br

## Overview

**Absolute Cost Ops Total (For Rent)** is the total net Operations cost allocated to the **For Rent** business vertical. It corresponds to the finance concept of *cost of service* for For Rent: the full `Operations` line of the P&L, summed across all benefit centers, products, brands, and organizational owners within For Rent.

The metric returns the **net liquid value** — costs and revenue offsets are summed as recorded, without `ABS()`.

This metric differs from a naive sum of all cost rows in the table (which would mix Sales, Marketing, G&A, and derived P&L results) and from [Absolute Cost Post-Contract (For Rent)](./absolute_cost_post_contract_fr.md), which is a subset filtered to `bece_l2 = 'Felipe Abreu'` and `pl_line_2` IN (`Onboarding`, `Ongoing`, `Offboarding`).

Related metrics: [Absolute Cost Post-Contract (For Rent)](./absolute_cost_post_contract_fr.md).

**Exists exclusively for For Rent.**

## Related Business Entities

- Finance Revenue and Cost

## MBR

- Post Contract

## Glossary and Synonyms

- **custo total For Rent**, **cost of service For Rent**, **Operations total cost For Rent**, **Absolute Cost Ops Total** → this metric

## Scope

**Included**: All `Operations` cost lines (`P&L Line 1 = 'Operations'`) under `BeCe Business = 'For Rent'` with a populated `Reporting Group` (`reporting_group <> '-'`), for `version = 'Actuals'`, regardless of `BeCe L2` / `BeCe L3` owner, product, brand, or `P&L Line 2` breakdown (Onboarding, Ongoing, Offboarding, Operations Overhead, Operations Tax Credit, etc.).

**Excluded**:

- Rows with `reporting_group = '-'` (placeholder / unclassified)
- Operations costs from other business verticals (`For Sale`, `Corporate`, etc.)
- Non-Operations P&L lines (`Sales`, `Marketing`, `G&A`, revenues, derived results)
- Post-Contract-only views (those require additional `bece_l2` and `pl_line_2` filters — see [Absolute Cost Post-Contract (For Rent)](./absolute_cost_post_contract_fr.md))

## Calculation

A naive `SUM(amount)` without scope filters will aggregate unrelated P&L categories and business verticals. A naive filter on `Operations` without `BeCe Business = 'For Rent'` will include Operations costs from other businesses.

The correct calculation is:

```
Absolute Cost Ops Total (For Rent) = SUM(<YYYYMM amount>)
```

where each amount comes from rows matching the canonical filter below. Amounts are summed **as recorded** — do not apply `ABS()`. Costs are predominantly **negative** and revenue offsets / tax credits may be **positive**; the result is the net liquid Operations figure for For Rent.

### Canonical Filter

Apply on `datalake_luigijr_ops_finance_clean.finance_revenue_cost_2025` or `finance_revenue_cost_2026` (see [table selection](../business_entities/finance_revenue_cost.md#table-selection-by-year)):

```sql
bece_business = 'For Rent'
AND pl_line_1 = 'Operations'
AND reporting_group <> '-'
AND version = 'Actuals'
```

Column names in the uploaded table are **lowercased**, **spaces replaced by underscores**, and **`&` removed** (e.g. `BeCe Business` → `bece_business`, `P&L Line 1` → `pl_line_1`).

**Warning**: Adding `bece_l2 = '<owner>'` or restricting `pl_line_2` narrows the result to a subset (e.g. Post-Contract) and **no longer produces the total For Rent Operations cost**.

### Nuances

**Period selection**: Months are not a categorical column. Select the target month by reading the corresponding `YYYYMM` column (e.g. `"202603"` for March 2026) from the table for that year. Period column names are unaffected by the lower/underscore transform. To build a time series, unpivot the relevant `YYYYMM` columns — see the golden query below.

**Empty cells**: Treat empty period cells as missing, not as zero.

**Sign convention**: Sum raw amounts without `ABS()`. A negative result indicates net cost; a positive result indicates net revenue offset exceeding costs within the filtered scope.

**Type casting**: Period columns are stored as `varchar` after upload. Cast to numeric before aggregating: `TRY_CAST(REPLACE(f."<YYYYMM>", ',', '') AS DOUBLE)`.

| Parameter   | Description                                                                                                                      |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `<YYYYMM>`  | Target month column name (e.g. `202603`). Query the table for the matching calendar year.                                        |

**Fallback**: If the requested `YYYYMM` column is empty for `version = 'Actuals'`, the metric is undefined for that period — do not fall back to a different `version` silently.

## Dos and Don'ts

**Do:**

- Always filter `bece_business = 'For Rent'` and `pl_line_1 = 'Operations'`
- Exclude placeholder rows: `reporting_group <> '-'`
- Use `version = 'Actuals'` for the standard realized-cost metric
- Query `finance_revenue_cost_2025` or `finance_revenue_cost_2026` according to the target year
- Sum raw amounts — do **not** apply `ABS()`; the metric is net liquid, not absolute
- Use lowercased, underscore-separated column names as they appear post-upload

**Don't:**

- Omit the `version` filter — this mixes scenarios and produces wrong totals
- Include rows with `reporting_group = '-'`
- Filter `bece_l2` or `pl_line_2` when computing the **total** For Rent cost (that produces the Post-Contract subset)
- Assume a `month` or `period` dimension column exists — months are wide `YYYYMM` columns
- Treat empty cells as zero
- Apply `ABS()` — this metric is net liquid, not absolute cost

## Targets and OKRs

The canonical filter uses `version = 'Actuals'` for realized costs. The same `YYYYMM` column can produce **different metric values** for other scenarios:

| Scenario | Typical `version` value                          | Use case                 |
| -------- | ------------------------------------------------ | ------------------------ |
| Actuals  | `Actuals`                                        | Realized / closed costs  |
| Budget   | `Budget <YYYY> - <MM>` (label varies by refresh) | Budget comparison        |
| Forecast | `Forecast 5+7` (label may vary)                  | Forward-looking forecast |
| OKR      | `OKR100 <YYYY> - <MM>` (label may vary)          | OKR target scenario      |

**Always pair the target `YYYYMM` column with the matching `version`.** For the standard Actuals metric, use `version = 'Actuals'`. Exact `version` labels may change between monthly refreshes — confirm available values before querying.

**Budget (Target)** — orçamento mensal do custo total Operations For Rent na tabela financeira.

- **Source table:** `datalake_luigijr_ops_finance_clean.finance_revenue_cost_2025` / `finance_revenue_cost_2026` (ver [table selection](../business_entities/finance_revenue_cost.md#table-selection-by-year))
- **Filter key / metric name:** coluna `version` = `Budget <YYYY> - <MM>` (label varia por refresh); aplicar o mesmo canonical filter de Calculation com `version` substituído
- **Period grain:** mensal — coluna `YYYYMM` wide-format
- **Aliases / search terms:** orçamento, budget, target, cost of service For Rent
- **Caveat:** labels exatos podem mudar entre refreshes; nunca agregar across `version` values

**OKR** — meta de período (OKR100) na mesma tabela.

- **Source table:** `datalake_luigijr_ops_finance_clean.finance_revenue_cost_2025` / `finance_revenue_cost_2026`
- **Filter key / metric name:** coluna `version` = `OKR100 <YYYY> - <MM>` (label varia por refresh); aplicar o mesmo canonical filter de Calculation com `version` substituído
- **Period grain:** mensal — coluna `YYYYMM`
- **Aliases / search terms:** meta, OKR, OKR100
- **Caveat:** confirmar labels disponíveis antes de consultar; parear `YYYYMM` + `version`

## Golden Queries

Single-month net cost (Actuals). Replace `<YYYYMM>` and use the table for the matching year (`_2025` or `_2026`).

```sql
SELECT
    SUM(TRY_CAST(REPLACE(f."<YYYYMM>", ',', '') AS DOUBLE)) AS absolute_cost_ops_total_fr
FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_<YEAR> f
WHERE f.bece_business = 'For Rent'
  AND f.pl_line_1 = 'Operations'
  AND f.reporting_group <> '-'
  AND f.version = 'Actuals'
  AND TRY_CAST(REPLACE(f."<YYYYMM>", ',', '') AS DOUBLE) IS NOT NULL;
```

Monthly time series for Actuals across 2025 and 2026. Extend the `VALUES` lists as new `YYYYMM` columns become available.

```sql
SELECT
    t.period_yyyymm,
    SUM(TRY_CAST(REPLACE(t.amount, ',', '') AS DOUBLE)) AS absolute_cost_ops_total_fr
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
  AND f.pl_line_1 = 'Operations'
  AND f.reporting_group <> '-'
  AND f.version = 'Actuals'
  AND TRY_CAST(REPLACE(t.amount, ',', '') AS DOUBLE) IS NOT NULL
GROUP BY 1

UNION ALL

SELECT
    t.period_yyyymm,
    SUM(TRY_CAST(REPLACE(t.amount, ',', '') AS DOUBLE)) AS absolute_cost_ops_total_fr
FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026 f
CROSS JOIN LATERAL (
    VALUES
        ('202601', f."202601"),
        ('202602', f."202602"),
        ('202603', f."202603")
) AS t(period_yyyymm, amount)
WHERE f.bece_business = 'For Rent'
  AND f.pl_line_1 = 'Operations'
  AND f.reporting_group <> '-'
  AND f.version = 'Actuals'
  AND TRY_CAST(REPLACE(t.amount, ',', '') AS DOUBLE) IS NOT NULL
GROUP BY 1
ORDER BY 1;
```

To compare budget or OKR scenarios for the same month, change `version` and keep all other filters — never aggregate across versions in one pass.
