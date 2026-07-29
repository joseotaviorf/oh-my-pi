# Onboarding Unit Cost (For Rent)

## Ownership

**Data Owner:**
- felipe.abreu@quintoandar.com.br

**Data Steward:**
- jacqueline.gomez@quintoandar.com.br
- livia.borges@quintoandar.com.br

## Overview

**Onboarding Unit Cost (For Rent)** is the **Onboarding** net Operations cost per **New Rental** for the For Rent business. It measures how much Onboarding spend is incurred for each new rental signed in the period.

```
Onboarding UC = Onboarding net cost (For Rent) ÷ New Rentals volume
```

This metric differs from [Absolute Cost Post-Contract (For Rent)](./absolute_cost_post_contract_fr.md) (which sums all Operations lines for the area) and from total For Rent Operations cost. It uses only the `Onboarding` `P&L Line 2` component as numerator and **New Rentals (active)** volume as denominator.

Related metrics: [Absolute Cost Ops Total (For Rent)](./absolute_cost_ops_total_fr.md), [Ongoing Unit Cost (For Rent)](./ongoing_uc_fr.md), [Offboarding Unit Cost (For Rent)](./offboarding_uc_fr.md).

**Exists exclusively for For Rent.**

## Related Business Entities

- Finance Revenue and Cost

## MBR

- Post Contract

## Glossary and Synonyms

- **Onboarding UC**, **unit cost Onboarding**, **custo unitário Onboarding**, **Onboarding UC Post-Contract** → this metric

## Scope

**Included**:

- **Numerator**: net liquid Onboarding cost from `finance_revenue_cost_2025` / `finance_revenue_cost_2026` — `bece_business = 'For Rent'`, `pl_line_1 = 'Operations'`, `pl_line_2 = 'Onboarding'`, `reporting_group <> '-'`, summed across all `bece_l2` owners
- **Denominator**: New Rental volume from the same table — `pl_line_4 = 'New Rentals (active)'`, volume-row pattern (`pl_line_1` = `-`, `bece_l2 = 'Lucas Lima'`), summed across `bece_product` for the target `YYYYMM` column

**Excluded**:

- `Operations Overhead`, `Operations Tax Credit`, `Ongoing`, `Offboarding` (other `pl_line_2` values — not unitarized in this metric)
- Operations costs from other business verticals
- Non-Operations P&L lines

## Calculation

Dividing total For Rent Operations cost by New Rentals produces the wrong unit cost — it blends Onboarding, Ongoing, Offboarding, and overhead. The numerator must be restricted to `pl_line_2 = 'Onboarding'` only.

The correct calculation is:

```
Onboarding UC = SUM(Onboarding net cost for month) / SUM(New Rentals (active) for month)
```

where:

- **Onboarding net cost** — rows matching the numerator canonical filter; amounts summed as recorded (no `ABS()`)
- **New Rentals volume** — rows matching the denominator canonical filter; summed across products for the same `version` and `YYYYMM` column

### Canonical Filter

#### Numerator

Apply on `datalake_luigijr_ops_finance_clean.finance_revenue_cost_<YEAR>`:

```sql
bece_business = 'For Rent'
AND pl_line_1 = 'Operations'
AND pl_line_2 = 'Onboarding'
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
AND pl_line_4 = 'New Rentals (active)'
AND version = '<VERSION>'
```

Aggregate with `SUM(TRY_CAST(REPLACE("<YYYYMM>", ',', '') AS DOUBLE))` across all matching rows (including all `bece_product` values).

**Warning**: Do not include `pl_line_2` values other than `Onboarding` in the numerator. Do **not** filter `bece_l2` on cost rows — UC numerators aggregate across all organizational owners within For Rent. Do not filter cost rows when reading volume denominators (`pl_line_1` must be `-`).

### Nuances

**Cost vs volume scope**: The cost numerator sums Onboarding Operations across all `bece_l2` owners in For Rent. Volume denominators use `bece_l2 = 'Lucas Lima'` on volume rows only.

**Sign convention**: Onboarding cost is summed without `ABS()`. Costs are predominantly negative; the unit cost inherits that sign. A negative UC means net cost per new rental.

**Type casting**: Period columns are `varchar` after upload. Cast before aggregating: `TRY_CAST(REPLACE(f."<YYYYMM>", ',', '') AS DOUBLE)`.

| Parameter | Description |
| :---- | :---- |
| `<VERSION>` | Financial scenario for both numerator and denominator. Required. |
| `<YYYYMM>`  | Target month column (e.g. `202603`). Use `finance_revenue_cost_2026` for 2026 months. |
| `<YEAR>`    | `2025` or `2026` — must match the calendar year of `<YYYYMM>`. |

**Fallback**: If either numerator or denominator is null or zero for the period, the UC is undefined — do not substitute a different month or scenario.

## Dos and Don'ts

**Do:**

- Filter numerator to `pl_line_2 = 'Onboarding'` only
- Sum Onboarding cost across all `bece_l2` owners (no `bece_l2` filter on the numerator)
- Read denominator from `pl_line_4 = 'New Rentals (active)'` with `pl_line_1 = '-'`
- Use `bece_l2 = 'Lucas Lima'` on volume rows
- Pair the same `version` and `YYYYMM` on numerator and denominator
- Sum across `bece_product` for the For Rent total
- Cast `YYYYMM` columns to numeric before summing
- Exclude placeholder cost rows: `reporting_group <> '-'` on the numerator
- Query the table for the matching year (`finance_revenue_cost_2025` or `_2026`)

