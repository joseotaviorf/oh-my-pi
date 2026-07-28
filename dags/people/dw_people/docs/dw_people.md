# People Public

**Metastore schema:** `dw_people`

> Public employee data covering identity, employment snapshots, and management hierarchy. The reference schema for headcount, tenure, and reporting structure in People Analytics.

## People Data Catalog

This schema is indexed in the [People Data Catalog](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/4635951235/People+Data+Catalog).

[Link to Catalog Row](#)

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

**✅ Employee Identity** : Public profile for every employee — name, work email, and internal identifier. The baseline reference for joining employee data across schemas.

**✅ Employment placement (current)** : One row per active employee with current organizational placement, tenure, hire date, and keys to business unit, job, cost center, and management hierarchy.

**✅ Management Hierarchy** : Current reporting chain for each active employee, from the CEO (L0) down to the individual contributor. Exposes the full chain of managers to enable filtering and grouping by any level of the reporting structure.

### Out of Scope

❌ **Organizational structure** : Business unit, cost center, and job definitions and attributes (name, hierarchy, validity periods) are not part of this schema. Use `dw_organization`.

### Who is included

* **Target Population:** Active QuintoAndar employees only (public Trino surface). Historical snapshots and terminated employees live in `dw_employee_details`.
* **Exclusions:** Internal test accounts used for system validation are excluded from all tables in this schema.

## Data Model and Tables

### Data Sources and System Context

* **PIN** : QuintoAndar's internal HR system (Oracle HCM). The single source of all employee identity, organizational placement, employment status, and management hierarchy data in this schema.

### About the data

* **Temporal coverage:** All tables in this schema are **current state only** for the **active workforce**. `dim_employee`, `dim_management_hierarchy`, and `fact_employees` are overwritten on each load and reflect the latest known placement for employees who are active today. For month-end history, terminations, and inactive assignments, use `dw_employee_details`.
* **Airflow DAG:** `bietlejuice.dw_people`
* **SLA:** D-1 available by 08:00 BRT

| Table | Grain | Links |
| :--- | :--- | :--- |
| `dim_employee` | **Current state only** · One row per active employee — latest identity | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_people.dim_employee,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_people/queries/dw/dim_employee.sql) |
| `fact_employees` | **Current state only** · One row per active employee — latest org placement | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_people.fact_employees,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_people/queries/dw/fact_employees.sql) |
| `dim_management_hierarchy` | **Current state only** · One row per active employee — latest reporting chain | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_people.dim_management_hierarchy,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_people/queries/dw/dim_management_hierarchy.sql) |

> **Note:** VPN connection is required to access DataHub.

**Main join identifiers:**

* `sk_employee` (Standard surrogate key for employees, FK to fact tables)
* `person_number` (Internal HR code, business key)

### Model decision (DBP-1804)

* **Public fact:** Keep the table name `fact_employees` and change the load to **one row per active employee** on the latest `assignment_snapshots` reference date (`is_current_for_employee` and `is_active`).
* **Restricted history:** Do not store month-end series or terminated employees in `dw_people`. Use `dw_employee_details.fact_assignment_snapshots` (and related dimensions) for historical headcount, exits, and internal People analytics.
* **Termination columns removed:** `dt_terminated` and `sk_terminated_date` are not part of the public fact; use `dw_employee_details` for exits.
* **No status flags on the fact:** `is_active` and `is_current` were removed; the table grain (active employees only) is enforced at load time — do not filter on removed columns.

## Core Features and Business Logic

### Domain logic and core concepts

* **fact_employees is current-state only** : One row per active employee on the latest reference date from `assignment_snapshots`. Terminated employees and month-end history are not stored here — use `dw_employee_details.fact_assignment_snapshots` for point-in-time or exit analysis.
* **All tables exclude terminated employees** : `dim_employee`, `fact_employees`, and `dim_management_hierarchy` load only people with `is_active = TRUE` on their current assignment in the enrich source. The fact does not expose `is_active` or `is_current` columns.
* **dim_employee and dim_management_hierarchy have no history** : Both dimensions are overwritten on each load. They cannot be used for time-travel on their own — use `dw_employee_details` for historical org structure.
* **Management Hierarchy Depth** : `dim_management_hierarchy` exposes the full reporting chain from the CEO (L0) down to each employee. Depth varies by position — some employees sit at L3, others at L8 or beyond. Levels deeper than the employee's actual position are NULL.
* **Surrogate Keys for Joins** : `fact_employees` connects to `dim_management_hierarchy` through `sk_manager_hierarchy` for the current hierarchy version. Historical hierarchy versions are in `dw_employee_details`.

