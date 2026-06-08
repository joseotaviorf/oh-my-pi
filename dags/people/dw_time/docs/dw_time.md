# DW Time — Workforce time, absence, and attendance

**Metastore schema:** `dw_time`

> Describes vacation, time-offs, absences, hour-banks, attendance requests, hourly cost windows, and the reference dimensions that describe them—one integrated dataset.

## People Data Catalog

This schema is indexed in the [People Data Catalog](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/4635951235/People+Data+Catalog).

[Link to Catalog Row](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/4635951235/People+Data+Catalog)

## Contents

* [In Scope](#in-scope)
* [Data Model and Tables](#data-model-and-tables)
* [Core Features and Business Logic](#core-features-and-business-logic)
* [Attention and limitations](#attention-and-limitations)
* [How to use](#how-to-use)
* [Operational analytics patterns](#operational-analytics-approvals-and-exposure)
* [Glossary](#glossary)
* [Related Scopes](#related-scopes)

***

## In Scope

**✅ Vacation period balances** : Accrued, used, and remaining vacation days by employee assignment and vacation period from Oracle HCM context.

**✅ Absence events** : Absence events with status and approval-related attributes.

**✅ Hour-bank balances** : Hour-bank balance values per employee in minutes for each reference date.

**✅ Daily punches** : Punch-clock events (entry, break, exit, manual adjustment) per employee and calendar day, with creation channel, validation outcome, and adjustment audit attributes for current-month attendance follow-up.

**✅ Time requests** : Workforce requests spanning clock corrections, hour-bank adjustments, and categorized justification or time-off approvals, each with status, subtype, and interval-related attributes.

**✅ Hourly-rate windows** : Hourly pay windows paired with balance facts, used to estimate workforce time related costs.

### Who is included

* **Vacations and absence events**
  * Employees with vacation-period or absence-event data.

* **Hour banks and time tracking**
  * Employees enrolled in punch-driven time tracking and consolidated hour banks.
  * **Exclusions:** Policy exclusions such as managerial roles or high-band compensation groups; teammates who do not punch the clock—or who sit outside tracked Oitchau hour-bank coverage—normally show no hourly-bank or punch-driven attendance facts while vacation balances and PIN-backed absence submissions can still reflect them where applicable.

## Data Model and Tables

### Data Sources and System Context

* **Oitchau** : Workforce time and attendance product that holds requests, approvals, employee registrations, hourly-bank snapshots, salary-rate segments and configurations that describe how hour-bank totals are categorized.

* **Oracle HCM Cloud (PIN)** : Defines how vacation and absence programs operate; captures submissions and approval outcomes together with their balances.

### About the data

Detailed definitions for every column, metric, and flag are maintained in DataHub.

* **Airflow DAG:** `bietlejuice.dw_time`
* **SLA:** D-1 available by 08:00 BRT

| Table | Grain | Links |
| :--- | :--- | :--- |
| `dim_absence_type` | One row per absence type (current reference) | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_time.dim_absence_type,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_time/queries/dw/dim_absence_type.sql) |
| `dim_hours_bank_rule` | One row per hours-bank rule segment (current reference) | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_time.dim_hours_bank_rule,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_time/queries/dw/dim_hours_bank_rule.sql) |
| `dim_request` | One row per time request subtype (current reference) | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_time.dim_request,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_time/queries/dw/dim_request.sql) |
| `fact_absence_requests` | One row per PIN absence submission (Latest state for that submission) | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_time.fact_absence_requests,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_time/queries/dw/fact_absence_requests.sql) |
| `fact_employee_hourly_cost_windows` | One row per salary-rate segment per employee | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_time.fact_employee_hourly_cost_windows,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_time/queries/dw/fact_employee_hourly_cost_windows.sql) |
| `fact_employee_punches` | One row per punch-clock event (id_punch) for an employee | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_time.fact_employee_punches,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_time/queries/dw/fact_employee_punches.sql) |
| `fact_hours_bank_rule_totals` | One row per employee, date, and hourly-bank bucket, with closed/open balance status | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_time.fact_hours_bank_rule_totals,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_time/queries/dw/fact_hours_bank_rule_totals.sql) |
| `fact_time_attendance_requests` | One row per time request | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_time.fact_time_attendance_requests,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_time/queries/dw/fact_time_attendance_requests.sql) |
| `fact_vacation_balances` | One row per employee vacation period | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_time.fact_vacation_balances,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_time/queries/dw/fact_vacation_balances.sql) |

