# Offboarding Unit Cost (For Rent)

## Ownership

**Data Owner:**
- felipe.abreu@quintoandar.com.br

**Data Steward:**
- jacqueline.gomez@quintoandar.com.br
- livia.borges@quintoandar.com.br

## Overview

**Offboarding Unit Cost (For Rent)** is the **Offboarding** net Operations cost per **ended rental** for the For Rent business. It measures how much Offboarding spend is incurred for each rental that ended in the period.

```
Offboarding UC = Offboarding net cost (For Rent) ÷ Ended Rentals
```

This metric differs from [Onboarding Unit Cost (For Rent)](./onboarding_uc_fr.md) and [Ongoing Unit Cost (For Rent)](./ongoing_uc_fr.md), which use different `P&L Line 2` numerators and volume denominators. It also differs from [Absolute Cost Post-Contract (For Rent)](./absolute_cost_post_contract_fr.md), which sums all Operations lines for the area.

Related metrics: [Absolute Cost Post-Contract (For Rent)](./absolute_cost_post_contract_fr.md), [Absolute Cost Ops Total (For Rent)](./absolute_cost_ops_total_fr.md), [Onboarding Unit Cost (For Rent)](./onboarding_uc_fr.md), [Ongoing Unit Cost (For Rent)](./ongoing_uc_fr.md).

**Exists exclusively for For Rent.**

## Related Domain Entities

- Finance Revenue and Cost

## Catalog

| Metric | Type |
| :---- | :---- |
| Offboarding Unit Cost (For Rent) | OKR |

## MBR

**Name** Post Contract
**Category** Cost of Service

## Glossary and Synonyms

- **Offboarding UC**, **unit cost Offboarding**, **custo unitário Offboarding**, **Offboarding UC Post-Contract** → this metric

## Scope

**Included**:

- **Numerator**: net liquid Offboarding cost from `finance_revenue_cost_2025` / `finance_revenue_cost_2026` — `bece_business = 'For Rent'`, `pl_line_1 = 'Operations'`, `pl_line_2 = 'Offboarding'`, `reporting_group <> '-'`, summed across all `bece_l2` owners
- **Denominator**: ended rental volume from the same table — `pl_line_4 = 'Ended Rentals'`, volume-row pattern (`pl_line_1` = `-`, `bece_l2 = 'Lucas Lima'`), summed across `bece_product` for the target `YYYYMM` column

**Excluded**:

- `Operations Overhead`, `Operations Tax Credit`, `Onboarding`, `Ongoing` (other `pl_line_2` values)
- Operations costs from other business verticals
- Non-Operations P&L lines

## Calculation

Dividing total For Rent Operations cost by ended rentals produces the wrong unit cost — it blends Onboarding, Ongoing, Offboarding, and overhead. Using a denominator metric other than `Ended Rentals` misaligns the volume definition from finance.

The correct calculation is:

```
Offboarding UC = SUM(Offboarding net cost for month) / SUM(Ended Rentals for month)
```

where:

- **Offboarding net cost** — rows matching the numerator canonical filter; amounts summed as recorded (no `ABS()`)
- **Ended Rentals** — rows matching the denominator canonical filter; summed across `bece_product` (e.g. `Full Rental`, `Brokerage Only`, `Rede`)

### Canonical Filter

#### Numerator

Apply on `datalake_luigijr_ops_finance_clean.finance_revenue_cost_<YEAR>`:

```sql
bece_business = 'For Rent'
AND pl_line_1 = 'Operations'
AND pl_line_2 = 'Offboarding'
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
AND pl_line_4 = 'Ended Rentals'
AND version = '<VERSION>'
```

Aggregate with `SUM(TRY_CAST(REPLACE("<YYYYMM>", ',', '') AS DOUBLE))` across all matching rows (including all `bece_product` values).

**Warning**: Do not include `pl_line_2` values other than `Offboarding` in the numerator. Do **not** filter `bece_l2` on cost rows. Use `Ended Rentals` — not `New Rentals (active)` or `Ongoing Rentals (active)`.

### Nuances

**Product split**: `Ended Rentals` is reported per `bece_product`. Sum all product rows for the For Rent total denominator.

**Cost vs volume scope**: The cost numerator sums Offboarding Operations across all `bece_l2` owners in For Rent. Volume denominators use `bece_l2 = 'Lucas Lima'` on volume rows only.

**Sign convention**: Offboarding cost is summed without `ABS()`. Costs are predominantly negative; the unit cost inherits that sign.

**Type casting**: Period columns are `varchar` after upload. Cast before aggregating: `TRY_CAST(REPLACE(f."<YYYYMM>", ',', '') AS DOUBLE)`.