### Business Assumptions

* **Cost Center vs. Other Attributes** : In `fact_employees`, the cost center reflects the version effective on each reference date — the organizational classification valid at that moment. Job, business unit, and management hierarchy version, however, follow the primary assignment snapshot for that same date and may represent a slightly different point in time than the cost center.

## Attention and Limitations

* **Public schema — not for history** : This schema is intended for public Trino consumption (replacing `org_chart`). Do not use it for terminated headcount, month-end archives, or termination reasons; use `dw_employee_details` instead.
* **dim_management_hierarchy is always current** : Join on `person_number` or `sk_manager_hierarchy` for today's reporting chain only.
* **dim_employee has no history** : Name and email always reflect the employee's latest values.

## How to Use

### Standard Join Pattern

When joining this schema's tables with other DW domains:

1. Always join on `sk_employee` (preferred) or `person_number`.
2. Reference `dw_people.dim_employee` for central employee attributes.

### Joining `dw_organization` (job, cost center, business unit)

**Question:** How do I attach job title, cost center, and business unit labels to the active workforce?

```sql
SELECT
    emp.person_number,
    emp.name,
    job.job_name,
    cc.cost_center_name,
    cc.chapter,
    cc.line,
    bu.business_unit_name
FROM
    dw_people.fact_employees AS fact
INNER JOIN dw_people.dim_employee AS emp
    ON fact.sk_employee = emp.sk_employee
LEFT JOIN dw_organization.dim_job AS job
    ON fact.sk_job = job.sk_job
LEFT JOIN dw_organization.dim_cost_center AS cc
    ON fact.sk_cost_center_version = cc.sk_cost_center_version
LEFT JOIN dw_organization.dim_business_unit AS bu
    ON fact.sk_business_unit = bu.sk_business_unit
```

For **Product & Tech team formation** (squad/line/chapter teams beyond cost-center attributes), use `datalake_gsheets_people_clean.team_formation_product_tech` today (sheet-maintained structure). A dedicated DW bridge table is planned under [DBP-1606](https://quintoandar.atlassian.net/browse/DBP-1606); until it ships, join on `person_number` or `assignment_number` per the reverse export `tech_team_formation` pattern.

### Analytical Snapshot (Management Chain for an Employee)

**Question:** Who are the managers from CEO down for a given employee?

```sql
SELECT
    emp.person_number,
    emp.name,
    hier.name_manager,
    hier.name_l0,
    hier.name_l1,
    hier.name_l2,
    hier.name_l3
FROM
    dw_people.dim_employee AS emp
INNER JOIN dw_people.dim_management_hierarchy AS hier
    ON emp.person_number = hier.person_number
WHERE
    emp.person_number = '<person_number>'
```

### Wide Join (Exploratory Query)

**Question:** How can I see all available employment data for active employees combined with their management chain?

```sql
SELECT
    fact.sk_employee,
    emp.name,
    emp.work_email,
    fact.dt_reference,
    fact.months_employee_tenure,
    hier.name_manager,
    hier.name_l0
FROM
    dw_people.fact_employees AS fact
LEFT JOIN dw_people.dim_employee AS emp
    ON fact.sk_employee = emp.sk_employee
LEFT JOIN dw_people.dim_management_hierarchy AS hier
    ON fact.sk_manager_hierarchy = hier.sk_manager_hierarchy
LIMIT 100
```

## Glossary

* **Validity Window** : A period of time during which specific attributes of an entity remain constant and true.
* **Snapshot** : A representation of data as it existed at a specific, frozen point in time, such as daily or monthly intervals.
* **Current State** : The latest, real-time version of the data representing only the active status of an entity without historical records.
* **SCD (Slowly Changing Dimension)** : A database design pattern used to store and manage both current and historical data over time.

## See Also

* **dw_employee_details** : Extended employee data including additional HR attributes not available in this schema. Use when a richer profile beyond public identity fields is required.
* **dw_organization** : Organizational reference tables for business units, cost centers, and job definitions — the structural dimensions used alongside employee snapshot data.
