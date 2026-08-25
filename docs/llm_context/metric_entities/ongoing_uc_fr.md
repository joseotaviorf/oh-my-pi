# Ongoing Unit Cost (For Rent)

## Ownership

**Data Owner:**
- felipe.abreu@quintoandar.com.br

**Data Steward:**
- jacqueline.gomez@quintoandar.com.br
- livia.borges@quintoandar.com.br

## Overview

**Ongoing Unit Cost (For Rent)** is the **Ongoing** net Operations cost per ongoing rental (excluding new rentals) for the For Rent business. It measures how much Ongoing spend is incurred for each rental in the ongoing base of the period.

```
Ongoing UC = Ongoing net cost (For Rent) ÷ (Ongoing Rentals − New Rentals)
```

**New Rentals are subtracted** from the Ongoing Rentals snapshot to avoid double-counting contracts that entered the ongoing base during the same month. The dataset provides this adjustment pre-calculated as `Ongoing (-) New Rentals` in `pl_line_4`.

This metric differs from [Onboarding Unit Cost (For Rent)](./onboarding_uc_fr.md) (which uses Onboarding cost ÷ New Rentals) and from [Absolute Cost Post-Contract (For Rent)](./absolute_cost_post_contract_fr.md) (absolute Operations total for the area).

Related metrics: [Absolute Cost Ops Total (For Rent)](./absolute_cost_ops_total_fr.md), [Onboarding Unit Cost (For Rent)](./onboarding_uc_fr.md), [Offboarding Unit Cost (For Rent)](./offboarding_uc_fr.md).

**Exists exclusively for For Rent.**

## Related Domain Entities

- Finance Revenue and Cost

## Catalog

| Metric | Type |
| :---- | :---- |
| Ongoing Unit Cost (For Rent) | OKR |

## MBR

**Name** Post Contract
**Category** Cost of Service

## Glossary and Synonyms

- **Ongoing UC**, **unit cost Ongoing**, **custo unitário Ongoing**, **Ongoing UC Post-Contract** → this metric

## Scope

**Included**:

- **Numerator**: net liquid Ongoing cost from `finance_revenue_cost_2025` / `finance_revenue_cost_2026` — `bece_business = 'For Rent'`, `pl_line_1 = 'Operations'`, `pl_line_2 = 'Ongoing'`, `reporting_group <> '-'`, summed across all `bece_l2` owners
- **Denominator**: adjusted ongoing rental base from the same table — `pl_line_4 = 'Ongoing (-) New Rentals'`, volume-row pattern (`pl_line_1` = `-`, `bece_l2 = 'Lucas Lima'`), summed across `bece_product` for the target `YYYYMM` column

**Excluded**:

- `Operations Overhead`, `Operations Tax Credit`, `Onboarding`, `Offboarding` (other `pl_line_2` values)
- Using raw `Ongoing Rentals (active)` without subtracting New Rentals (causes double count)

## Calculation

Dividing Ongoing cost by total Ongoing Rentals without subtracting New Rentals **overstates the denominator** — new rentals signed in the month are already embedded in the ongoing snapshot. Using total For Rent Operations cost as numerator blends all Operations lines.

The correct calculation is:

```
Ongoing UC = SUM(Ongoing net cost for month) / SUM(Ongoing (-) New Rentals for month)
```

Equivalent validation (should match at For Rent level):

```
SUM(Ongoing Rentals (active)) − SUM(New Rentals (active)) = SUM(Ongoing (-) New Rentals)
```

where:

- **Ongoing net cost** — rows matching the numerator canonical filter; summed as recorded (no `ABS()`)
- **Ongoing (-) New Rentals** — pre-calculated adjusted ongoing base per product; sum across `bece_product` for the For Rent total

### Canonical Filter

#### Numerator

Apply on `datalake_luigijr_ops_finance_clean.finance_revenue_cost_<YEAR>`:

```sql
bece_business = 'For Rent'
AND pl_line_1 = 'Operations'
AND pl_line_2 = 'Ongoing'
AND reporting_group <> '-'
AND version = '<VERSION>'
```

#### Denominator

Apply on the same table (volume rows have `reporting_group = '-'` — do not apply the cost-side `reporting_group` filter here):

