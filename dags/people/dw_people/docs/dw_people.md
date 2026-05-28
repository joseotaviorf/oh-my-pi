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

**✅ Employment Snapshots** : Month-by-month records of each employee's organizational placement, tenure, and employment status. Covers headcount, hire and termination dates, and references to business unit, job, cost center, and management hierarchy on each snapshot date.

**✅ Management Hierarchy** : Current reporting chain for every employee, from the CEO (L0) down to the individual contributor. Exposes the full chain of managers to enable filtering and grouping by any level of the reporting structure.

### Out of Scope

❌ **Organizational structure** : Business unit, cost center, and job definitions and attributes (name, hierarchy, validity periods) are not part of this schema. Use `dw_organization`.

### Who is included

* **Target Population:** All QuintoAndar employees with an active or historical employment record.
* **Exclusions:** Internal test accounts used for system validation are excluded from all tables in this schema.

## Data Model and Tables

### Data Sources and System Context

* **PIN** : QuintoAndar's internal HR system (Oracle HCM). The single source of all employee identity, organizational placement, employment status, and management hierarchy data in this schema.

### About the data

* **Temporal coverage:** Mixed across tables. `dim_employee` and `dim_management_hierarchy` are always **current state only** — they reflect the latest version of each employee's identity and reporting chain, with no historical records stored. `fact_employees` is **historical** — it keeps one row per employee per month-end reference date (full archive from the first snapshot onwards) plus one additional row for the most recent available day (`is_current = TRUE`).
* **Airflow DAG:** `bietlejuice.dw_people`
* **SLA:** D-1 available by 08:00 BRT

| Table | Grain | Links |
| :--- | :--- | :--- |
| `dim_employee` | **Current state only** · One row per employee — always latest identity | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_people.dim_employee,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_people/queries/dw/dim_employee.sql) |
| `fact_employees` | **Historical + current day** · One row per (employee, reference date) — full month-end archive plus `is_current` row | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_people.fact_employees,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_people/queries/dw/fact_employees.sql) |
| `dim_management_hierarchy` | **Current state only** · One row per employee — always latest reporting chain | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_people.dim_management_hierarchy,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_people/queries/dw/dim_management_hierarchy.sql) |

> **Note:** VPN connection is required to access DataHub.

**Main join identifiers:**

* `sk_employee` (Standard surrogate key for employees, FK to fact tables)
* `person_number` (Internal HR code, business key)

## Core Features and Business Logic

### Domain logic and core concepts

* **fact_employees is historical** : This table accumulates one row per employee for every month-end reference date since their first snapshot. It is the only table in this schema that keeps a time series. Use `dt_reference` to select a specific point in time, or omit it to work with the full history.
* **is_current marks the latest-day row** : In addition to the monthly archive, `fact_employees` includes one extra row per employee for the most recent available day. This row has `is_current = TRUE` and is not a month-end — it represents the latest known state before the next month closes. Use `is_current = TRUE` for the most up-to-date snapshot, and `is_active = TRUE` to further filter for currently employed individuals.
* **dim_employee and dim_management_hierarchy have no history** : Both dimension tables are overwritten on each load and always reflect the latest state. They cannot be used for time-travel or point-in-time analysis on their own — combine them with `fact_employees` filtered to a specific `dt_reference` for that purpose.
* **Management Hierarchy Depth** : `dim_management_hierarchy` exposes the full reporting chain from the CEO (L0) down to each employee. Depth varies by position — some employees sit at L3, others at L8 or beyond. Levels deeper than the employee's actual position are NULL.
* **Surrogate Keys for Historical Joins** : `fact_employees` connects to `dim_management_hierarchy` through `sk_manager_hierarchy`. This key represents the hierarchy version in effect on each reference date, enabling historical org structure analysis even though the dimension itself is always current.

### Business Assumptions

* **Cost Center vs. Other Attributes** : In `fact_employees`, the cost center reflects the version effective on each reference date — the organizational classification valid at that moment. Job, business unit, and management hierarchy version, however, follow the primary assignment snapshot for that same date and may represent a slightly different point in time than the cost center.

## Attention and Limitations

* **fact_employees has two overlapping rows near the current date** : Each employee has one row for every month-end plus one row for the most recent available day (`is_current = TRUE`). When the current date is close to a month-end, both the month-end row and the latest-day row exist for the same period and will appear together without a filter. Always add either `is_current = TRUE` (latest day only) or a specific `dt_reference` (point-in-time) to avoid counting employees twice.
* **dim_management_hierarchy is always current — history is in the fact** : The hierarchy dimension is overwritten on each run and only stores the latest reporting chain. If you need to know who managed someone on a past date, join `fact_employees` on `sk_manager_hierarchy` for the desired `dt_reference` and then use that key to look up the corresponding hierarchy version — not by joining directly to `dim_management_hierarchy`.
* **dim_employee has no history** : Name and email in `dim_employee` always reflect the employee's latest values. Changes over time (e.g. name updates) are not tracked in this schema.

## How to Use

### Standard Join Pattern

When joining this schema's tables with other DW domains:

1. Always join on `sk_employee` (preferred) or `person_number`.
2. Reference `dw_people.dim_employee` for central employee attributes.

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
    fact.tenure_months,
    fact.is_active,
    hier.name_manager,
    hier.name_l0
FROM
    dw_people.fact_employees AS fact
LEFT JOIN dw_people.dim_employee AS emp
    ON fact.sk_employee = emp.sk_employee
LEFT JOIN dw_people.dim_management_hierarchy AS hier
    ON fact.sk_manager_hierarchy = hier.sk_manager_hierarchy
WHERE
    fact.is_current = TRUE
    AND fact.is_active = TRUE
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