| Parameter | Description |
| :---- | :---- |
| `<VERSION>` | Financial scenario for both numerator and denominator. Required. |
| `<YYYYMM>`  | Target month column (e.g. `202603`). Use `finance_revenue_cost_2026` for 2026 months. |
| `<YEAR>`    | `2025` or `2026` — must match the calendar year of `<YYYYMM>`. |

**Fallback**: If either numerator or denominator is null or zero for the period, the UC is undefined — do not substitute a different month or scenario.

## Dos and Don'ts

**Do:**

- Filter numerator to `pl_line_2 = 'Offboarding'` only
- Sum Offboarding cost across all `bece_l2` owners (no `bece_l2` filter on the numerator)
- Use `pl_line_4 = 'Ended Rentals'` for ended rentals volume
- Use `bece_l2 = 'Lucas Lima'` on volume rows
- Pair the same `version` and `YYYYMM` on numerator and denominator
- Sum across `bece_product` for the For Rent total
- Cast `YYYYMM` columns to numeric before summing
- Exclude placeholder cost rows: `reporting_group <> '-'` on the numerator
- Query the table for the matching year (`finance_revenue_cost_2025` or `_2026`)

**Don't:**

- Include `Operations Overhead`, `Operations Tax Credit`, `Onboarding`, or `Ongoing` in the numerator
- Use total For Rent Operations cost as numerator (blend all `pl_line_2` values)
- Filter `bece_l2` on the cost numerator — UC costs are not scoped to a single owner
- Use `New Rentals (active)` or `Ongoing Rentals (active)` as the ended-rentals denominator
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

### Denominator — Ended Rentals by month

```sql
SELECT
    f.version,
    -- Change the "202603" column to the target month (YYYYMM).
    SUM(TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)) AS ended_rentals
-- Change the _2026 suffix to the calendar year of the month above (_2025 or _2026).
FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026 f
WHERE f.bece_business = 'For Rent'
  AND f.bece_l2 = 'Lucas Lima'
  AND f.pl_line_1 = '-'
  AND f.pl_line_2 = '-'
  AND f.pl_line_3 = '-'
  AND f.pl_line_4 = 'Ended Rentals'
  -- Change to 'Budget' or 'OKR' to read a target instead of the actual.
  AND f.version = 'Actuals'
  AND TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE) IS NOT NULL
GROUP BY 1;
```

### Offboarding UC — single month

Written for March 2026 Actuals.

```sql
WITH offboarding_cost AS (
    SELECT
        -- Change every "202603" column reference to the target month (YYYYMM).
        SUM(TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)) AS offboarding_cost
    -- Change the _2026 suffix to the calendar year of the month above (_2025 or _2026).
    FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026 f
    WHERE f.bece_business = 'For Rent'
      AND f.pl_line_1 = 'Operations'
      AND f.pl_line_2 = 'Offboarding'
      AND f.reporting_group <> '-'
      -- Change to 'Budget' or 'OKR' to read a target instead of the actual.
      AND f.version = 'Actuals'
      AND TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE) IS NOT NULL
),
ended_rentals AS (
    SELECT
        SUM(TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)) AS ended_rentals
    FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026 f
    WHERE f.bece_business = 'For Rent'
      AND f.bece_l2 = 'Lucas Lima'
      AND f.pl_line_1 = '-'
      AND f.pl_line_2 = '-'
      AND f.pl_line_3 = '-'
      AND f.pl_line_4 = 'Ended Rentals'
      AND f.version = 'Actuals'
      AND TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE) IS NOT NULL
)
SELECT
    oc.offboarding_cost,
    er.ended_rentals,
    oc.offboarding_cost / er.ended_rentals AS offboarding_uc
FROM offboarding_cost oc
CROSS JOIN ended_rentals er;
```

### Example — March 2026 Actuals

```sql
WITH offboarding_cost AS (
    SELECT
        SUM(TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)) AS offboarding_cost
    FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026 f
    WHERE f.bece_business = 'For Rent'
      AND f.pl_line_1 = 'Operations'
      AND f.pl_line_2 = 'Offboarding'
      AND f.reporting_group <> '-'
      AND f.version = 'Actuals'
      AND TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE) IS NOT NULL
),
ended_rentals AS (
    SELECT
        SUM(TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)) AS ended_rentals
    FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026 f
    WHERE f.bece_business = 'For Rent'
      AND f.bece_l2 = 'Lucas Lima'
      AND f.pl_line_1 = '-'
      AND f.pl_line_2 = '-'
      AND f.pl_line_3 = '-'
      AND f.pl_line_4 = 'Ended Rentals'
      AND f.version = 'Actuals'
      AND TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE) IS NOT NULL
)
SELECT
    oc.offboarding_cost,
    er.ended_rentals,
    oc.offboarding_cost / er.ended_rentals AS offboarding_uc
FROM offboarding_cost oc
CROSS JOIN ended_rentals er;
```

To compare budget or OKR scenarios, change `version` on **both** CTEs to the matching scenario label.