```sql
bece_business = 'For Rent'
AND bece_l2 = 'Lucas Lima'
AND pl_line_1 = '-'
AND pl_line_2 = '-'
AND pl_line_3 = '-'
AND pl_line_4 = 'Ongoing (-) New Rentals'
AND version = '<VERSION>'
```

Aggregate with `SUM(TRY_CAST(REPLACE("<YYYYMM>", ',', '') AS DOUBLE))` across all matching rows (including all `bece_product` values).

**Warning**: Do not use `pl_line_2` values other than `Ongoing` in the numerator. Do not use `Ongoing Rentals (active)` alone as denominator — that double-counts new rentals. Prefer the pre-calculated `Ongoing (-) New Rentals` row.

### Nuances

**Pre-calculated adjustment**: `Ongoing (-) New Rentals` is maintained per `bece_product` in the source data. At For Rent level, sum all product rows — do not manually subtract only the `Full Rental` product.

**Cost vs volume scope**: The cost numerator sums Ongoing Operations across all `bece_l2` owners in For Rent. Volume denominators use `bece_l2 = 'Lucas Lima'` on volume rows only.

**Sign convention**: Ongoing cost is summed without `ABS()`. Costs are predominantly negative; the unit cost inherits that sign.

**Type casting**: Period columns are `varchar` after upload. Cast before aggregating: `TRY_CAST(REPLACE(f."<YYYYMM>", ',', '') AS DOUBLE)`.

| Parameter | Description |
| :---- | :---- |
| `<VERSION>` | Financial scenario for both numerator and denominator. Required. |
| `<YYYYMM>`  | Target month column (e.g. `202603`). Use `finance_revenue_cost_2026` for 2026 months. |
| `<YEAR>`    | `2025` or `2026` — must match the calendar year of `<YYYYMM>`. |

**Fallback**: If the denominator is null or zero for the period, the UC is undefined.

## Dos and Don'ts

**Do:**

- Filter numerator to `pl_line_2 = 'Ongoing'` only
- Sum Ongoing cost across all `bece_l2` owners (no `bece_l2` filter on the numerator)
- Use `pl_line_4 = 'Ongoing (-) New Rentals'` as denominator
- Use `bece_l2 = 'Lucas Lima'` on volume rows
- Pair the same `version` and `YYYYMM` on numerator and denominator
- Sum across `bece_product` for the For Rent total
- Cast `YYYYMM` columns to numeric before summing
- Exclude placeholder cost rows: `reporting_group <> '-'` on the numerator
- Query the table for the matching year (`finance_revenue_cost_2025` or `_2026`)

**Don't:**

- Divide by `Ongoing Rentals (active)` without subtracting New Rentals
- Include `Onboarding`, `Offboarding`, `Operations Overhead`, or `Operations Tax Credit` in the numerator
- Filter `bece_l2` on the cost numerator — UC costs are not scoped to a single owner
- Mix `Actuals` cost with budget/OKR volume
- Apply `ABS()` — cost is net liquid
- Join to external volume tables — denominators are in this table

## Targets and OKRs

Both numerator and denominator use the `version` column in the year-matching table (`finance_revenue_cost_2025` or `finance_revenue_cost_2026`). For realized values, use `version = 'Actuals'` (canonical filter default). Forecast uses labels `Forecast …`.

| Scenario | `version` (numerator and denominator) |
| -------- | ------------------------------------- |
| Actuals  | `Actuals`                             |
| Budget   | `Budget <YYYY> - <MM>`                |
| Forecast | `Forecast …`                          |
| OKR      | `OKR100 <YYYY> - <MM>`                |

**Always pair numerator and denominator from the same `version` and `YYYYMM` column.**

**Budget (Target)** — orçamento mensal da métrica na tabela financeira; `version` label `Budget <YYYY> - <MM>`.

