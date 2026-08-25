# Absolute Cost Post-Contract (For Rent)

## Ownership

**Data Owner:**
- felipe.abreu@quintoandar.com.br

**Data Steward:**
- jacqueline.gomez@quintoandar.com.br
- livia.borges@quintoandar.com.br

## Overview

**Absolute Cost Post-Contract (For Rent)** is the net cost of the **Onboarding**, **Ongoing**, and **Offboarding** phases for the For Rent business vertical, with explicit exclusions for bank transaction fees and Finance Operations benefit-center allocations.

The metric returns the **net liquid value** — costs and revenues offset each other according to the source sign convention (costs predominantly negative, credits/revenue offsets positive).

This metric differs from the total For Rent Operations cost (which sums all `Operations` lines for For Rent) and from unit-cost metrics (which divide a single `P&L Line 2` by a volume denominator).

Related metrics: [Absolute Cost Ops Total (For Rent)](./absolute_cost_ops_total_fr.md), [Onboarding Unit Cost (For Rent)](./onboarding_uc_fr.md), [Ongoing Unit Cost (For Rent)](./ongoing_uc_fr.md), [Offboarding Unit Cost (For Rent)](./offboarding_uc_fr.md).

**Exists exclusively for For Rent.**

## Related Domain Entities

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

**Included** (additions): rows with `bece_business = 'For Rent'` and `version = 'Actuals'` where `pl_line_2` IN (`Onboarding`, `Ongoing`, `Offboarding`).

**Excluded** (subtractions applied after the additions, not simply omitted rows):

- `pl_line_4 = 'Bank Transactions Fees'` — bank transaction fees allocated to For Rent Operations (typically under `Ongoing`)
- `pl_line_3 = 'Ongoing Team'` at `benefit_center_code` IN (`135R1X`, `135R2X`) — Finance Operations B allocations (`135R1X` = For Rent Cross, `135R2X` = Full Rental)

**Not part of this metric** (never included; there is no `bece_l2`, `pl_line_1`, or `reporting_group` filter in the canonical definition):

- `Operations Overhead`, `Operations Tax Credit`, and any other `P&L Line 2` outside the three Post-Contract phases
- Operations costs from other business verticals (`For Sale`, `Corporate`, etc.)
- Non-Operations P&L lines (`Sales`, `Marketing`, `G&A`, revenues, derived results)
- Unit-cost views (those use a single `P&L Line 2` and a volume denominator)

## Calculation

Summing only the three `pl_line_2` phases (`Onboarding`, `Ongoing`, `Offboarding`) for `bece_business = 'For Rent'` and `version = 'Actuals'` overstates the Post-Contract figure: it does not net out bank transaction fees and Finance Operations benefit-center allocations that are already embedded in those phase sums. The finance source implements this metric as **three additive sums minus three subtractive sums** on the target `YYYYMM` column. There is no `bece_l2`, `pl_line_1`, or `reporting_group` filter in the canonical definition.

```
Absolute Cost Post-Contract (For Rent)
  = SUM(Onboarding | For Rent | Actuals)
  + SUM(Ongoing   | For Rent | Actuals)
  + SUM(Offboarding | For Rent | Actuals)
  − SUM(Bank Transactions Fees | For Rent | Actuals)
  − SUM(Ongoing Team @ 135R2X | For Rent | Actuals)
  − SUM(Ongoing Team @ 135R1X | For Rent | Actuals)
```

Amounts are summed **as recorded** — do not apply `ABS()`. Subtractions use the same signed values; if the excluded rows are negative costs, subtracting them increases the net total.

### Excel reference (source layout)

Column mapping in `DB_financial_data`:

| Excel column | Field |
| ------------ | ----- |
| `E` | `BeCe Business` |
| `L` | `P&L Line 2` |
| `M` | `P&L Line 3` |
| `N` | `P&L Line 4` |
| `P` | `Benefit Center Code` |
| `R` | `Version` |
| `X` (example) | Target `YYYYMM` period column |

Equivalent `SUMIFS` pattern for month column `X`:

```
= SUMIFS(X, L, "Onboarding", R, "Actuals", E, "For Rent")
+ SUMIFS(X, L, "Ongoing",   R, "Actuals", E, "For Rent")
+ SUMIFS(X, L, "Offboarding", R, "Actuals", E, "For Rent")
− SUMIFS(X, N, "Bank Transactions Fees", R, "Actuals", E, "For Rent")
− SUMIFS(X, M, "Ongoing Team", R, "Actuals", E, "For Rent", P, "135R2X")
− SUMIFS(X, M, "Ongoing Team", R, "Actuals", E, "For Rent", P, "135R1X")
```

