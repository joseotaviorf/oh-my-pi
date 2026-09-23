# Compensation

**Metastore schema:** `dw_compensation`

> Historical and current compensation records (salary, salary range positioning, PLR bonus calculations, and salary table targets) for QuintoAndar people in Brazil, Portugal, the United States, and LATAM. Built from PIN HR data and the Performa cycle for analytics, audit, and PLR operation.

## People Data Catalog

This schema is indexed in the [People Data Catalog](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/5474320386/People+Data+Catalog).

[Link to Catalog Row](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/5474713621/Compensation)

## Contents

* [In Scope](#in-scope)
* [Data Model and Tables](#data-model-and-tables)
* [Core Features and Business Logic](#core-features-and-business-logic)
* [Attention and Limitations](#attention-and-limitations)
* [How to Use](#how-to-use)
* [Glossary](#glossary)
* [See Also](#see-also)

***

## In Scope

**✅ Salary history** : Approved salary records over time, with the adjustment amount, percentage variation, and each salary's ratio to the effective salary-table midpoint.

**✅ Job versions** : Every meaningful change to a job (band, salary table, salary range, PLR target) opens a new version; identical consecutive versions are merged so the timeline stays clean.

**✅ PLR / performance bonus** : Monthly building blocks of the annual PLR calculation: eligibility checks, IPA from Performa, corporate goals achievement, and target derivation for Brazil, Portugal, USA, and LATAM employees.

**✅ Salary table targets** : The most representative bonus targets (PLR, RVV, SOP, and similar) for each salary table and band over the last two years, useful as a reference for compensation reviews and audits.

**✅ Movement and reason catalog** : Unified labels for the action and reason that triggered each compensation change (promotion, lateral move, market adjustment, and so on), in English and Portuguese.

### Out of Scope

❌ **Employee identity, contact, and org chain** : Preferred name, work email, documents, daily workforce snapshots, and reporting hierarchy are in `dw_employee_details`.

❌ **Performance calibration inputs** : The raw Performa score and IPA used by PLR live in `dw_performance.fact_performance_calibrations`; this schema only consumes them.

❌ **Benefits** : Benefits data is not modeled at the DW layer yet; it lives only in upstream PIN sources.

### Who is included

* **Target Population:** Employees and contractors with an active employment relationship in PIN across Brazil, Portugal, the United States, and LATAM. Salary history covers all approved salary periods that intersect each person's active job history; PLR rows are produced for every assignment month within the PLR reference year.
* **Exclusions:** Pending hires not yet active in PIN, test and non-production accounts, and unapproved salary proposals. For PLR specifically, the calculation also excludes interns (core countries), Band 9+ (LATAM), people not admitted by the annual admission cutoff, and dismissals for just cause.

## Data Model and Tables

### Data Sources and System Context

* **PIN (HR master)** : QuintoAndar's HR system of record. Provides every employee, assignment, job, salary, movement, salary table, and PLR target used here. All compensation rows ultimately resolve to PIN identifiers (person, assignment, job). Performa calibration results (individual performance scores and IPA multipliers used for PLR) also flow into the warehouse through PIN.

### About the data

* **Temporal coverage:** Mixed: `dim_event_definition` is Current State; `dim_job` and `fact_compensations` carry full history as Validity Windows (SCD Type 2); `dim_plr_parameters` is one row per PLR reference year; `fact_plr_monthly` is a monthly snapshot per assignment per PLR year; `fact_salary_table_targets` is a daily snapshot rebuilt over a rolling two-year window.
* **Airflow DAG:** `bietlejuice.dw_compensation`
* **SLA:** D-1 available by 08:00 BRT.

| Table | Grain | Links |
| :--- | :--- | :--- |
| `dim_event_definition` | Current state: one record per unique movement (action + reason) combination | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_compensation.dim_event_definition,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_compensation/queries/dw/dim_event_definition.sql) |
| `dim_job` | Validity window: one record per job per period where its compensation attributes did not change | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_compensation.dim_job,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_compensation/queries/dw/dim_job.sql) |
| `fact_compensations` | Validity window: one record per approved salary per assignment per job version | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_compensation.fact_compensations,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_compensation/queries/dw/fact_compensations.sql) |
| `fact_salary_table_targets` | Daily snapshot: one record per salary table + band + reference date over the last two years | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_compensation.fact_salary_table_targets,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_compensation/queries/dw/fact_salary_table_targets.sql) |
| `dim_plr_parameters` | One record per PLR reference year | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_compensation.dim_plr_parameters,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_compensation/queries/dw/dim_plr_parameters.sql) |
| `fact_plr_monthly` | Monthly snapshot: one record per assignment per reference month per PLR reference year | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_compensation.fact_plr_monthly,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_compensation/queries/dw/fact_plr_monthly.sql) |

> **Note:** VPN connection is required to access DataHub.

**Main join identifiers:**

* `sk_employee` (Standard PK/FK to `dw_employee_details.dim_employee`)
* `person_number` (Business Key from PIN)
* `sk_contract` / `assignment_number` (Assignment-level join key for facts)
* `sk_job_version` (Versioned job link between `fact_compensations`, `fact_plr_monthly`, and `dim_job`)

## Core Features and Business Logic

### Domain logic and core concepts

* **Salary history with job context** : `fact_compensations` carries one row per approved salary per assignment per job version. A new row opens whenever the salary changes **or** the underlying job version changes, even if the salary itself stayed the same: this keeps the link to the correct band, salary table, and PLR target across time.
* **Salary midpoint ratio** : `salary_midpoint_ratio` is the salary amount divided by the midpoint of the effective salary table for the compensation record. A value of 1.000 means the salary equals the midpoint; values below 1.000 are below midpoint and values above 1.000 are above midpoint. The value is NULL when the salary or midpoint is missing, or when the midpoint is not positive.
* **Total cash** : `amount_total_cash` combines the annual salary with the PLR target read from person-level ICP entries in PIN. People with no PLR ICP entry have `NULL` PLR and `amount_total_cash` equals their annual salary.
* **PLR target sources** : PLR targets come from person-level ICP entries (`PLR - Salary Multiple` or legacy `Annual Target - PLR(*)`): never from `dim_job` as a fallback. `dim_job` keeps the salary-table-level target for reference and for the salary table targets snapshot.
* **PLR monthly engine** : `fact_plr_monthly` materializes the building blocks of the annual PLR (eligibility flags, IPA, corporate goals percentage, monthly target) on a monthly grain per assignment. The final monthly amount is `eligibility × IPA × corporate_goals × target`.
* **Eligibility rules (PLR)** : Admission by the annual cutoff; for hires in the reference year, 90+ days worked; no just-cause dismissal; no interns (core countries); no Band 9+ (LATAM). A month counts as worked when the person has at least 15 days inside the month, excluding unpaid leave; protected leaves (maternity, INSS, certain health) guarantee an IPA of at least 100%.
* **Job versions and consolidation** : `dim_job` opens a new version whenever any attribute (band, salary table, salary range, PLR target) changes; consecutive identical versions are merged into a single row so the history reflects business-meaningful changes only.
* **Salary table targets** : `fact_salary_table_targets` infers, per salary table and band on each reference date, the most representative target value (PLR, RVV, SOP, and so on) weighted by active headcount. Exception flags surface cases where individual jobs deviate from the dominant target.
* **Movement labels** : `dim_event_definition` unifies the action and reason of compensation movements (for example promotion, lateral move, market adjustment) and exposes them in English and Portuguese, with a flag for career-progression movements.
* **Tenure context** : `fact_compensations` carries tenure pre-computed in days (`days_tenure_in_company`, `days_tenure_in_position`, `days_tenure_in_band`) and in whole months (`months_tenure_in_company`, `months_tenure_in_position`, `months_tenure_in_band`). Position and band tenure reset on true rehire and on returning to the same role or band after a gap.

### Business Assumptions

* **PLR target follows the person, not the job** : Even when a salary table indicates a PLR target, the actual target used for PLR comes from the person's ICP entry; absence of an ICP entry means no PLR for that person.
* **Just-cause dismissals never get PLR** : Regardless of any other eligibility check.
* **Tenure preserves transfer continuity** : `days_tenure_in_company` and the monthly variants use the original hire date with transfer continuation; only true rehires reset the counter.

## Attention and Limitations

* **Current vs historical salary rows** : A far-future value in `dt_valid_to` indicates the currently active salary record, not a closed period. Use `is_current = TRUE` to retrieve the latest valid row per assignment. When analyzing historical periods, scope both `dt_valid_from` and `dt_valid_to` against the reference date you need to avoid counting the same salary multiple times.
* **Salary midpoint ratio interpretation** : The ratio is calculated against the salary-table midpoint effective during the compensation record, so a changed midpoint can change the ratio even when the salary is unchanged.
* **Range splits without a salary change** : A row in `fact_compensations` may exist purely because the job version changed (band, salary table, salary range, or PLR target). On these rows `amount_adjustment`, `pct_adjustment`, `is_promotion_movement`, and `sk_event_definition` are `NULL`: they are not real salary movements.
* **`amount_total_cash` excludes SOP, RVV, and exceptional bonus** : Only annual salary plus PLR target are folded into `amount_total_cash` today. Variable pay components remain available as targets in `dim_job` and `fact_salary_table_targets` but are not summed into the total cash figure.
* **Currency mismatch on PLR target** : When a PLR target is fixed (legacy `Annual Target - PLR`) and the salary is in a different currency, the calculation does not reconcile currencies. `plr_target_currency_code` is exposed so analysts can flag those cases.
* **Salary table targets snapshot** : `fact_salary_table_targets` is fully rebuilt on each run over a two-year rolling window. Older points in time are not preserved.
* **PLR corporate goals percentage** : `pct_corporate_goals` is only known after the year closes (available by 31/03 of the following year). Monthly rows may carry `NULL` corporate goals until then.
* **Promotion is reason-based, not action-based** : `is_promotion_movement` filters on the `CMP_PROM` reason code, not the broader `PROMOTION` action: the action also covers internal recruitment and lateral moves that should not count as promotions.

## How to Use

### Standard Join Pattern

When joining this schema's tables with other DW domains:

1. Always join on `sk_employee` (preferred) or `person_number`.
2. Reference `dw_employee_details.dim_employee` for central employee attributes.
3. Use `sk_job_version` to attach job context (`dim_job`) consistent with the salary row.
4. Anchor on `dt_valid_from` / `dt_valid_to` (or `sk_reference_month`) when joining history facts to date-aware dimensions.

### Current salary snapshot

**Question:** What is each employee's current salary, band, and how does it sit inside the pay range right now?

```sql
SELECT
    fact_compensations.sk_employee,
    fact_compensations.person_number,
    fact_compensations.assignment_number,
    fact_compensations.amount_salary,
    fact_compensations.amount_annual_salary,
    fact_compensations.amount_total_cash,
    fact_compensations.salary_midpoint_ratio,
    dim_job.band,
    dim_job.salary_table,
    dim_job.country,
    fact_compensations.dt_valid_from,
    fact_compensations.dt_valid_to
FROM
    dw_compensation.fact_compensations AS fact_compensations
INNER JOIN dw_compensation.dim_job AS dim_job
    ON dim_job.sk_job_version = fact_compensations.sk_job_version
WHERE
    fact_compensations.is_current = TRUE
    AND fact_compensations.is_salary_approved = TRUE
LIMIT 100
```

### Promotions in the last 12 months

**Question:** Who was promoted in the last twelve months, and by how much did the salary change?

```sql
SELECT
    fact_compensations.sk_employee,
    fact_compensations.person_number,
    fact_compensations.amount_salary,
    fact_compensations.amount_adjustment,
    fact_compensations.pct_adjustment,
    fact_compensations.dt_valid_from AS dt_promoted,
    dim_event_definition.action_name,
    dim_event_definition.reason_name
FROM
    dw_compensation.fact_compensations AS fact_compensations
INNER JOIN dw_compensation.dim_event_definition AS dim_event_definition
    ON dim_event_definition.sk_event_definition = fact_compensations.sk_event_definition
WHERE
    fact_compensations.is_promotion_movement = TRUE
    AND fact_compensations.dt_valid_from >= DATE_ADD(CURRENT_DATE(), -365)
ORDER BY
    fact_compensations.dt_valid_from DESC
LIMIT 100
```

### Monthly PLR build-up for a reference year

**Question:** For a given PLR year, how does each eligible person's monthly PLR break down across the year?

```sql
SELECT
    fact_plr_monthly.person_number,
    fact_plr_monthly.assignment_number,
    fact_plr_monthly.sk_reference_month,
    fact_plr_monthly.country,
    fact_plr_monthly.band,
    fact_plr_monthly.amount_salary,
    fact_plr_monthly.performa_score,
    fact_plr_monthly.multiplier_eligibility,
    fact_plr_monthly.multiplier_ipa,
    fact_plr_monthly.multiplier_corporate_goals,
    fact_plr_monthly.multiplier_target_plr,
    fact_plr_monthly.amount_plr_monthly
FROM
    dw_compensation.fact_plr_monthly AS fact_plr_monthly
INNER JOIN dw_compensation.dim_plr_parameters AS dim_plr_parameters
    ON dim_plr_parameters.sk_plr_parameters = fact_plr_monthly.sk_plr_parameters
WHERE
    dim_plr_parameters.reference_year = YEAR(CURRENT_DATE()) - 1
    AND fact_plr_monthly.multiplier_eligibility = 1
LIMIT 100
```

## Glossary

* **Validity Window** : A period of time during which specific attributes of an entity remain constant and true, represented by `dt_valid_from` / `dt_valid_to` pairs.
* **Snapshot** : A representation of data as it existed at a specific, frozen point in time, such as daily or monthly intervals.
* **Current State** : The latest, real time version of the data representing only the active status of an entity without historical records.
* **SCD (Slowly Changing Dimension)** : A database design pattern used to store and manage both current and historical data over time.
* **PLR (Profit and Results Sharing)** : Annual performance bonus paid to eligible employees, calculated from corporate goals achievement, individual performance (IPA), and a salary-derived target.
* **IPA (Individual Performance Adjustment)** : Multiplier derived from the Performa score that scales each person's PLR target up or down.
* **Salary midpoint ratio** : Unitless ratio of salary amount to the effective salary-table midpoint; 1.000 means the salary equals the midpoint.
* **Band** : Seniority and salary level (for example 5, 6, 7, Estag1) used as the primary grouping for pay range and targets.
* **Salary table** : Catalog of salary ranges (min, mid, max) by country and band that anchors compensation policy.

## See Also

* **PLR Calculation** : [PLR Calculation](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/4769087489/PLR+Calculation): operational page describing the annual PLR calculation end-to-end (problem statement, scope, data sources, milestones, references). Use it for the process view of how PLR is run each year on top of the building blocks materialized in `fact_plr_monthly`.
