# DW Time - Workforce time and attendance: dw_time

## People Data Catalog

[People Data Catalog database](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/database/4638474284?contentId=4638474284&entryId=ee0b4dc1-56e4-4947-be5e-d50e02efd4f9&savedViewId=136c293b-f5c1-48d6-a161-9586a403e181)

## Contents

- [People Data Catalog](#people-data-catalog)
- [Description](#description)
- [Scope](#scope)
- [Out of scope](#out-of-scope)
- [Tables](#tables)
- [Data model](#data-model)
- [Full data model on GitHub](#full-data-model-on-github)
- [Executive summary](#executive-summary)
- [Business logic](#business-logic)
- [Data dictionary](#data-dictionary)
- [How to use](#how-to-use)
- [Sensitivity and access](#sensitivity-and-access)

---

## Description

The **`dw_time`** schema is the People Data Warehouse home for **workforce time and attendance** facts sourced from the company’s **time integration** (requests, approvals, hours-bank balances, and salary-rate segments used for operational analytics). It is built for **approval SLAs**, **hours-bank** reporting, and **cross-functional** views that combine **who** (PIN), **where** (cost center and vertical from the org model), and **who approves** (management hierarchy)—without replacing **payroll** or **PIN** as the systems of record for pay and master data.

## Scope

**✅ Time requests and approvals** — Line-level **requests** (intervals, adjustments, configured subtypes) with **approval status**, **stage**, and **flow** payload for dashboards such as **manager approval backlog**.

**✅ Request subtype reference** — **`dim_request`** for subtype labels and defaults (**paid**, **DSR-related** flags) aligned to the integration catalog.

**✅ Hours bank** — **`fact_hours_bank_rule_totals`** with balances per rule segment and optional **estimated monetary** amount when an **hourly rate window** matches; **`dim_hours_bank_rule`** for segment labels.

**✅ Hourly cost windows from the time product** — **`fact_employee_hourly_cost_windows`** for **order-of-magnitude** cost context tied to the integration’s salary segments (**compensation-sensitive**).

**✅ People in scope** — **Employees** who appear in the **time integration** and are matched to **PIN**, so **approval pendencies** (volume, hierarchy, cost center) and **hours bank** (balances and estimated cost by org) both combine cleanly with **`dw_people`** and **`dw_organization`**—same idea as other People marts. **Test accounts** are excluded.

## Out of scope

**❌ Official payroll results** — Gross pay, deductions, and final DSR calculations remain in **payroll** systems and downstream finance marts; use **`dw_time`** for **operational** and **estimated** views only.

**❌ PIN absence workflows not mirrored in the time product** — Some absences or benefits may exist only in **PIN** or other HR flows; see **`dw_employee`** / **`dw_employee_details`** when the question is **PIN absence entries**, not Oitchau request lines.

**❌ Full compensation history** — Salary bands, equity, and compensation policy history live in **`dw_compensation`**; join there only when the analysis explicitly requires compensation tables beyond the **hourly segment** in **`dw_time`**.

**❌ Demographics and performance** — DE&I attributes in **`dw_demographics`**; performance cycles in **`dw_performance`**.

---

## Tables

Explore schemas and column-level detail in **DataHub** (lineage and definitions). **View SQL** opens the **query used to build each table** on GitHub (`queries/dw/{table}.sql`).

| Table | Explore in DataHub | Explore in GitHub |
|-------|-------------------|-------------------|
| `dim_hours_bank_rule` | [Open schema](<https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_time.dim_hours_bank_rule,PROD)/Schema?is_lineage_mode=false&schemaFilter=>) | [View SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_time/queries/dw/dim_hours_bank_rule.sql) |
| `dim_request` | [Open schema](<https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_time.dim_request,PROD)/Schema?is_lineage_mode=false&schemaFilter=>) | [View SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_time/queries/dw/dim_request.sql) |
| `fact_employee_hourly_cost_windows` | [Open schema](<https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_time.fact_employee_hourly_cost_windows,PROD)/Schema?is_lineage_mode=false&schemaFilter=>) | [View SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_time/queries/dw/fact_employee_hourly_cost_windows.sql) |
| `fact_hours_bank_rule_totals` | [Open schema](<https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_time.fact_hours_bank_rule_totals,PROD)/Schema?is_lineage_mode=false&schemaFilter=>) | [View SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_time/queries/dw/fact_hours_bank_rule_totals.sql) |
| `fact_time_attendance_requests` | [Open schema](<https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_time.fact_time_attendance_requests,PROD)/Schema?is_lineage_mode=false&schemaFilter=>) | [View SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_time/queries/dw/fact_time_attendance_requests.sql) |

---

## Data model

**Grain**

- **`fact_time_attendance_requests`:** One row per **request identifier** from the time product for employees in scope; each row carries **approval outcome**, **interval timestamps**, and keys to **subtype** and **employee**.
- **`dim_request`:** One row per **request subtype** configuration (labels and defaults used for grouping “abono” vs “manual marking” style categories in the product).
- **`fact_hours_bank_rule_totals`:** One row per **employee** per **balance date** per **rule segment**; optional **estimated cost** when a matching **hourly rate window** exists.
- **`fact_employee_hourly_cost_windows`:** One row per **hourly salary segment** per employee from the integration.
- **`dim_hours_bank_rule`:** One row per **rule segment** reference for **labels** and policy metadata.

**Joins in plain language:** Attach **subtype names** to request lines on **`sk_request`**. Attach **manager names** and the **reporting chain** with **`dw_people.dim_management_hierarchy`**. Attach **cost center**, **vertical**, **job**, and **business unit** for the **month of the request** by going through **`dw_people.fact_employees`** on **`sk_employee`** and **month-end `dt_reference`**, then **`dw_organization`** dimensions.

### Full data model on GitHub

For a **relationship overview and join patterns** (for example when **People Insights** prepares analyses for **DP**), open **[data_model.md](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_time/docs/data_model.md)**.

---

## Executive summary

**`dw_time`** supports **operational time** analytics: **pending and decided requests**, **hours-bank** positions with optional **rough cost**, and **hourly rate windows** from the time stack. For **approval dashboards**, combine **`fact_time_attendance_requests`** with **`dw_people`** (employee, **monthly assignment snapshot**, hierarchy) and **`dw_organization`** (cost center, vertical, job, business unit). **Near-real-time** pendency in the UI may still read the **API**; the warehouse follows the **People DW** refresh cadence.

### Key concepts

- **Approval labels** in the data are **English** (`pending`, `approved`, `declined`, `ignored`); map to Portuguese in Looker Studio if needed (**Pendente / Aprovado / Reprovado / Inválido or ignorado**).
- **Org slice for a request month** uses **`dw_people.fact_employees`** with **`dt_reference`** equal to the **last calendar day** of the month containing **`ts_interval_started`** (primary assignment on that snapshot).
- **Payroll close** and **countdown** are not native columns here—model them with a **calendar** or **parameters** maintained by HR and join by month or company.

### Refresh and availability

People warehouse **DW layer SLA**: data is expected to be **available by 8:00** (once per day). This pipeline runs after upstream People and time clean tables have loaded.

### Granularity

See [Data model](#data-model).

### Where to find the data

**Schema:** `dw_time` · **Airflow pipeline:** `bietlejuice.dw_time`

---

## Business logic

### Who is included

**Request lines** include employees whose **registration** in the time product maps to a **current PIN assignment** in **`identifier_mapping`**, excluding **test users**. Rows without a successful mapping are dropped at build time.

### Request and approval fields

**`approval_status`** reflects the integration state (**pending** still in flow, **approved** / **declined** decided, **ignored** bypassed or treated as ignored). Use **`approval_stage`** and **`approval_flow`** when the dashboard must show **where** the case sits in the configured workflow. Pair with **`dim_management_hierarchy`** to attribute backlog to **direct managers** or **L1** leaders.

### Financial and DSR context

**`dim_request.is_discount_dsr`** and **`is_paid_subtype`** describe **subtype defaults**; line-level flags such as **`is_paid_request`** and **`hours_calculation_type`** can differ for a given booking. **`fact_hours_bank_rule_totals.estimated_balance_cost_amount`** combines **minutes** with a matched **hourly rate** for **bank** lines—use as **supporting insight**, not payroll truth.

**Reporting tip:** When the business question is **“impact if approvals slip”**, prefer a **defined payroll rule** (hours × rate × policy) agreed with HR; the examples below show **patterns** using **`dw_time`** and **`dw_people`** keys.

---

## Data dictionary

Summary columns only. **Authoritative** definitions: **DataHub** (links in [Tables](#tables)).

### `dw_time.fact_time_attendance_requests`

| Column | Business definition | Notes |
|--------|---------------------|-------|
| `sk_time_request` | Internal key for one request row in analytics. | Stable for counts. |
| `sk_employee` | Employee key shared with **`dw_people`**. | Join **`dim_employee`**, **`fact_employees`**. |
| `person_number` | PIN person number. | Join hierarchy and spreadsheets. |
| `approval_status` | Outcome state from the time product (**English** labels). | Map to dashboard language in Looker. |
| `approval_stage` | Step index in the approval flow. | SLA analytics. |
| `request_type` | High-level family (for example medical, vacation, custom). | Volume split. |
| `ts_interval_started` / `ts_interval_ended` | Booked interval. | Month attribution for org join. |

### `dw_time.dim_request`

| Column | Business definition | Notes |
|--------|---------------------|-------|
| `subtype_name` | Human-readable subtype. | Group “abonos” vs manual marks when labels match operations language. |
| `is_paid_subtype` / `is_discount_dsr` | Defaults from configuration. | Pair with line-level flags on the fact. |

---

## How to use

The bullets below mirror the **business questions** for the **time approval dashboard** (reducing **HR operations** rework and payroll risk). They intentionally combine **`dw_time`** with **`dw_people`** and **`dw_organization`**, matching the **Looker Studio** approach (integration plus **org chart**).

**Cross-schema keys:** **`sk_employee`**, **`person_number`**, **`fact_employees.sk_cost_center_version`**, **`dim_management_hierarchy.person_number`**.

**Example SQL** targets **Databricks SQL** (adjust **`date_trunc` / `last_day`** if your engine differs). Add **stricter date or partition filters** in production; examples use **`CURRENT_DATE()`** for illustration only.

---

### Volume and operational efficiency — pending items (warehouse view)

**Question:** What is the **total volume of manager approval pendencies** for a recent window (warehouse refresh), and how does it compare to all requests in the same window?

**Pattern:** True **real-time** counts may come from the **time product API** in Looker Studio; the warehouse reflects the **latest daily** load.

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

---

### Volume and operational efficiency — share of pendencies by management and cost center

**Question:** What **percentage of requests in the calendar month** are **pending**, broken down by **direct manager** and **cost center**?

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

---

### Volume and operational efficiency — distribution by approval status and request family

**Question:** How are **requests** (including **abonos** and **manual marks** style flows) distributed across **pending**, **approved**, **declined**, and **ignored**?

**Pattern:** Map **`ignored`** to the business label **Inválido / ignorado** only if your HR glossary agrees; otherwise treat **ignored** as its own category.

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

---

### Volume and operational efficiency — countdown to payroll close

**Question:** How much time remains until **payroll close**?

**Pattern:** This is **not** stored in **`dw_time`**. Implement a **parameter** or a **small calendar table** in Looker Studio (or a governed reference table) with **cutoff timestamp per month and legal entity**, then compute **`cutoff_ts - current_timestamp()`** in the presentation layer. Join warehouse facts on **calendar month** of **`ts_interval_started`** when you need to align pendencies to the same **close month**.

---

### Management and performance — top backlog after payroll close (managers and cost centers)

**Question:** Which **managers**, **verticals**, and **cost centers** have the **largest open backlog after the close deadline**?

**Pattern:** Replace **`DATE '2099-12-31'`** with your **official cutoff date** for the month under analysis (or join a **payroll calendar** table).

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

---

### Management and performance — agility by vertical (time to decision)

**Question:** Which **verticals** show the **slowest approval** behaviour?

**Pattern:** **Median or average hours** from **`ts_created`** to **`ts_updated`** for rows that reached **`approved`** or **`declined`**; segment by **`dim_cost_center.vertical`** on the request month snapshot.

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

---

### Management and performance — correlation of pendencies with job and business unit

**Question:** Is there a **concentration** of **pending** requests by **job** or **business unit**?

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

---

### Financial impact and risk — rough exposure for pending requests (hours × rate)

**Question:** What is the **estimated financial exposure** from **unresolved** lines where **payroll-relevant** flags apply?

**Pattern:** This uses **integration hourly rate** windows and **booked duration**; **payroll** remains authoritative. Elapsed hours use **`UNIX_TIMESTAMP`** differences (Databricks / Spark SQL).

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
pending_with_rate AS (
    SELECT
        pending_requests.sk_time_request,
        cost_window.hourly_rate_amount,
        GREATEST(
            (
                UNIX_TIMESTAMP(pending_requests.ts_interval_ended)
                - UNIX_TIMESTAMP(pending_requests.ts_interval_started)
            ) / 3600.0,
            0.0
        ) AS booked_hours
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
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                pending_requests.sk_time_request
            ORDER BY
                cost_window.dt_hourly_cost_segment_started DESC NULLS LAST
        ) = 1
)
SELECT
    ROUND(
        SUM(booked_hours * COALESCE(pending_with_rate.hourly_rate_amount, 0)),
        2
    ) AS estimated_exposure_amount
FROM
    pending_with_rate
```

---

### Financial impact and risk — confirmed backlog after close

**Question:** What is the **confirmed impact bucket**: pendencies that were **still pending after** the **payroll close** instant?

**Pattern:** Same **`payroll_cutoff`** substitution as above; the metric is a **count** or the **financial pattern** query restricted to **`ts_updated > cutoff`**.

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

---

### Financial impact and risk — HR rework estimate

**Question:** What **rework effort** should the **HR operations** team plan for corrections linked to approval delays?

**Pattern:** The warehouse does **not** store **ticket minutes**. Common approach: **`pending_request_count_after_close * assumed_minutes_per_case`**, with **`assumed_minutes_per_case`** owned by **HR** as a **parameter** in Looker Studio. Combine with the **count** example in the previous subsection.

---

### Behaviour and recurrence — managers with pendencies in three consecutive months

**Question:** Which **managers** (or **employees**) appear with **open pendencies** in **three consecutive months**?

**Managers (direct manager person number):**

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

**Collaborators (employee `person_number`):** reuse the same pattern with **`attendance_request.person_number`** in the **`GROUP BY`** and window **`PARTITION BY`** instead of **`person_number_manager`**.

---

### Behaviour and recurrence — punctual spike versus systematic recurrence

**Question:** Is the approval problem **one-off** or **recurring**?

**Pattern:** Compare **`pending_request_count` by month** for the **same manager** or **vertical** using **`monthly_manager_pending`** (above); **one sharp month** suggests a **punctual** driver, **flat or rising multi-month series** suggests **systemic** behaviour. Combine with **process changes** or **headcount changes** from **`dw_people.fact_employees`** if needed.

---

## Sensitivity and access

**Personal data:** **`person_number`**, **employee names** (via **`dw_people`** joins), and **hourly rate** fields are **sensitive**; follow **LGPD** and **internal People data** policy. Limit extracts to **least privilege** roles.

**Financial disclaimers:** **Hourly** amounts from the **time integration** support **operational** estimates only; **payroll** and **finance** systems decide **actual** discounts, **DSR**, and **reimbursements**.

Engineering detail (lineage, full column text) lives in **DataHub** and **`metadata/dw/*.yml`** for this DAG.