### Canonical Filter

Apply on `datalake_luigijr_ops_finance_clean.finance_revenue_cost_2025` or `finance_revenue_cost_2026` (see [table selection](../domain_entities/finance_revenue_cost.md#table-selection-by-year)).

**Base scope** (all six components):

```sql
bece_business = 'For Rent'
AND version = 'Actuals'
```

**Additions** — `pl_line_2` IN (`Onboarding`, `Ongoing`, `Offboarding`)

**Subtractions**:

| Component | Filter |
| --------- | ------ |
| Bank transaction fees | `pl_line_4 = 'Bank Transactions Fees'` |
| Finance Operations B (Full Rental) | `pl_line_3 = 'Ongoing Team'` AND `benefit_center_code = '135R2X'` |
| Finance Operations B (For Rent Cross) | `pl_line_3 = 'Ongoing Team'` AND `benefit_center_code = '135R1X'` |

Column names in the uploaded table are **lowercased**, **spaces replaced by underscores**, and **`&` removed** (e.g. `BeCe Business` → `bece_business`, `P&L Line 2` → `pl_line_2`, `Benefit Center Code` → `benefit_center_code`).

**Warning**: Do not apply `bece_l2 = 'Felipe Abreu'` — that is not part of the finance formula. Do not omit the three subtraction components; bank fees and Finance Operations allocations are explicitly netted out.

### Nuances

**Why subtractions exist**: `Bank Transactions Fees` and `Ongoing Team` rows at benefit centers `135R1X` / `135R2X` may already be included in the `Ongoing` (or broader phase) sums. The formula removes them explicitly to match the controllership view.

**Period selection**: Months are not a categorical column. Select the target month by reading the corresponding `YYYYMM` column (e.g. `"202603"` for March 2026) from the table for that year. Period column names are unaffected by the lower/underscore transform. To build a time series, unpivot the relevant `YYYYMM` columns — see the golden query below.

**Empty cells**: Treat empty period cells as missing, not as zero.

**Sign convention**: Sum raw amounts without `ABS()`. Apply subtractions as signed arithmetic on the same values.

**Type casting**: Period columns are stored as `varchar` after upload. Cast to numeric before aggregating: `TRY_CAST(REPLACE(f."<YYYYMM>", ',', '') AS DOUBLE)`.

| Parameter   | Description                                                                                                                      |
| :---- | :---- |
| `<YYYYMM>`  | Target month column name (e.g. `202603`). Query the table for the matching calendar year.                                        |

**Fallback**: If the requested `YYYYMM` column is empty for `version = 'Actuals'`, the metric is undefined for that period — do not fall back to a different `version` silently.

## Dos and Don'ts

**Do:**

- Sum `pl_line_2` IN (`Onboarding`, `Ongoing`, `Offboarding`) for `bece_business = 'For Rent'` and `version = 'Actuals'`
- Subtract `pl_line_4 = 'Bank Transactions Fees'` for the same base scope
- Subtract `pl_line_3 = 'Ongoing Team'` at `benefit_center_code` `135R1X` and `135R2X`
- Apply all six components with the same `version` and `YYYYMM` column
- Query `finance_revenue_cost_2025` or `finance_revenue_cost_2026` according to the target year
- Sum raw amounts — do **not** apply `ABS()`; the metric is net liquid, not absolute
- Use lowercased, underscore-separated column names as they appear post-upload

**Don't:**

- Filter `bece_l2` — not in the finance definition
- Filter `pl_line_1 = 'Operations'` as a hard requirement — the formula keys on `pl_line_2` phase names
- Omit the bank-fee or Finance Operations subtractions
- Include `Operations Overhead` or `Operations Tax Credit` (they are outside the three `pl_line_2` additions)
- Mix `version` values across components
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

**Always pair the target `YYYYMM` column with the matching `version`.** For the standard Actuals metric, use `version = 'Actuals'`. Replace `Actuals` with the matching label on **all six** components (three additive sums, three subtractive sums) consistently — never mix versions across components. Exact `version` labels may change between monthly refreshes — confirm available values before querying.

**Budget (Target)** — orçamento mensal do custo Pós-Contrato For Rent na tabela financeira.

- **Source table:** `datalake_luigijr_ops_finance_clean.finance_revenue_cost_2025` / `finance_revenue_cost_2026` (ver [table selection](../domain_entities/finance_revenue_cost.md#table-selection-by-year))
- **Filter key / metric name:** coluna `version` = `Budget <YYYY> - <MM>` (label varia por refresh); aplicar o mesmo canonical filter de Calculation (três somas aditivas menos três subtrativas) com `version` substituído nos seis componentes
- **Period grain:** mensal — coluna `YYYYMM` wide-format
- **Aliases / search terms:** orçamento, budget, target, custo Pós-Contrato
- **Caveat:** labels exatos podem mudar entre refreshes; nunca agregar across `version` values

**OKR** — meta de período (OKR100) na mesma tabela.

- **Source table:** `datalake_luigijr_ops_finance_clean.finance_revenue_cost_2025` / `finance_revenue_cost_2026`
- **Filter key / metric name:** coluna `version` = `OKR100 <YYYY> - <MM>` (label varia por refresh); aplicar o mesmo canonical filter de Calculation (três somas aditivas menos três subtrativas) com `version` substituído nos seis componentes
- **Period grain:** mensal — coluna `YYYYMM`
- **Aliases / search terms:** meta, OKR, OKR100
- **Caveat:** confirmar labels disponíveis antes de consultar; parear `YYYYMM` + `version`

## Golden Queries

Single-month Post-Contract cost (Actuals), written for March 2026.

```sql
SELECT
    -- Change every "202603" column reference to the target month (YYYYMM).
    SUM(CASE
        WHEN f.pl_line_2 IN ('Onboarding', 'Ongoing', 'Offboarding')
        THEN TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)
        WHEN f.pl_line_4 = 'Bank Transactions Fees'
        THEN -TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)
        WHEN f.pl_line_3 = 'Ongoing Team'
         AND f.benefit_center_code IN ('135R1X', '135R2X')
        THEN -TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)
        ELSE 0
    END) AS absolute_cost_post_contract_fr
-- Change the _2026 suffix to the calendar year of the month above (_2025 or _2026).
FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026 f
WHERE f.bece_business = 'For Rent'
  AND f.version = 'Actuals'
  AND TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE) IS NOT NULL
  AND (
        f.pl_line_2 IN ('Onboarding', 'Ongoing', 'Offboarding')
     OR f.pl_line_4 = 'Bank Transactions Fees'
     OR (f.pl_line_3 = 'Ongoing Team' AND f.benefit_center_code IN ('135R1X', '135R2X'))
  );
```

Equivalent decomposed form (matches the Excel `SUMIFS` structure), written for March 2026:

```sql
WITH base AS (
    SELECT TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE) AS amount, f.*
    FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026 f
    WHERE f.bece_business = 'For Rent'
      AND f.version = 'Actuals'
      AND TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE) IS NOT NULL
)
SELECT
    COALESCE(SUM(amount) FILTER (WHERE pl_line_2 = 'Onboarding'), 0)
  + COALESCE(SUM(amount) FILTER (WHERE pl_line_2 = 'Ongoing'), 0)
  + COALESCE(SUM(amount) FILTER (WHERE pl_line_2 = 'Offboarding'), 0)
  - COALESCE(SUM(amount) FILTER (WHERE pl_line_4 = 'Bank Transactions Fees'), 0)
  - COALESCE(SUM(amount) FILTER (
        WHERE pl_line_3 = 'Ongoing Team' AND benefit_center_code = '135R2X'
    ), 0)
  - COALESCE(SUM(amount) FILTER (
        WHERE pl_line_3 = 'Ongoing Team' AND benefit_center_code = '135R1X'
    ), 0) AS absolute_cost_post_contract_fr
FROM base;
```

Side-by-side comparison with total For Rent Operations cost for the same period (Actuals), written for March 2026:

```sql
SELECT
    -- Change every "202603" column reference to the target month (YYYYMM).
    SUM(TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)) FILTER (
        WHERE f.pl_line_1 = 'Operations'
    ) AS absolute_cost_ops_total_fr,
    SUM(CASE
        WHEN f.pl_line_2 IN ('Onboarding', 'Ongoing', 'Offboarding')
        THEN TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)
        WHEN f.pl_line_4 = 'Bank Transactions Fees'
        THEN -TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)
        WHEN f.pl_line_3 = 'Ongoing Team'
         AND f.benefit_center_code IN ('135R1X', '135R2X')
        THEN -TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE)
        ELSE 0
    END) AS absolute_cost_post_contract_fr
-- Change the _2026 suffix to the calendar year of the month above (_2025 or _2026).
FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026 f
WHERE f.bece_business = 'For Rent'
  AND f.version = 'Actuals'
  AND TRY_CAST(REPLACE(f."202603", ',', '') AS DOUBLE) IS NOT NULL;
```

To compare budget or OKR scenarios for the same month, change `version` and keep all other filters — never aggregate across versions in one pass.