- **Source table:** `datalake_luigijr_ops_finance_clean.finance_revenue_cost_2025` / `finance_revenue_cost_2026` (ver [table selection](../domain_entities/finance_revenue_cost.md#table-selection-by-year))
- **Filter key / metric name:** coluna `version` = `Budget <YYYY> - <MM>` (label varia por refresh)
- **Period grain:** mensal — coluna `YYYYMM` wide-format
- **Aliases / search terms:** orçamento, budget, target
- **Caveat:** **sempre** parear numerator e denominator com o mesmo `version` e `YYYYMM`; labels exatos podem mudar entre refreshes

**OKR** — meta de período (OKR100) na mesma tabela.

- **Source table:** `datalake_luigijr_ops_finance_clean.finance_revenue_cost_2025` / `finance_revenue_cost_2026`
- **Filter key / metric name:** coluna `version` = `OKR100 <YYYY> - <MM>` (label varia por refresh)
- **Period grain:** mensal — coluna `YYYYMM`
- **Aliases / search terms:** meta, OKR, OKR100
- **Caveat:** parear numerator/denominator no mesmo scenario; confirmar labels disponíveis antes de consultar

## Golden Queries

### Denominator — Ongoing (-) New Rentals by month

```sql
SELECT
    f.version,
    -- Change the "202603" column to the target month (YYYYMM).
    SUM(TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)) AS ongoing_base
-- Change the _2026 suffix to the calendar year of the month above (_2025 or _2026).
FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026 f
WHERE f.bece_business = 'For Rent'
  AND f.bece_l2 = 'Lucas Lima'
  AND f.pl_line_1 = '-'
  AND f.pl_line_2 = '-'
  AND f.pl_line_3 = '-'
  AND f.pl_line_4 = 'Ongoing (-) New Rentals'
  -- Change to 'Budget' or 'OKR' to read a target instead of the actual.
  AND f.version = 'Actuals'
  AND TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE) IS NOT NULL
GROUP BY 1;
```

### Ongoing UC — single month

Written for March 2026 Actuals.

```sql
WITH ongoing_cost AS (
    SELECT
        -- Change every "202603" column reference to the target month (YYYYMM).
        SUM(TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)) AS ongoing_cost
    -- Change the _2026 suffix to the calendar year of the month above (_2025 or _2026).
    FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026 f
    WHERE f.bece_business = 'For Rent'
      AND f.pl_line_1 = 'Operations'
      AND f.pl_line_2 = 'Ongoing'
      AND f.reporting_group <> '-'
      -- Change to 'Budget' or 'OKR' to read a target instead of the actual.
      AND f.version = 'Actuals'
      AND TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE) IS NOT NULL
),
ongoing_base AS (
    SELECT
        SUM(TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)) AS ongoing_base
    FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026 f
    WHERE f.bece_business = 'For Rent'
      AND f.bece_l2 = 'Lucas Lima'
      AND f.pl_line_1 = '-'
      AND f.pl_line_2 = '-'
      AND f.pl_line_3 = '-'
      AND f.pl_line_4 = 'Ongoing (-) New Rentals'
      AND f.version = 'Actuals'
      AND TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE) IS NOT NULL
)
SELECT
    oc.ongoing_cost,
    ob.ongoing_base,
    oc.ongoing_cost / ob.ongoing_base AS ongoing_uc
FROM ongoing_cost oc
CROSS JOIN ongoing_base ob;
```

### Example — March 2026 Actuals

```sql
WITH ongoing_cost AS (
    SELECT
        SUM(TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)) AS ongoing_cost
    FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026 f
    WHERE f.bece_business = 'For Rent'
      AND f.pl_line_1 = 'Operations'
      AND f.pl_line_2 = 'Ongoing'
      AND f.reporting_group <> '-'
      AND f.version = 'Actuals'
      AND TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE) IS NOT NULL
),
ongoing_base AS (
    SELECT
        SUM(TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)) AS ongoing_base
    FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026 f
    WHERE f.bece_business = 'For Rent'
      AND f.bece_l2 = 'Lucas Lima'
      AND f.pl_line_1 = '-'
      AND f.pl_line_2 = '-'
      AND f.pl_line_3 = '-'
      AND f.pl_line_4 = 'Ongoing (-) New Rentals'
      AND f.version = 'Actuals'
      AND TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE) IS NOT NULL
)
SELECT
    oc.ongoing_cost,
    ob.ongoing_base,
    oc.ongoing_cost / ob.ongoing_base AS ongoing_uc
FROM ongoing_cost oc
CROSS JOIN ongoing_base ob;
```

To compare budget or OKR scenarios, change `version` on **both** CTEs to the matching scenario label.

