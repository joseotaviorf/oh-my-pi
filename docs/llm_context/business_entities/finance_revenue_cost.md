# Finance Revenue and Cost

## Ownership

**Data Owner:**
- felipe.abreu@quintoandar.com.br

**Data Steward:**
- jacqueline.gomez@quintoandar.com.br
- livia.borges@quintoandar.com.br

## Overview

- **Objective:** Monthly financial amounts at granular **Benefit Center (BeCe)** level for **unit economics**, **absolute costs**, and **cross-dimensional P&L analysis** — dataset `DB_financial_data`, uploaded manually to the data environment (FP&A / controllership allocation).
- **Asset status / lifecycle:** One table per calendar year (`finance_revenue_cost_2025`, `finance_revenue_cost_2026`); refreshed monthly; dimension values, `Version` labels, and available `YYYYMM` columns may change between refreshes — do not rely on hardcoded counts or snapshots.
- **Structure:** Dimension columns + monthly amount columns named as `YYYYMM` (wide format — no `month` or `period` column); volume drivers for unit economics coexist in the same table as monetary rows (`pl_line_1` = `-`, driver name in `pl_line_4`).
- **Common metrics:** [Onboarding Unit Cost (For Rent)](../metric_entities/onboarding_uc_fr.md), [Ongoing Unit Cost (For Rent)](../metric_entities/ongoing_uc_fr.md), [Offboarding Unit Cost (For Rent)](../metric_entities/offboarding_uc_fr.md), [Absolute Cost Post-Contract (For Rent)](../metric_entities/absolute_cost_post_contract_fr.md), [Absolute Cost Ops Total (For Rent)](../metric_entities/absolute_cost_ops_total_fr.md).
- **Source systems:** FP&A / Controllership manual upload (inferido); refresh cadence and upstream system details should be confirmed with the Finance / Controllership team.

This document is the authoritative reference when querying, documenting metrics, or citing these tables as dependencies for financial analyses.

**Intended use cases:**

- **Unit economics** — decomposing revenue and cost into capacity (variable), overhead (fixed), and direct P&L lines to compute per-unit or per-segment economics.
- **Absolute costs** — aggregating payroll, discretionary spend, corporate costs, marketing, operations, and collection/guarantee expenses by business unit, product, brand, and cost center.
- **Cross-dimensional P&L analysis** — slicing financial performance by CFO ownership, business line, product, brand, reporting group, benefit center, and financial scenario (`Version`).

The data reflects operations across Brazil and Latin America (brands such as QuintoAndar business lines, Classifieds portals like Zonaprop, Inmuebles24, Urbania, Plusvalia, Adondevivir, Compre o Alquile, CRM product Tokko, and fintech products like QuintoCred and mortgage cross-sell).

**Dataset characteristics:**

| Property | Detail |
| -------- | ------ |
| **Derived P&L rows dominate** | Most rows represent calculated P&L results (EBIT, Net Income, EBITDA variants) rather than leaf-level cost/revenue lines |
| **Volume and monetary rows coexist** | Most rows hold monetary P&L amounts; volume drivers for unit economics appear as separate rows with `pl_line_1` = `-` and the driver name in `pl_line_4` |
| **No metadata columns** | No `updated_at`, `source_system`, `currency`, or `refresh_timestamp` fields |
| **Unit economics in one table** | Post-Contract UC numerators (`pl_line_2` under `Operations`) and denominators (`pl_line_4` volume rows) can both be read from this table — no join to external volume tables required |
| **Structure evolves over time** | Dimension values, `Version` labels, and available `YYYYMM` columns may change with monthly refreshes |

**Content origin (inferred):** `DB_financial_data` reflects an FP&A / controllership allocation that: (1) allocates P&L amounts to benefit centers using the BeCe hierarchy; (2) classifies costs into Capacity vs Overhead for unit economics reporting; (3) maps granular P&L lines to standardized Reporting Groups; (4) stores amounts in a wide-format monthly layout; (5) separates financial scenarios via the `Version` column (actuals, budget, forecast, OKR).

## Related Metric Entities

- [Onboarding Unit Cost (For Rent)](../metric_entities/onboarding_uc_fr.md)
- [Ongoing Unit Cost (For Rent)](../metric_entities/ongoing_uc_fr.md)
- [Offboarding Unit Cost (For Rent)](../metric_entities/offboarding_uc_fr.md)
- [Absolute Cost Post-Contract (For Rent)](../metric_entities/absolute_cost_post_contract_fr.md)
- [Absolute Cost Ops Total (For Rent)](../metric_entities/absolute_cost_ops_total_fr.md)