> **Note:** VPN connection is required to access DataHub.

**Documentation on GitHub:** This **`dw_time.md`** file is the only maintained narrative companion for **`dw_time`** in the repo—we removed legacy **`docs/data_model.md`** to avoid conflicting ER appendixes. Relationships and keys are summarized in **[How to use](#how-to-use)** (join patterns); column truth lives in **DataHub** and `metadata/`.

**Main join identifiers:**

* `sk_employee` : Preferred surrogate key.
* `person_number` : PIN-aligned business key for the employee.
* `assignment_number` : PIN-aligned business key for the assignment.

## Core Features and Business Logic

### Domain logic and core concepts

* **Time request line** : Each row is one time request, subtype keys point to the time catalog.

* **Time catalog** : Each row is one subtype from the Oitchau catalog regarding why a workforce-time request is opened, including labels plus policy-oriented defaults (paid subtype, hourly-bank treatment, weekly-rest discount, active versus retired menu items).

* **Hourly-bank balance line** : Each row is one employee on a calendar balance date within one hourly-bank bucket. The `is_closed` boolean separates official closed balances (`true`) from open current-period balances (`false`) that can still receive adjustments.

* **Punch event** : Each row is one punch-clock event (entry, break, exit, manual adjustment) registered for an employee on a calendar day with the channel where the punch was created, validation outcome, and creator audit attributes.

* **Hourly-rate window** : Each row is one salary-rate segment with start and end dates; Latest periods use an empty end date.

* **Balance cost overlay** : Indicative cost multiplies bank minutes by the hourly rate whose window covers the balance date.

* **Absence catalog line** : Each row is one absence category with descriptive label, ceiling on duration, paid-leave treatment, and performance-protection tagging for qualifying leave types under company policies.

* **Absence submission line** : Each row reflects one PIN absence submission with flags for approval, withdrawal, validity, and “in effect today” planning use.

* **Vacation period snapshot** : Each row summarizes one assignment vacation cycle with accrued days, absence-based usage, optional cash-out usage, residual balance, sequencing across periods, and simple indicators such as latest open period.

### Business Assumptions

* **Hourly-rate pairing rule** : When several ACTIVE salary-rate windows cover the same balance date for an employee, enrichment maps **exactly one** window per hourly-bank balance row—that is modeled join logic, not a reconciliation failure when overlaps exist.

## Attention and limitations

* **Product vs payroll** : Costs and rates shown here are estimates for analysis only, payroll and finance systems decide actual pay.

* **Hourly-bank rule labels** : Bucket keys occasionally fail to resolve to the rule catalog when formatting diverges; the fact still exposes the bucket key for investigation while the rule key may appear empty.

* **Vacation helper metrics** : Negative residual balances can appear when submissions exceed accrued amounts in upstream data; reconcile with upstream HR investigation when needed.

## How to use

### Standard Join Pattern

When joining this schema's tables with other People DW domains:

1. Prefer `sk_employee` when the fact provides it; otherwise join on `person_number`, and use `assignment_number` together with `person_number` when you need assignment-level grain on PIN facts.
2. Use `dw_people.dim_employee` for canonical People attributes and hierarchy.

### Wide Join (Exploratory Query)

**Question:** How do recent time requests look with subtype labels and employee keys?

```sql
SELECT
    req.sk_time_request,
    req.approval_status,
    req.approval_stage,
    req.ts_interval_started,
    req.ts_interval_ended,
    subtype.subtype_name,
    emp.sk_employee,
    emp.person_number
FROM
    dw_time.fact_time_attendance_requests AS req
LEFT JOIN
    dw_time.dim_request AS subtype
        ON req.sk_request = subtype.sk_request
LEFT JOIN
    dw_people.dim_employee AS emp
        ON req.sk_employee = emp.sk_employee
WHERE
    DATE(req.ts_interval_started) >= DATE_TRUNC('MONTH', CURRENT_DATE())
LIMIT 100
```

### Analytical Snapshot (Fact + All Related Dims)

**Question:** For last month's balance dates, how do minutes and indicative cost break down by rule segment labels?

```sql
SELECT
    bal.person_number,
    bal.dt_hours_bank_balanced,
    bal.minutes_balance_rule,
    bal.hourly_rate_applied,
    bal.estimated_balance_cost_amount,
    rules.segment_label,
    rules.group_name
FROM
    dw_time.fact_hours_bank_rule_totals AS bal
LEFT JOIN
    dw_time.dim_hours_bank_rule AS rules
        ON bal.sk_hours_bank_rule = rules.sk_hours_bank_rule
WHERE
    bal.is_closed = TRUE
    AND bal.dt_hours_bank_balanced BETWEEN ADD_MONTHS(CURRENT_DATE(), -1)
        AND DATE_SUB(CURRENT_DATE(), 1)
LIMIT 100
```

### Vacation balance exploration (Exploratory Query)

**Question:** How do accrued, used, and remaining vacation days look for the latest modeled vacation period per assignment?

```sql
SELECT
    vb.person_number,
    vb.assignment_number,
    vb.vacation_status,
    vb.days_accrued,
    vb.days_taken_total,
    vb.days_balance,
    vb.dt_vacation_period_started,
    vb.dt_vacation_period_ended,
    emp.sk_employee
FROM
    dw_time.fact_vacation_balances AS vb
LEFT JOIN
    dw_people.dim_employee AS emp
        ON vb.person_number = emp.person_number
WHERE
    vb.is_latest_period = TRUE
LIMIT 100
```

### Vacation absence requests (Exploratory Query)

**Question:** What do recent vacation-type absence submissions look like beside catalog labels and approval flags?

```sql
SELECT
    ar.sk_absence_request,
    ar.person_number,
    ar.assignment_number,
    ar.dt_absence_started,
    ar.dt_absence_ended,
    ar.days_requested,
    ar.is_approved,
    ar.is_effective,
    cat.absence_type,
    cat.is_paid_leave,
    emp.sk_employee
FROM
    dw_time.fact_absence_requests AS ar
LEFT JOIN
    dw_time.dim_absence_type AS cat
        ON ar.sk_absence_type = cat.sk_absence_type
LEFT JOIN
    dw_people.dim_employee AS emp
        ON ar.person_number = emp.person_number
WHERE
    (
        LOWER(cat.absence_type) LIKE '%vacation%'
        OR LOWER(cat.absence_type) LIKE '%ferias%'
        OR LOWER(cat.absence_type) LIKE '%férias%'
    )
    AND ar.dt_absence_started >= ADD_MONTHS(CURRENT_DATE(), -3)
LIMIT 100
```

### Daily punch-clock snapshot (Exploratory Query)

**Question:** How many punches did each employee register today and yesterday, including a flag for manual adjustments?

```sql
SELECT
    fp.person_number,
    fp.dt_punched,
    COUNT(DISTINCT fp.id_punch) AS punches_count,
    MIN(fp.ts_punched) AS ts_first_punch,
    MAX(fp.ts_punched) AS ts_last_punch,
    SUM(
        CASE
            WHEN fp.is_manual_adjustment THEN 1
            ELSE 0
        END
    ) AS manual_adjustments_count,
    emp.sk_employee
FROM
    dw_time.fact_employee_punches AS fp
LEFT JOIN
    dw_people.dim_employee AS emp
        ON fp.sk_employee = emp.sk_employee
WHERE
    fp.dt_punched BETWEEN DATE_SUB(CURRENT_DATE(), 1)
        AND CURRENT_DATE()
GROUP BY
    fp.person_number,
    fp.dt_punched,
    emp.sk_employee
ORDER BY
    fp.dt_punched DESC,
    punches_count DESC
LIMIT 100
```

### Operational analytics — approvals and exposure

The snippets below anchor on **`dw_time.fact_time_attendance_requests`** and joins to **`dw_organization`**, **`dw_people.fact_employees`** (month-end snapshot keyed to the request interval month), **`dim_management_hierarchy`**, and **`fact_employee_hourly_cost_windows`**. Interpretations are exploratory; payroll and product systems remain authoritative where they disagree.

Where the text says **payroll cutoff**, replace placeholder dates (`2099-12-31`) with the official cutoff for the month under analysis, or drive the cutoff from a governed payroll-calendar table instead of literals.

---

#### Volume — pending items (warehouse view)

**Question:** What is the total volume of manager approval pendencies for a recent window (warehouse refresh), and how does it compare to all requests in the same window?

**Pattern:** True real-time counts may come from the time product API or Looker Studio; the warehouse reflects the latest daily load.

```sql
WITH request_window AS (
    SELECT
        attendance_request.sk_time_request,
        attendance_request.approval_status,
        attendance_request.ts_updated
    FROM
        dw_time.fact_time_attendance_requests AS attendance_request
    WHERE
        TO_DATE(attendance_request.ts_updated) >= DATE_SUB(CURRENT_DATE(), 35)
)
SELECT
    COUNT(DISTINCT request_window.sk_time_request) AS total_request_count,
    COUNT(
        DISTINCT CASE
            WHEN LOWER(TRIM(request_window.approval_status)) = 'pending'
                THEN request_window.sk_time_request
        END
    ) AS pending_request_count
FROM
    request_window
```

#### Volume — share of pendencies by management and cost center

**Question:** What percentage of requests in the calendar month are pending, broken down by direct manager and cost center?

```sql
WITH monthly_requests AS (
    SELECT
        attendance_request.sk_time_request,
        attendance_request.sk_employee,
        attendance_request.person_number,
        attendance_request.approval_status,
        LAST_DAY(TO_DATE(attendance_request.ts_interval_started)) AS dt_month_end
    FROM
        dw_time.fact_time_attendance_requests AS attendance_request
    WHERE
        DATE_TRUNC('MONTH', attendance_request.ts_interval_started) = DATE_TRUNC('MONTH', CURRENT_DATE())
),
requests_with_org AS (
    SELECT
        monthly_requests.sk_time_request,
        monthly_requests.approval_status,
        hierarchy.name_manager,
        hierarchy.email_manager,
        cost_center.cost_center_name,
        cost_center.vertical
    FROM
        monthly_requests
    INNER JOIN
        dw_people.fact_employees AS employee_snapshot
            ON employee_snapshot.sk_employee = monthly_requests.sk_employee
            AND employee_snapshot.dt_reference = monthly_requests.dt_month_end
    INNER JOIN
        dw_organization.dim_cost_center AS cost_center
            ON cost_center.sk_cost_center_version = employee_snapshot.sk_cost_center_version
    LEFT JOIN
        dw_people.dim_management_hierarchy AS hierarchy
            ON hierarchy.person_number = monthly_requests.person_number
)
SELECT
    requests_with_org.name_manager,
    requests_with_org.email_manager,
    requests_with_org.cost_center_name,
    requests_with_org.vertical,
    COUNT(DISTINCT requests_with_org.sk_time_request) AS request_count,
    COUNT(
        DISTINCT CASE
            WHEN LOWER(TRIM(requests_with_org.approval_status)) = 'pending'
                THEN requests_with_org.sk_time_request
        END
    ) AS pending_request_count,
    ROUND(
        100.0 * COUNT(
            DISTINCT CASE
                WHEN LOWER(TRIM(requests_with_org.approval_status)) = 'pending'
                    THEN requests_with_org.sk_time_request
            END
        ) / NULLIF(COUNT(DISTINCT requests_with_org.sk_time_request), 0),
        2
    ) AS pending_share_percent
FROM
    requests_with_org
GROUP BY
    requests_with_org.name_manager,
    requests_with_org.email_manager,
    requests_with_org.cost_center_name,
    requests_with_org.vertical
```

#### Volume — distribution by approval status and request family

**Question:** How are requests (including abonos and manual-mark-style flows) distributed across pending, approved, declined, and ignored?

**Pattern:** Map **`ignored`** to the business label *Inválido / ignorado* only if your HR glossary agrees; otherwise treat **`ignored`** as its own category.

```sql
SELECT
    LOWER(TRIM(attendance_request.approval_status)) AS approval_status_normalized,
    attendance_request.request_type,
    request_dimension.subtype_name,
    COUNT(DISTINCT attendance_request.sk_time_request) AS request_count
FROM
    dw_time.fact_time_attendance_requests AS attendance_request
LEFT JOIN
    dw_time.dim_request AS request_dimension
        ON request_dimension.sk_request = attendance_request.sk_request
WHERE
    DATE_TRUNC('MONTH', attendance_request.ts_interval_started) = DATE_TRUNC('MONTH', CURRENT_DATE())
GROUP BY
    LOWER(TRIM(attendance_request.approval_status)),
    attendance_request.request_type,
    request_dimension.subtype_name
ORDER BY
    request_count DESC
```

#### Volume — countdown to payroll close

**Question:** How much time remains until payroll close?

**Pattern:** This is **not stored in `dw_time`**. Implement a parameter or a small calendar table in Looker Studio (or a governed reference table) with **cutoff timestamp per month and legal entity**, then compute `cutoff_ts - current_timestamp()` in the presentation layer. Join warehouse facts on the calendar month of `ts_interval_started` when aligning pendencies to the same close month.

#### Management — top backlog after payroll close

**Question:** Which managers, verticals, and cost centers have the largest open backlog after the close deadline?

**Pattern:** Replace `DATE '2099-12-31'` with your official cutoff date for the month under analysis (or join a payroll calendar table).

```sql
WITH payroll_cutoff AS (
    SELECT DATE('2099-12-31') AS dt_payroll_close
),
open_after_close AS (
    SELECT
        attendance_request.sk_time_request,
        attendance_request.person_number,
        attendance_request.sk_employee,
        attendance_request.approval_status,
        LAST_DAY(TO_DATE(attendance_request.ts_interval_started)) AS dt_month_end
    FROM
        dw_time.fact_time_attendance_requests AS attendance_request
    CROSS JOIN
        payroll_cutoff AS cutoff_rule
    WHERE
        LOWER(TRIM(attendance_request.approval_status)) = 'pending'
        AND TO_DATE(attendance_request.ts_updated) > cutoff_rule.dt_payroll_close
)
SELECT
    hierarchy.name_manager,
    cost_center.vertical,
    cost_center.cost_center_name,
    COUNT(DISTINCT open_after_close.sk_time_request) AS open_request_count_after_close
FROM
    open_after_close
INNER JOIN
    dw_people.fact_employees AS employee_snapshot
        ON employee_snapshot.sk_employee = open_after_close.sk_employee
        AND employee_snapshot.dt_reference = open_after_close.dt_month_end
INNER JOIN
    dw_organization.dim_cost_center AS cost_center
        ON cost_center.sk_cost_center_version = employee_snapshot.sk_cost_center_version
LEFT JOIN
    dw_people.dim_management_hierarchy AS hierarchy
        ON hierarchy.person_number = open_after_close.person_number
GROUP BY
    hierarchy.name_manager,
    cost_center.vertical,
    cost_center.cost_center_name
ORDER BY
    open_request_count_after_close DESC
```

#### Management — agility by vertical (time to decision)

**Question:** Which verticals show the slowest approval behaviour?

**Pattern:** Median or average hours from **`ts_created`** to **`ts_updated`** for rows that reached **approved** or **declined**; segment by **`dim_cost_center.vertical`** on the request-month snapshot (`fact_employees` keyed to **`LAST_DAY`** of the interval started month).

```sql
WITH decided_requests AS (
    SELECT
        attendance_request.sk_time_request,
        attendance_request.sk_employee,
        attendance_request.person_number,
        attendance_request.ts_created,
        attendance_request.ts_updated,
        LAST_DAY(TO_DATE(attendance_request.ts_interval_started)) AS dt_month_end
    FROM
        dw_time.fact_time_attendance_requests AS attendance_request
    WHERE
        DATE_TRUNC('MONTH', attendance_request.ts_interval_started) = DATE_TRUNC('MONTH', CURRENT_DATE())
        AND LOWER(TRIM(attendance_request.approval_status)) IN ('approved', 'declined')
)
SELECT
    cost_center.vertical,
    ROUND(
        AVG(
            (
                UNIX_TIMESTAMP(decided_requests.ts_updated)
                - UNIX_TIMESTAMP(decided_requests.ts_created)
            ) / 3600.0
        ),
        2
    ) AS avg_hours_created_to_decision
FROM
    decided_requests
INNER JOIN
    dw_people.fact_employees AS employee_snapshot
        ON employee_snapshot.sk_employee = decided_requests.sk_employee
        AND employee_snapshot.dt_reference = decided_requests.dt_month_end
INNER JOIN
    dw_organization.dim_cost_center AS cost_center
        ON cost_center.sk_cost_center_version = employee_snapshot.sk_cost_center_version
GROUP BY
    cost_center.vertical
ORDER BY
    avg_hours_created_to_decision DESC
```

#### Management — correlation with job and business unit

**Question:** Is there a concentration of pending requests by job or business unit?

```sql
WITH monthly_pending AS (
    SELECT
        attendance_request.sk_time_request,
        attendance_request.sk_employee,
        attendance_request.approval_status,
        LAST_DAY(TO_DATE(attendance_request.ts_interval_started)) AS dt_month_end
    FROM
        dw_time.fact_time_attendance_requests AS attendance_request
    WHERE
        DATE_TRUNC('MONTH', attendance_request.ts_interval_started) = DATE_TRUNC('MONTH', CURRENT_DATE())
        AND LOWER(TRIM(attendance_request.approval_status)) = 'pending'
)
SELECT
    job_dimension.job_name,
    business_unit.business_unit_name,
    COUNT(DISTINCT monthly_pending.sk_time_request) AS pending_request_count
FROM
    monthly_pending
INNER JOIN
    dw_people.fact_employees AS employee_snapshot
        ON employee_snapshot.sk_employee = monthly_pending.sk_employee
        AND employee_snapshot.dt_reference = monthly_pending.dt_month_end
LEFT JOIN
    dw_organization.dim_job AS job_dimension
        ON job_dimension.sk_job = employee_snapshot.sk_job
LEFT JOIN
    dw_organization.dim_business_unit AS business_unit
        ON business_unit.sk_business_unit = employee_snapshot.sk_business_unit
GROUP BY
    job_dimension.job_name,
    business_unit.business_unit_name
ORDER BY
    pending_request_count DESC
```

#### Finance — rough exposure for pending requests (hours × rate)

**Question:** What is the estimated financial exposure from unresolved lines where payroll-relevant flags apply?

**Pattern:** Uses hourly-rate windows and booked duration from integration; payroll remains authoritative. Elapsed hours use **`UNIX_TIMESTAMP`** differences (Databricks / Spark SQL).

```sql
WITH pending_requests AS (
    SELECT
        attendance_request.sk_time_request,
        attendance_request.sk_employee,
        attendance_request.ts_interval_started,
        attendance_request.ts_interval_ended,
        attendance_request.approval_status
    FROM
        dw_time.fact_time_attendance_requests AS attendance_request
    INNER JOIN
        dw_time.dim_request AS request_dimension
            ON request_dimension.sk_request = attendance_request.sk_request
    WHERE
        LOWER(TRIM(attendance_request.approval_status)) = 'pending'
        AND attendance_request.ts_interval_started IS NOT NULL
        AND attendance_request.ts_interval_ended IS NOT NULL
        AND (
            request_dimension.is_discount_dsr = TRUE
            OR attendance_request.is_paid_request = TRUE
        )
),
pending_with_rate_ranked AS (
    SELECT
        pending_requests.sk_time_request,
        cost_window.hourly_rate_amount,
        GREATEST(
            (
                UNIX_TIMESTAMP(pending_requests.ts_interval_ended)
                - UNIX_TIMESTAMP(pending_requests.ts_interval_started)
            ) / 3600.0,
            0.0
        ) AS booked_hours,
        ROW_NUMBER() OVER (
            PARTITION BY
                pending_requests.sk_time_request
            ORDER BY
                cost_window.dt_hourly_cost_segment_started DESC NULLS LAST
        ) AS rate_rank
    FROM
        pending_requests
    LEFT JOIN
        dw_time.fact_employee_hourly_cost_windows AS cost_window
            ON cost_window.sk_employee = pending_requests.sk_employee
            AND TO_DATE(pending_requests.ts_interval_started) >= cost_window.dt_hourly_cost_segment_started
            AND (
                cost_window.dt_hourly_cost_segment_ended IS NULL
                OR TO_DATE(pending_requests.ts_interval_started) <= cost_window.dt_hourly_cost_segment_ended
            )
),
pending_with_rate AS (
    SELECT
        pending_with_rate_ranked.sk_time_request,
        pending_with_rate_ranked.hourly_rate_amount,
        pending_with_rate_ranked.booked_hours
    FROM
        pending_with_rate_ranked
    WHERE
        pending_with_rate_ranked.rate_rank = 1
)
SELECT
    ROUND(
        SUM(booked_hours * COALESCE(pending_with_rate.hourly_rate_amount, 0)),
        2
    ) AS estimated_exposure_amount
FROM
    pending_with_rate
```

#### Finance — confirmed backlog after close

**Question:** What is the confirmed impact bucket: pendencies still pending after the payroll close instant?

**Pattern:** Same **`payroll_cutoff`** substitution as above; alternatively restrict the financial-pattern query with **`ts_updated > cutoff_ts`**.

```sql
WITH payroll_cutoff AS (
    SELECT TIMESTAMP('2099-12-31 23:59:59') AS ts_payroll_close
)
SELECT
    COUNT(DISTINCT attendance_request.sk_time_request) AS pending_request_count_after_close
FROM
    dw_time.fact_time_attendance_requests AS attendance_request
CROSS JOIN
    payroll_cutoff AS cutoff_rule
WHERE
    LOWER(TRIM(attendance_request.approval_status)) = 'pending'
    AND attendance_request.ts_updated > cutoff_rule.ts_payroll_close
```

#### Finance — HR rework estimate

**Question:** What rework effort should HR operations plan for corrections linked to approval delays?

**Pattern:** The warehouse does not store ticket minutes. Typical approach: **`pending_request_count_after_close * assumed_minutes_per_case`**, with **`assumed_minutes_per_case`** owned by HR as a parameter in Looker Studio. Combine with the count examples in **Finance — confirmed backlog after close**.

#### Behaviour — managers with pendencies in three consecutive months

**Question:** Which managers appear with open pendencies in three consecutive calendar months (**direct managers**, by **`person_number_manager`**)?

```sql
WITH monthly_manager_pending AS (
    SELECT
        DATE_TRUNC('MONTH', attendance_request.ts_interval_started) AS dt_month,
        hierarchy.person_number_manager AS person_number_manager,
        COUNT(DISTINCT attendance_request.sk_time_request) AS pending_request_count
    FROM
        dw_time.fact_time_attendance_requests AS attendance_request
    INNER JOIN
        dw_people.dim_management_hierarchy AS hierarchy
            ON hierarchy.person_number = attendance_request.person_number
    WHERE
        LOWER(TRIM(attendance_request.approval_status)) = 'pending'
    GROUP BY
        DATE_TRUNC('MONTH', attendance_request.ts_interval_started),
        hierarchy.person_number_manager
),
manager_month_streak AS (
    SELECT
        monthly_manager_pending.person_number_manager,
        monthly_manager_pending.dt_month,
        LAG(monthly_manager_pending.dt_month, 1) OVER (
            PARTITION BY
                monthly_manager_pending.person_number_manager
            ORDER BY
                monthly_manager_pending.dt_month
        ) AS dt_prev_month,
        LAG(monthly_manager_pending.dt_month, 2) OVER (
            PARTITION BY
                monthly_manager_pending.person_number_manager
            ORDER BY
                monthly_manager_pending.dt_month
        ) AS dt_prev_prev_month
    FROM
        monthly_manager_pending
    WHERE
        monthly_manager_pending.pending_request_count > 0
)
SELECT DISTINCT
    manager_month_streak.person_number_manager
FROM
    manager_month_streak
WHERE
    manager_month_streak.dt_month = ADD_MONTHS(manager_month_streak.dt_prev_month, 1)
    AND manager_month_streak.dt_prev_month = ADD_MONTHS(manager_month_streak.dt_prev_prev_month, 1)
```

**Pattern (collaborators / employees):** Reuse the same windowed pattern but aggregate and partition by **`attendance_request.person_number`** instead of **`person_number_manager`**.

## Glossary

* **Validity Window** : A period of time during which specific attributes of an entity remain constant and true.
* **Snapshot** : A representation of data as it existed at a specific, frozen point in time, such as daily or monthly intervals.
* **Current State** : The latest, real time version of the data representing only the active status of an entity without historical records.
* **SCD (Slowly Changing Dimension)** : A database design pattern used to store and manage both current and historical data over time.

## Related Scopes

* **Lifecycle and Employee attributes** : Use `dw_employee_details` when combining time-off views with broader employee documentation or lifecycle context.