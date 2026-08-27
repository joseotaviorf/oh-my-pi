# Employee Snapshots

**DAG:** `metric_people`

> The curated, governed One Big Table (OBT) for People Insights — one row per employee per month, combining workforce state, compensation, organizational structure, diversity & inclusion, and performance into a single flat view. Direct successor to the legacy *base_completa_hierarquia* (current state) and *base_fotografias* (monthly snapshots).

## People Data Catalog

This schema is indexed in the [People Data Catalog](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/4635951235/People+Data+Catalog).

[Link to Catalog Row](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/4635951235/People+Data+Catalog)

## Contents

* [In Scope](#in-scope)
* [Data Model and Tables](#data-model-and-tables)
* [Core Features and Business Logic](#core-features-and-business-logic)
* [Attention and Limitations](#attention-and-limitations)
* [How to Use](#how-to-use)
* [Glossary](#glossary)
* [See Also](#see-also)

---

## In Scope

**✅ Monthly employee snapshots** : One record per employee per month, capturing their full state at the end of each reporting period — active employees, employees who left during that month, and all their attributes as they stood at that exact point in time.

**✅ Current workforce state** : A daily-updated view of the workforce as of yesterday, equivalent to the former *base_completa_hierarquia* (filter: `is_current = TRUE`).

**✅ Compensation and job details** : Salary, band, job family, compa-ratio, variable pay target, and last raise details — already joined and ready to use without additional queries.

**✅ Organizational structure** : Full management chain (L0–L9), cost center, business unit, HRBP, and Codex attributes — resolved at the correct point in time for every row.

**✅ Diversity and inclusion** : Self-declared DE&I attributes including ethnicity, gender identity, sexual orientation, religion, and disability status — joined at the right snapshot date.

### Out of Scope

**❌ Day-level workforce history** : Daily granularity lives in `dw_employee_details.fact_assignment_snapshots`. This table provides only month-end and current-day snapshots.

**❌ Immutable frozen snapshots** : Past months can change when retroactive corrections arrive from the source system. For an immutable audit trail, this is not the right table.

**❌ Production reports and Google Sheets exports** : This table is intended for ad-hoc exploration and analysis. Dedicated metric tables and reverse reports handle structured production outputs.

### Who is included

* **Target Population:** All current and former employees with a valid HR assignment in the company, across all employment types and countries where the company operates.
* **Exclusions:** Test accounts and system-generated users without a real employment relationship are not included.

## Data Model and Tables

### Data Sources and System Context

* **Oracle HCM Cloud (PIN)** : The company's HR management platform and single source of truth for all data in this table — personal information, legal documents, org assignments, management hierarchies, compensation history, diversity declarations, and performance evaluations all originate here.

### About the data

* **Temporal coverage:** Monthly snapshots — one record per employee per month closing date (`dt_reference`). An additional "current" row (`is_current = TRUE`) reflects the latest state, refreshed daily.
* **Airflow DAG:** `bietlejuice.metric_people`
* **SLA:** D-1 available by 08:00 BRT

| Table | Grain | Links |
| :--- | :--- | :--- |
| `employee_snapshots` | Monthly snapshot: one record per employee per reference date | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.people.employee_snapshots,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/metric_people/queries/metric/employee_snapshots.sql) |

> **Note:** VPN connection is required to access DataHub.

**Main join identifiers:**

* `sk_employee` (Standard PK — stable identifier per employee across all snapshots)
* `person_number` (Business Key from Oracle HCM)
* `assignment_number` (Assignment-level key; employees with internal transfers may hold more than one)

## Core Features and Business Logic

### Domain logic and core concepts

* **Month-end snapshot** : Each row represents one employee's complete state at the last day of a given month. `dt_reference` marks the closing date. Filtering on a single `dt_reference` gives a consistent headcount with all attributes point-in-time resolved — no extra joins needed.
* **Current state row** : Every active employee also has a row where `is_current = TRUE`, representing their state as of yesterday. This is the governed replacement for the legacy *base_completa_hierarquia* pattern.
* **Legacy table equivalences** (fechamento = `dt_reference`) :
  * *base_completa_hierarquia* → `employee_snapshots WHERE is_current = TRUE AND is_primary_assignment_for_snapshot = TRUE`
  * *base_fotografias* → `employee_snapshots WHERE is_monthly_snapshot = TRUE AND is_primary_assignment_for_snapshot = TRUE`
* **Pre-resolved organizational context** : Cost center, management hierarchy (L0–L9), business unit, and HRBP are already joined and resolved for every row. Standard People analyses do not require additional joins to organizational DW schemas.
* **Access list columns** : Four `access_list_*` fields provide dash-delimited, deduplicated email strings for row-level access control in reporting tools, covering all combinations of employee, HRBP, and management chain visibility.

### Business Assumptions

* **Retroactive corrections are reflected** : Unlike *base_fotografias*, which preserved a frozen copy at publish time, this table reflects the best available view of history at every daily refresh. A correction applied in Oracle HCM today will propagate to all historical month-end rows on the next load.

## Attention and Limitations

* **Performance and talent fields always return NULL** : `talent_potential`, `talent_criticality`, `talent_readiness`, `talent_risk_of_loss`, and all `perf_*` columns are placeholders for a planned integration. Do not use them in any analysis — they will return NULL for every row.
* **Always filter to the canonical assignment** : Employees who transferred internally hold more than one `assignment_number`. Use `is_primary_assignment_for_snapshot = TRUE` to get exactly one row per employee per `dt_reference`. Omitting this filter inflates headcount.

## How to Use

### Standard Filter Pattern

For any headcount or people analysis, always start with these two filters:

```sql
SELECT
    es.name,
    es.status,
    es.job_name,
    es.cost_center_name,
    es.dt_reference                   AS snapshot_month
FROM
    people.employee_snapshots AS es
WHERE
    es.is_monthly_snapshot = TRUE
    AND es.is_primary_assignment_for_snapshot = TRUE
```

Replace `is_monthly_snapshot` with `is_current = TRUE` if you need today's workforce state instead of month-end history.

### Standard Join Pattern

When joining this table with other DW domains:

1. Always join on `sk_employee` (preferred) or `person_number`.
2. Reference `dw_people.dim_employee` for any identity attributes not already present on this table.

### Exploratory Query (Current Workforce Profile)

**Question:** What does the current active workforce look like — who is working, in what role, and with what compensation?

```sql
SELECT
    es.name,
    es.work_email,
    es.job_name,
    es.band,
    es.cost_center_name,
    es.manager_name,
    es.amount_salary,
    es.months_tenure_in_company,
    es.status
FROM
    people.employee_snapshots AS es
WHERE
    es.is_current = TRUE
    AND es.is_primary_assignment_for_snapshot = TRUE
    AND es.is_active = TRUE
ORDER BY
    es.name
LIMIT 100
```

### Analytical Query (People Voluntary Turnover — January 2026)

**Question:** What was the voluntary turnover rate for the People vertical in January 2026?

```sql
SELECT
    COUNT(DISTINCT CASE
        WHEN es.is_terminated = TRUE
             AND es.termination_category = '<voluntary_category_value>'
        THEN es.person_number
    END)                                                     AS voluntary_terminations,
    COUNT(DISTINCT es.person_number)                         AS total_in_snapshot,
    ROUND(
        COUNT(DISTINCT CASE
            WHEN es.is_terminated = TRUE
                 AND es.termination_category = '<voluntary_category_value>'
            THEN es.person_number
        END) * 100.0
        / NULLIF(COUNT(DISTINCT es.person_number), 0),
    2)                                                       AS voluntary_turnover_pct
FROM
    people.employee_snapshots AS es
WHERE
    es.is_monthly_snapshot = TRUE
    AND es.is_primary_assignment_for_snapshot = TRUE
    AND es.dt_reference = DATE '2026-01-31'
    AND es.vertical = 'People'
```

> **Tip:** The `termination_category` values are recorded in Portuguese as they arrive from Oracle HCM. Verify the exact string for voluntary terminations in your dataset before running in production.

## Glossary

* **Snapshot** : A frozen representation of the workforce at a specific point in time — here, the last day of each month.
* **Current State** : The latest available version of each employee's record, reflecting data as of yesterday. Access via `is_current = TRUE`.
* **OBT (One Big Table)** : A wide, pre-joined table that eliminates complex multi-schema joins by consolidating all relevant dimensions into a single flat structure. `employee_snapshots` is the People domain OBT.

## See Also

* **Discovery and Engineering Reference** : [Employee Snapshots — Discovery & Engineering Reference](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/5468979201/Employee+Snapshots+Discovery+Engineering+Reference) — internal engineering reference covering the motivation, scope decisions, legacy column mapping (*base_completa* / *base_fotografias*), column structure, open questions, and delivery plan for this table.