## Glossary and Synonyms

| Term | Meaning | Notes |
|------|---------|-------|
| **DB_financial_data** | Manual FP&A dataset name | Tables: `finance_revenue_cost_2025` / `_2026` |
| **BeCe / centro de benefício** | Benefit Center organizational taxonomy | Columns `bece_cfo_tag`, `bece_l1`–`l3`, `bece_business`, `bece_product`, `bece_brand` |
| **BeCe Business** | Business vertical | Uploaded as `bece_business` |
| **P&L Line 1** | Top-level P&L category | Uploaded as `pl_line_1` |
| **P&L Line 2** | Second-level P&L sub-category | Uploaded as `pl_line_2` |
| **P&L Line 4** | Granular line or volume driver label | Uploaded as `pl_line_4` |
| **Reporting Group** | Standardized financial taxonomy | Uploaded as `reporting_group`; see [Reporting Groups](#reporting-groups) |
| **Version** | Financial scenario | Uploaded as `version`; e.g. `Actuals`, `Budget <YYYY> - <MM>`, `OKR100 <YYYY> - <MM>` |
| **orçamento / budget** | Budget scenario rows | Filter `version` = `Budget …` |
| **custo de serviço** | Cost of service (Operations P&L) | e.g. Absolute Cost Ops Total (For Rent) |

### Reporting Groups

The `Reporting Group` column provides a standardized financial taxonomy used for financial consolidation and dashboards. Observed values include:

`#`, `3P SERVICES`, `ACQUISITION COSTS`, `ADS`, `ADVERTISING`, `AFFILIATES REVENUE SHARE`, `AFFILIATES SPEND`, `AGENTS EXPENSES`, `AGENTS REVENUE SHARE`, `APOIO ADM`, `AUDIOVISUAL`, `BAD DEBT`, `BANK TRANSACTIONS FEES`, `BRANDING EXPENSES`, `BROKERAGE`, `BROKERAGE BYPASS`, `BROKERAGE FINANCING`, `BROKERAGE SPEND`, `CASHBACK`, `COLLECTION AND INSPECTION SPEND`, `COLLECTIONS COSTS`, `COLLECTIONS EXPENSES`, `COLLECTIONS SERVICES`, `CONSORTIUM`, `CONTINGENCY`, `CORPORATE TAX`, `COURT FEES`, `CREDIT AND COLLECTION SPEND`, `CREDIT CARD PAYMENT`, `CREDIT EXPENSES`, `CREDIT EXPENSES AND TRANSACTION COSTS`, `DEPRECIATION & AMORTIZATION`, `EVENT SPEND`, `EVENTO EXTERNO`, `EVENTO INTERNO`, `EVENTS`, `EVENTS PARTNERS/ENGAGEMENT`, `EXCHANGE RATE FX`, `FACILITIES`, `FACILITIES DISCRETIONARY`, `FINANCIAL EXPENSES`, `FINANCIAL INCOME`, `GROSS SALES TAX`, `GROSS SALES TAX FLOAT`, `GROWTH DEMAND`, `GROWTH SUPPLY`, `GUARANTEE`, `HOSTING & SOFTWARE FOR ADMINISTRATIVE - 5A`, `HOSTING & SOFTWARE FOR OPERATIONS - 5A`, `HOSTING & SOFTWARE GENERAL`, `HOSTING & SOFTWARE UE`, `IFRS 17 AND 9`, `INSPECTIONS`, `INSURANCE COMMISSION`, `INSURANCE PREMIUM`, `KEY-DELIVERY`, `LATE PAYMENTS FEES`, `LOGISTICS`, `LONG-TERM RENTAL ANTICIPATION`, `LOSSES`, `MAINTENANCE`, `MANAGEMENT`, `MARKETING`, `MARKETING & SALES EXPENSES`, `MARKETING DEMAND`, `MASS MARKETING`, `MONTHLY RENTAL ANTICIPATION`, `MORTGAGE COMMISSION`, `NOTEBOOK LEASE`, `OTHER`, `OTHER DISCRETIONARY SPEND`, `OTHER TAXES`, `OTHER TAXES DISCRETIONARY`, `PARTNERS REVENUE SHARE`, `PARTNERSHIP COMMISSION`, `PAYROLL BENEFITS`, `PAYROLL BONUS`, `PAYROLL OUTSOURCING`, `PAYROLL SALARY`, `PAYROLL SALARY EXTRA`, `PAYROLL SEVERANCE`, `PAYROLL TAX`, `PAYROLL TAX 13º`, `PAYROLL TAX FÉRIAS`, `PRODUCT SPEND`, `RESERVE`, `REVENUE - FLOAT`, `REVENUE ANNULMENT PROVISION`, `SERVICE FEE`, `SETTLEMENTS AND JUDICIAL AGREEMENTS`, `SPACES RENTAL`, `STANDALONE GUARANTEES`, `STOCK OPTIONS`, `SUBSCRIPTION`, `TAX CREDIT`, `TAX OVER FINANCIAL EXPENSES`, `THIRD PARTY SERVICES`, `TRANSACTION AND COLLECTIONS COSTS`, `TRANSACTION COSTS`, `TRAVEL`, `TRAVEL EXPENSES`, `UPFRONT PAYMENTS`

> **Note:** `#` appears to be a placeholder or unclassified reporting group used for certain revenue lines (e.g. mortgage commission, revenue annulment provision).

## Tables

| You need… | Schema / table |
|-----------|----------------|
| Financial amounts / costs for 2025 months (`202501`–`202512`) | `datalake_luigijr_ops_finance_clean.finance_revenue_cost_2025` |
| Financial amounts / costs for 2026 months (`202601`–`202612`) | `datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026` |
| For Rent UC denominators (volume rows) | Same tables — see [Volume / activity rows](#volume--activity-rows) |
| Cross-year monthly series | Query each year table for its range and combine with `UNION ALL` |

### Table selection by year

| Target month (`YYYYMM`) | Table |
| ----------------------- | ----- |
| `202501` – `202512`     | `datalake_luigijr_ops_finance_clean.finance_revenue_cost_2025` |
| `202601` – `202612`     | `datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026` |

Both tables share the same schema and dimension conventions. For analyses spanning multiple years, query each table for its year range and combine with `UNION ALL`.

### Uploaded column naming

After manual upload to the data environment, dimension column headers are transformed: **spaces become underscores**, names are **lowercased**, and **`&` is removed**. Examples:

| Source header       | Uploaded column    |
| ------------------- | ------------------ |
| `BeCe Business`     | `bece_business`    |
| `P&L Line 1`        | `pl_line_1`        |
| `P&L Line 2`        | `pl_line_2`        |
| `BeCe L2`           | `bece_l2`          |
| `BeCe P&T Chapter`  | `bece_pt_chapter`  |
| `Version`           | `version`          |
| `Reporting Group`   | `reporting_group`  |

`YYYYMM` period columns (e.g. `202603`) are unchanged.

### Dimension columns

These columns define the row identity. Together with the selected `YYYYMM` column(s) and `version`, they form the **logical primary key** of the table.

| #   | Column                | Description                                                                                                                                                                                                                         |
| --- | --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `BeCe CFO Tag`        | Top-level CFO / executive owner of the benefit center hierarchy. Includes functional groupings such as `For Living` and `Other`, alongside executive assignments.                                                                  |
| 2   | `BeCe L1`             | Level 1 of the BeCe organizational hierarchy (senior leader or division).                                                                                                                                                           |
| 3   | `BeCe L2`             | Level 2 — mid-level leadership or sub-division.                                                                                                                                                                                     |
| 4   | `BeCe L3`             | Level 3 — team or squad-level owner (most granular org assignment).                                                                                                                                                                 |
| 5   | `BeCe Business`       | Business vertical. Values: `Classifieds & CRM`, `Corporate`, `For Living`, `For Rent`, `For Sale`, `Inmuebles24 Full`, `QCX`, `QuintoCred`.                                                                                         |
| 6   | `BeCe Product`        | Product or channel within the business. Examples: `1P`, `3P Demand`, `3P Supply`, `Full Rental`, `Brokerage Only`, `For Rent Cross`, `Classifieds`, `CRM`, `Mortgage Cross`, `Guarantees`, `Standalone`, `Internal Channel`.      |
| 7   | `BeCe Brand`          | Brand or market entity. Values: `Total Brands`, `Zonaprop`, `Inmuebles24`, `Urbania`, `Plusvalia`, `Adondevivir`, `Compre o Alquile`, `Tokko`, `Imovelweb`, `Allocations`, `Classifieds 2.0`, `Union`. `-` when not brand-specific. |
| 8   | `BeCe P&T Chapter`    | Product & Technology chapter. Values: `-` (not applicable / unassigned), `Cross Functional`, `Data`, `Design`, `Engineering`, `For Living`, `Infosec`, `Product Management`, `Product Marketing`, `Program Management`, `n.a`.     |
| 9   | `BeCe P&T Line`       | Product & Technology line. Values: `-`, `BSG`, `Bedrock`, `CMI`, `Classifieds`, `Conversational Experience`, `Credit Analytics`, `Fintech`, `For Living`, `For Rent`, `For Sale`, `General`, `Growth`, `INT`, `Mortgage`, `Partners (3P)`, `Partners (Agents)`, `Primitives`, `QCX`, `Single Station`, `Tech Platform`. |
| 10  | `P&L Line Type`       | Cost classification for unit economics. See [P&L Line Type semantics](#pl-line-type-semantics) below. Values: `-`, `Capacity`, `Overhead`.                                                                                          |
| 11  | `P&L Line 1`          | Top-level P&L category. Includes revenue lines (`Gross Revenues`, `Net Revenue`), cost lines (`Sales`, `Operations`, `Marketing`, `G&A`, `Product & Technology`), and derived results (`Gross Profit`, `EBIT`, `EBITDA Fully Loaded`, `Net Income`, etc.). |
| 12  | `P&L Line 2`          | Second-level P&L sub-category (e.g. `Brokerage`, `Advertising`, `Pre-Listing`, `Onboarding`, `Ongoing`, `Offboarding`, `Branding`, `Growth`).                                                                                       |
| 13  | `P&L Line 3`          | Third-level P&L detail (e.g. `Brokerage`, `Sales Overhead Team`, `Onboarding Payroll`, `Growth Demand`).                                                                                                                            |
| 14  | `P&L Line 4`          | Most granular P&L line item for **cost/revenue rows** (e.g. `Onboarding Payroll`, `Brokerage Financing`), or **volume / activity driver** for unit-economics denominators (e.g. `New Rentals (active)`, `Ended Rentals`). See [Volume / activity rows](#volume--activity-rows). |
| 15  | `Reporting Group`     | Standardized reporting bucket used for financial consolidation and dashboards. See [Reporting Groups](#reporting-groups). Cost aggregations typically exclude placeholder rows with `reporting_group = '-'`. Volume rows use `reporting_group = '-'` by design. |
| 16  | `Benefit Center Code` | Unique alphanumeric code identifying the cost/revenue center (e.g. `002R2X`, `426C3Z`, `490C3I`). Prefix patterns often encode org unit (e.g. `002` = General allocation, `426` = Sales, `490` = Sales overhead).                   |
| 17  | `Benefit Center Name` | Human-readable benefit center name (e.g. `General`, `Sales`, `Collections`, `Customer Support`, `Business Operations`). Some names include code prefixes.                                                                              |
| 18  | `Version`             | Financial scenario (e.g. `Actuals`, `Budget`, `Forecast`, `OKR`). Must be filtered when querying a specific scenario. Values and labels may change between refreshes. |

### Version column

The `Version` column separates financial scenarios within the same dimensional structure. Typical values include `Actuals`, `Budget`, `Forecast`, and `OKR` variants — exact labels may change between refreshes.

When computing a metric for a given month, always pair the target `YYYYMM` column with the appropriate `Version`. The same month column can hold different scenario types depending on which `Version` row is selected.

### Volume / activity rows

Starting with the **v2** dataset refresh, **transaction counts and rental volumes** used as unit-economics denominators are stored in the same table as monetary amounts. They are not in a separate volume table.

**Row pattern**

Volume rows are identified by a distinct dimensional signature:

| Dimension           | Volume rows                                                                 |
| ------------------- | --------------------------------------------------------------------------- |
| `P&L Line 1`        | `-`                                                                         |
| `P&L Line 2`        | `-`                                                                         |
| `P&L Line 3`        | `-`                                                                         |
| `P&L Line Type`     | `-`                                                                         |
| `Reporting Group`   | `-`                                                                         |
| `P&L Line 4`        | **Volume metric name** (driver label)                                       |
| `YYYYMM` columns    | **Count** for that month (not currency)                                     |

Costs and revenues continue to use populated `P&L Line 1`–`3` values; volume rows keep those fields as `-`.

**For Rent volume drivers (`bece_business = 'For Rent'`)**

When a driver is split by product, **sum across `bece_product`** to obtain the For Rent total.

Volume rows use `bece_l2 = 'Lucas Lima'`.

| `P&L Line 4`               | Role in unit economics                                      |
| -------------------------- | ----------------------------------------------------------- |
| `New Rentals (active)`     | Onboarding UC denominator                                   |
| `Ongoing Rentals (active)` | Month-end ongoing rental snapshot (reference / validation)  |
| `Ongoing (-) New Rentals`  | Ongoing UC denominator (pre-calculated: ongoing − new)      |
| `Ended Rentals`            | Offboarding UC denominator                                  |
| `Contracts Signed`         | Contract volume (not used in UC metrics)      |

UC cost numerators aggregate Onboarding / Ongoing / Offboarding Operations across **all** `bece_l2` owners within For Rent (no `bece_l2` filter). The absolute Post-Contract cost metric also has no `bece_l2` filter; it nets the same three `pl_line_2` phases against bank transaction fees and Finance Operations benefit-center allocations — see [Absolute Cost Post-Contract (For Rent)](../metric_entities/absolute_cost_post_contract_fr.md).

`Ongoing (-) New Rentals` is maintained per `bece_product`; at For Rent level, `SUM(Ongoing Rentals (active)) − SUM(New Rentals (active))` equals `SUM(Ongoing (-) New Rentals)` for the same `version` and month.

**Other business volume drivers**

| `BeCe Business` | `P&L Line 4` values (volume rows)                          | `BeCe L2`                         |
| --------------- | ----------------------------------------------------------- | --------------------------------- |
| `For Sale`      | `Closed Deals`, `Signed Deals (CCV)`, `Bypass Deals`, `Financed Deals` | `Lucas Lima`, `Bernardo Dorigo` |
| `QCX`           | `Closed Deals`                                              | `-`                               |

Volume rows are available across the same `Version` values as monetary rows (`Actuals`, `Budget …`, `Forecast …`, `OKR100 …`). Pair cost numerators and volume denominators on the **same `version` and `YYYYMM` column**.

## Key Metrics

Official For Rent post-contract metrics (exact calculation in linked metric entities):

- **Onboarding Unit Cost (For Rent):** Onboarding Operations cost ÷ `New Rentals (active)` — see [onboarding_uc_fr.md](../metric_entities/onboarding_uc_fr.md).
- **Ongoing Unit Cost (For Rent):** Ongoing Operations cost ÷ `Ongoing (-) New Rentals` — see [ongoing_uc_fr.md](../metric_entities/ongoing_uc_fr.md).
- **Offboarding Unit Cost (For Rent):** Offboarding Operations cost ÷ `Ended Rentals` — see [offboarding_uc_fr.md](../metric_entities/offboarding_uc_fr.md).
- **Absolute Cost Post-Contract (For Rent):** Net cost of `pl_line_2` IN (`Onboarding`, `Ongoing`, `Offboarding`), minus bank transaction fees and Finance Operations benefit-center allocations (`135R1X` / `135R2X`) — see [absolute_cost_post_contract_fr.md](../metric_entities/absolute_cost_post_contract_fr.md).
- **Absolute Cost Ops Total (For Rent):** Total net For Rent Operations cost — see [absolute_cost_ops_total_fr.md](../metric_entities/absolute_cost_ops_total_fr.md).

### Operations P&L Line 2 Breakdown

Relevant for post-contract cost metrics (unit economics and absolute operations cost):

| P&L Line 2              | Role in unit cost calculation                          |
| ----------------------- | ------------------------------------------------------ |
| `Operations Overhead`   | Absolute cost only — not unitarized                    |
| `Onboarding`            | Unit cost numerator (÷ New Rental)                     |
| `Ongoing`               | Unit cost numerator (÷ `Ongoing (-) New Rentals` volume) |
| `Offboarding`           | Unit cost numerator (÷ `Ended Rentals` volume)         |
| `Operations Tax Credit` | Tax credit offset within operations                    |

### Example Dependency Patterns

| Metric type                              | Typical filters                                                                                                            |
| ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| **Absolute payroll cost**                | `Reporting Group` IN (`PAYROLL SALARY`, `PAYROLL BENEFITS`, `PAYROLL TAX`, …), `P&L Line Type` IN (`Capacity`, `Overhead`) |
| **Absolute cost Ops Total (For Rent)**   | `bece_business` = `For Rent`, `pl_line_1` = `Operations`, `reporting_group` <> `'-'`, `version` = `Actuals` |
| **Absolute cost Post-Contract (For Rent)** | `bece_business` = `For Rent`, `version` = `Actuals`, `pl_line_2` IN (`Onboarding`, `Ongoing`, `Offboarding`) minus `pl_line_4` = `Bank Transactions Fees` and `pl_line_3` = `Ongoing Team` at `benefit_center_code` IN (`135R1X`, `135R2X`) — no `bece_l2`, `pl_line_1`, or `reporting_group` filter |
| **Gross revenue by product**             | `P&L Line 1` = `Gross Revenues`, `Reporting Group` = `BROKERAGE` / `ADVERTISING` / etc.                                    |
| **Marketing spend**                      | `P&L Line 1` = `Marketing`, sum `Branding` + `Growth` lines                                                                |
| **Unit economics (For Rent UC)** | Cost numerator: `bece_business` = `For Rent`, `pl_line_1` = `Operations`, `pl_line_2` = `Onboarding` / `Ongoing` / `Offboarding`, `reporting_group` <> `'-'` (no `bece_l2` filter). Volume denominator: `pl_line_4` = `New Rentals (active)` / `Ongoing (-) New Rentals` / `Ended Rentals`, `bece_l2` = `Lucas Lima`, `pl_line_1` = `-` |

## Relationships with other entities

This dataset is **standalone** (manual FP&A upload). For Rent unit-cost denominators are read from volume rows in the same table — **no join to external volume tables** is required.

### BeCe Organizational Hierarchy

```
BeCe CFO Tag
 └── BeCe L1
      └── BeCe L2
           └── BeCe L3
```

Cross-cut by:

```
BeCe Business → BeCe Product → BeCe Brand
                     ↓
              BeCe P&T Chapter → BeCe P&T Line  (optional; often unpopulated as `-`)
```

### P&L Hierarchy

```
P&L Line Type
 └── P&L Line 1
      └── P&L Line 2
           └── P&L Line 3
                └── P&L Line 4
                     ↕ (maps to)
                Reporting Group
```

### P&L Line Type Semantics

| `P&L Line Type` | Meaning                                                          | Typical contents                                                                                                              |
| --------------- | ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `-`             | Direct P&L lines not split into capacity/overhead                | Gross Revenues, Gross Sales Tax, Revenue Share, tax credits, brokerage, derived P&L results (EBIT, Net Income), and provisions |
| `Capacity`      | Variable / volume-driven costs (headcount and operational teams) | Sales support teams, onboarding/offboarding/ongoing operations payroll, collection & guarantee team costs                     |
| `Overhead`      | Fixed / indirect costs                                           | Sales overhead, marketing overhead, operations overhead — payroll, corporate costs, and discretionary spend                   |

### P&L Line 1 Breakdown

| P&L Line 1                     | Role                                                                      |
| ------------------------------ | ------------------------------------------------------------------------- |
| `Net Income`                   | Bottom-line result                                                        |
| `EBIT`                         | Operating profit                                                          |
| `EBITDA Fully Loaded`          | EBITDA including all loadings                                             |
| `Segment EBITDA`               | Segment-level EBITDA                                                      |
| `Sales`                        | Pre-listing, pre-contract, sales support, and sales overhead costs        |
| `Product & Technology`         | Engineering and product costs                                             |
| `G&A`                          | General & administrative costs                                            |
| `Marketing`                    | Branding and growth (demand/supply) costs                                 |
| `Operations`                   | Onboarding, ongoing, offboarding, and operations overhead                 |
| `Gross Revenues`               | Top-line revenue (brokerage, advertising, subscription, management, etc.) |
| `Gross Sales Tax`              | Sales tax and float-related tax                                           |
| `Revenue Share`                | Affiliate, agent, and partner revenue share                               |

## Dos and don'ts

**Temporal structure:** The monthly breakdown is **not** a categorical dimension — each month is a **separate `YYYYMM` column**. To obtain a monthly time series: (1) select the relevant `YYYYMM` column(s); (2) sum across those columns; (3) combine with the `Version` filter. A single row holds amounts for multiple months side by side. Each amount cell holds the **absolute monetary amount** for that month at the given dimension intersection. Currency is not explicitly encoded; amounts are consistent with **local operating currency** (predominantly BRL for Brazil operations, with LATAM classifieds revenue in local currencies).

**Do:**

- Pair the target `YYYYMM` column with the matching `version` (Actuals, Budget, OKR, Forecast).
- Cast period columns before aggregating: `TRY_CAST(REPLACE(f."<YYYYMM>", ',', '') AS DOUBLE)`.
- Sum raw amounts for net liquid cost metrics — do not apply `ABS()` unless the metric definition requires it.
- Apply metric-specific row exclusions when defining aggregation logic (e.g. exclude `Revenue Annulment Provision` from gross revenue totals when the metric definition requires it).
- Exclude placeholder cost rows: `reporting_group <> '-'` on monetary P&L rows.
- Use `reporting_group = '-'` on volume rows only (do not apply the cost-side `reporting_group` filter on denominators).
- Query `finance_revenue_cost_2025` or `_2026` according to the calendar year of the target `YYYYMM` column.
- When documenting a metric that depends on this dataset, include: (1) **filter dimensions** — which `BeCe Business`, `BeCe Product`, `P&L Line Type`, `P&L Line 1`–`4`, `Reporting Group`, and `Version` values are included; (2) **period selection** — which `YYYYMM` column(s) to read; (3) **aggregation logic** — sum, sign handling (`ABS` vs raw sum), exclusions; (4) **grain of output** — benefit-center, product, business, or company level.

**Don't:**

- Assume a `month` or `period` dimension column exists — months are wide `YYYYMM` columns.
- Treat empty period cells as zero — empty means missing.
- Mix `version` values in a single aggregation pass.
- Mix `Actuals` cost with budget/OKR volume (or vice versa) for unit-cost metrics.
- Join to external volume tables for For Rent UC denominators — they live in this table.

**Value sparsity:** Many period cells are **empty** or **zero** — empty should be treated as missing, not as zero. Non-zero values are a minority of all period cells; the table is structurally sparse.

**Sign convention:** **Revenues** (`Gross Revenues`) are predominantly **positive**; provisions and annulments appear as **negative** values. **Costs and expenses** are predominantly **negative**. **Tax credits** may appear as positive offsets. Sum raw amounts for **net liquid value**; use `ABS()` only when an explicit absolute-cost view is required by a metric definition.

**Period coverage asymmetry:** Different `Version` values may populate different subsets of `YYYYMM` columns. As the dataset is refreshed monthly, available period columns and populated ranges are expected to change.

**Organizational hierarchy drift:** `bece_l1` / `l2` / `l3` assignments can change between reporting cycles. Retrospective reconciliation against historical MBA reports may diverge if the hierarchy was updated after the original close.

## Golden Queries

Canonical pattern for a single-month Operations cost aggregation (For Rent Actuals). Because months are columns, not rows. Written for March 2026:

```sql
SELECT
  -- Change the "202603" column to the target month (YYYYMM).
  SUM(TRY_CAST(REPLACE("202603", ',', '') AS DOUBLE)) AS operations_cost
-- Change the _2026 suffix to the calendar year of the month above (_2025 or _2026).
FROM datalake_luigijr_ops_finance_clean.finance_revenue_cost_2026
WHERE bece_business = 'For Rent'
  AND pl_line_1 = 'Operations'
  AND reporting_group <> '-'
  AND version = 'Actuals'
```

Replace the `_2026` table suffix with `_2025` or `_2026` according to the target `YYYYMM` column.

Period columns are `varchar` after upload — cast before aggregating. Sum without `ABS()` for net liquid value.

Column names in queries must use the post-upload convention: `lower()`, spaces replaced by underscores, and `&` removed (e.g. `bece_business`, `pl_line_1`, `version`).

To build a time series, select multiple `YYYYMM` columns or unpivot the period columns into rows.

When documenting a metric that depends on this dataset, cite it as:

> **Source:** `datalake_luigijr_ops_finance_clean.finance_revenue_cost_2025` / `finance_revenue_cost_2026` (`DB_financial_data`) — see [finance_revenue_cost.md](./finance_revenue_cost.md)