**Don't:**

- Include `Operations Overhead` or `Operations Tax Credit` in the numerator
- Use total For Rent Operations cost as numerator (blend all `pl_line_2` values)
- Filter `bece_l2` on the cost numerator — UC costs are not scoped to a single owner
- Mix `Actuals` cost with budget/OKR volume (or vice versa)
- Apply `ABS()` — cost is net liquid
- Join to external volume tables — denominators are in this table

## Targets and OKRs

Both numerator and denominator use the `version` column in the year-matching table (`finance_revenue_cost_2025` or `finance_revenue_cost_2026`). Pair them on the **same scenario and month**. For realized values, use `version = 'Actuals'` (canonical filter default). Forecast uses labels `Forecast …`.

| Scenario | `version` (numerator and denominator) |
| -------- | ------------------------------------- |
| Actuals  | `Actuals`                             |
| Budget   | `Budget <YYYY> - <MM>`                |
| Forecast | `Forecast …`                          |
| OKR      | `OKR100 <YYYY> - <MM>`                |

**Always pair numerator and denominator from the same `version` and `YYYYMM` column.** Mixing `Actuals` cost with budget volume (or vice versa) produces an invalid unit cost.

**Budget (Target)** — orçamento mensal da métrica na tabela financeira; `version` label `Budget <YYYY> - <MM>`.

- **Source table:** `datalake_luigijr_ops_finance_clean.finance_revenue_cost_2025` / `finance_revenue_cost_2026` (ver [table selection](../business_entities/finance_revenue_cost.md#table-selection-by-year))
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

### Denominator — New Rentals by month

```sql
SELECT
    f.version,
    SUM(TRY_CAST(REPLACE(f."<YYYYMM>", ',', '') AS DOUBLE)) AS new_rentals
FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_<YEAR> f
WHERE f.bece_business = 'For Rent'
  AND f.bece_l2 = 'Lucas Lima'
  AND f.pl_line_1 = '-'
  AND f.pl_line_2 = '-'
  AND f.pl_line_3 = '-'
  AND f.pl_line_4 = 'New Rentals (active)'
  AND f.version = '<VERSION>'
  AND TRY_CAST(REPLACE(f."<YYYYMM>", ',', '') AS DOUBLE) IS NOT NULL
GROUP BY 1;
```

### Onboarding UC — single month

Replace `<YYYYMM>`, `<YEAR>`, and `<VERSION>` for the target month.

```sql
WITH onboarding_cost AS (
    SELECT
        SUM(TRY_CAST(REPLACE(f."<YYYYMM>", ',', '') AS DOUBLE)) AS onboarding_cost
    FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_<YEAR> f
    WHERE f.bece_business = 'For Rent'
      AND f.pl_line_1 = 'Operations'
      AND f.pl_line_2 = 'Onboarding'
      AND f.reporting_group <> '-'
      AND f.version = '<VERSION>'
      AND TRY_CAST(REPLACE(f."<YYYYMM>", ',', '') AS DOUBLE) IS NOT NULL
),
new_rentals AS (
    SELECT
        SUM(TRY_CAST(REPLACE(f."<YYYYMM>", ',', '') AS DOUBLE)) AS new_rentals
    FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_<YEAR> f
    WHERE f.bece_business = 'For Rent'
      AND f.bece_l2 = 'Lucas Lima'
      AND f.pl_line_1 = '-'
      AND f.pl_line_2 = '-'
      AND f.pl_line_3 = '-'
      AND f.pl_line_4 = 'New Rentals (active)'
      AND f.version = '<VERSION>'
      AND TRY_CAST(REPLACE(f."<YYYYMM>", ',', '') AS DOUBLE) IS NOT NULL
)
SELECT
    oc.onboarding_cost,
    nr.new_rentals,
    oc.onboarding_cost / nr.new_rentals AS onboarding_uc
FROM onboarding_cost oc
CROSS JOIN new_rentals nr;
```

### Example — March 2026 Actuals

```sql
WITH onboarding_cost AS (
    SELECT
        SUM(TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)) AS onboarding_cost
    FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026 f
    WHERE f.bece_business = 'For Rent'
      AND f.pl_line_1 = 'Operations'
      AND f.pl_line_2 = 'Onboarding'
      AND f.reporting_group <> '-'
      AND f.version = 'Actuals'
      AND TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE) IS NOT NULL
),
new_rentals AS (
    SELECT
        SUM(TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)) AS new_rentals
    FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026 f
    WHERE f.bece_business = 'For Rent'
      AND f.bece_l2 = 'Lucas Lima'
      AND f.pl_line_1 = '-'
      AND f.pl_line_2 = '-'
      AND f.pl_line_3 = '-'
      AND f.pl_line_4 = 'New Rentals (active)'
      AND f.version = 'Actuals'
      AND TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE) IS NOT NULL
)
SELECT
    oc.onboarding_cost,
    nr.new_rentals,
    oc.onboarding_cost / nr.new_rentals AS onboarding_uc
FROM onboarding_cost oc
CROSS JOIN new_rentals nr;
```

To compare budget or OKR scenarios, change `version` on **both** CTEs to the matching scenario label.
