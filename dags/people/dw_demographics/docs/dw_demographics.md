# Employee DE&I Attributes

**Metastore schema:** `dw_demographics`

> DE&I (diversity, equity, and inclusion) attributes for analytics: a time-aware profile of self-declared and standardized demographic fields, plus documented disability detail where it exists. Built for reporting that respects legislation, self-declaration, and how values change over time. Data originates from PIN, QuintoAndar's HR master system.

## People Data Catalog

This schema is indexed in the [People Data Catalog](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/5474320386/People+Data+Catalog).

[Link to Catalog Row](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/database/4638474284?contentId=4638474284&entryId=a5f75849-69fc-4796-9540-cc6b587ed925&savedViewId=136c293b-f5c1-48d6-a161-9586a403e181)

## Contents

* [In Scope](#in-scope)
* [Data Model and Tables](#data-model-and-tables)
* [Core Features and Business Logic](#core-features-and-business-logic)
* [Attention and Limitations](#attention-and-limitations)
* [How to Use](#how-to-use)
* [Glossary](#glossary)
***

## In Scope

**✅ Demographic profile** : Ethnicity, religion, gender identity, sexual orientation, neurodiversity signals, and related inclusion flags (URG, LGBT+, Women, BIM, PwD) versioned per person and legislation, with both current and historical rows for trends and as-of reporting.

**✅ Documented disability** : Records for people with formal disability documentation in PIN, including category and status, HR narrative (description, subclassification, work restrictions, accommodation requests, clinical codes), boolean self-declaration and accessibility-need flags, neurodiversity, and quota-related signals where applicable — linked to the same person and legislation context as the profile table.

**✅ People in scope** : Current and former employees and contractors whose last assignment was an employee or contractor type, so both active workforce and historical profiles are available.

### Out of Scope

❌ Employment facts, headcount, FTE, org slices, and tenure on a daily or monthly grain live in `dw_people` and `dw_employee_details`.

❌ Employee identity, contacts, documentation, hierarchy, and assignment history live in `dw_employee_details`.

### Who is included

* **Target Population:** Current and former employees and contractors whose last assignment type was employee or contractor. This includes both active workforce and terminated employees, so DE&I profiles remain accessible after offboarding. When legislative data is missing for someone in scope, a current row is still produced with unknown placeholders so joins do not drop people silently.
* **Exclusions:** Pending hires and test accounts. People whose only assignment type was pending are not represented.

## Data Model and Tables

### Data Sources and System Context

* **PIN** : The HR master system. All demographic attributes, documented disability records, and legal context (legislation) originate from PIN. PIN is the single business source of truth for this schema; display labels for ethnicity, religion, and sexual orientation come from PIN's own reference lists.

### About the data

* **Temporal coverage:** History (validity window, SCD Type 2). Each row is valid from a start date to an end date; the latest version of each person plus legislation combination is flagged as the current row. Ongoing rows use a far-future end date as the sentinel for "still valid today". Consecutive identical periods are merged into a single row.
* **Airflow DAG:** `bietlejuice.dw_demographics`
* **SLA:** D-1 available by 08:00 BRT

| Table | Grain | Links |
| :--- | :--- | :--- |
| `dim_employee_demographic` | Validity window: one record per person per legislation per period where the DE&I attribute set stays the same. When something changes, a new period opens and earlier periods remain for as-of reporting. | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_demographics.dim_employee_demographic,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_demographics/queries/dw/dim_employee_demographic.sql) |
| `dim_employee_disability` | Validity window: one record per person per legislation per documented disability record over its own validity period. A person can have zero, one, or many rows. | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_demographics.dim_employee_disability,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_demographics/queries/dw/dim_employee_disability.sql) |

> **Note:** VPN connection is required to access DataHub.

**Main join identifiers:**

* `sk_employee` (Standard PK/FK)
* `person_number` (Business Key from PIN)

## Core Features and Business Logic

### Domain logic and core concepts

* **Today's profile** : `is_current = TRUE` returns the latest validity-window row for each person regardless of employment status — it includes both active employees and people who have already been offboarded. To restrict to the currently active workforce, inner join `dw_people.fact_employees` on `sk_employee` (the fact already contains active employees only).
* **Validity over time** : When an attribute set changes, a new validity window opens and the previous one is closed; older windows remain available for trend and audit use. For an as-of historical date, filter the validity window to that date instead of relying only on `is_current`.
* **Legislation drives applicability** : Some flags only make sense under specific legal context. The BIM (Black, Indigenous, Mixed-race) flag, for example, is filled only under Brazilian legislation; for other countries it stays empty.
* **Composite inclusion flags** : URG (Underrepresented Group) is derived from BIM, Women, LGBT+, and PwD with documentation. When any input is unknown, the composite may stay empty; strict metrics should treat empty as not in scope.
* **Disability optionality** : Rows in `dim_employee_disability` are optional; not every person has them. Join only when you need disability taxonomy, documented narrative, or self-declared fields, and prefer the primary disability per person and legislation when quota information indicates it.
* **Documented vs self-declared** : Documented fields (category, status, description, restrictions, subclassification, clinical codes) come from the formal disability record in PIN. Self-declared disability type, neurodiversity, and accessibility need come from overlapping legislative data for the same person and legislation period.
* **Label language** : HR narrative fields are kept as entered in PIN (source language as typed by HR). Lookup-backed labels for category, self-declared type, and neurodiversity prefer English PIN reference data, with a local-language lookup fallback when no English label exists.
* **Primary documented label** : `documented_name` is the reporting-friendly label: HR subclassification or clinical description when present, otherwise the English lookup label for the disability code, otherwise the raw code.

### Business Assumptions

* **Empty BIM is intentional outside Brazil** : Race-based inclusion is meaningful only under Brazilian legislation. Outside Brazil the value is empty by design; do not treat empty as false.
* **DataHub is the source of truth for column rules** : Authoritative definitions of metrics and flags (for example BIM, LGBT+, URG, PwD) are maintained in DataHub on each column. Use those descriptions for formulas, null handling, and governance.
* **Reporting tip** : Start from `dim_employee_demographic` with `is_current = TRUE` to get the latest row per person, then left join `dim_employee_disability` only when you need disability breakdowns. For active workforce only, inner join `dw_people.fact_employees` on `sk_employee`.

## Attention and Limitations

* **Disability rows are not universal** : Most people do not have rows in `dim_employee_disability`. Always use a `LEFT JOIN` when adding disability detail to a demographic query; an `INNER JOIN` will silently drop everyone without a record.
* **Self-declaration is not the same as documentation** : `has_self_declared_pwd` on the demographic profile captures what the person reported on the legislative form. `has_self_declared_disability` on the disability table applies the same yes/no decoding when joined to an overlapping disability row. `has_medical_disability_record` reflects whether a formal medical record overlaps the demographic period. They are independent and can disagree; choose deliberately for each metric.
* **Accessibility need is a boolean flag** : `has_accessibility_need` is true, false, or null when PIN uses standard yes/no codes. Use this flag for counts and filters; free-text accommodation detail lives on the documented disability record.
* **Documented narrative is restricted** : Description, work restrictions, and accommodation request text are sensitive occupational-health fields. Prefer aggregate reporting on `category`, `documented_name`, `disability_status`, and the boolean flags; do not publish free-text narrative in open DE&I dashboards.
* **Quota status labels** : PIN status maps to Active, Pending, Inactive (or Unknown). There is no dedicated warehouse status for a disability that is not quota-eligible; treat self-declaration and documentation as separate signals when those populations differ.
* **Avoid double-counting on disability** : A person can have multiple disability rows over time. When summarizing per person, deduplicate by `sk_employee` (or use `is_primary`) before counting.
* **As-of reporting requires validity overlap** : To report a past month or to align demographic attributes with a fact row, compare `dt_valid_from` / `dt_valid_to` with the reference date rather than relying only on `is_current`.
* **`is_current` does not mean active employee** : `is_current = TRUE` on demographic dimensions returns the latest validity-window row per person, including terminated employees. Inner join `dw_people.fact_employees` on `sk_employee` when the analysis should cover only people currently employed.

## How to Use

### Standard Join Pattern

When joining this schema's tables with other DW domains:

1. Always join on `sk_employee` (preferred) or `person_number`.
2. Reference `dw_people.dim_employee` for central employee attributes and `dw_people.fact_employees` (or `dw_employee_details.fact_assignment_snapshots`) for active workforce, FTE, or org-sliced counts.
3. When also joining `dim_employee_disability`, add `legislation_code` and the validity-window overlap to the predicate.

### Latest DE&I attributes per person (active and terminated)

**Question:** What is the latest DE&I profile for all employees and contractors, including those who have already left?

> To scope to active-only, inner join `dw_people.fact_employees` on `sk_employee`.

```sql
SELECT
    employee_demographic.sk_employee,
    employee_demographic.person_number,
    employee_demographic.legislation_code,
    employee_demographic.ethnicity,
    employee_demographic.gender_identity,
    employee_demographic.sexual_orientation,
    employee_demographic.is_urg,
    employee_demographic.is_current,
    employee_demographic.dt_valid_from,
    employee_demographic.dt_valid_to
FROM
    dw_demographics.dim_employee_demographic AS employee_demographic
WHERE
    employee_demographic.is_current = TRUE
```

### Disability status and category (active workforce)

**Question:** Among active employees, how many have an active documented disability record, by status and category?

> Use `is_primary` when counting people so multiple disability rows do not inflate headcount. Prefer `category` and `disability_status` for open reporting; keep free-text description and work restrictions out of shared dashboards.

```sql
SELECT
    employee_disability.disability_status,
    employee_disability.category,
    COUNT(DISTINCT fact_employees.sk_employee) AS employee_count
FROM
    dw_people.fact_employees AS fact_employees
INNER JOIN dw_demographics.dim_employee_disability AS employee_disability
    ON employee_disability.sk_employee = fact_employees.sk_employee
    AND employee_disability.is_active = TRUE
    AND employee_disability.is_primary = TRUE
GROUP BY
    employee_disability.disability_status,
    employee_disability.category
ORDER BY
    employee_count DESC
```

### Self-declared disability and accessibility need (active workforce)

**Question:** How many active people self-declared a disability, and how many declared an accessibility need?

> Workforce-wide self-declaration uses `has_self_declared_pwd` on the demographic profile (including people without a quota-eligible disability record). Accessibility need lives on the disability dimension and is only available when a documented disability row exists.

```sql
SELECT
    COUNT(
        DISTINCT CASE
            WHEN employee_demographic.has_self_declared_pwd = TRUE
                THEN fact_employees.sk_employee
        END
    ) AS count_self_declared_pwd,
    COUNT(
        DISTINCT CASE
            WHEN employee_disability.has_accessibility_need = TRUE
                THEN fact_employees.sk_employee
        END
    ) AS count_accessibility_need
FROM
    dw_people.fact_employees AS fact_employees
INNER JOIN dw_demographics.dim_employee_demographic AS employee_demographic
    ON employee_demographic.sk_employee = fact_employees.sk_employee
    AND employee_demographic.is_current = TRUE
LEFT JOIN dw_demographics.dim_employee_disability AS employee_disability
    ON employee_disability.sk_employee = fact_employees.sk_employee
    AND employee_disability.legislation_code = employee_demographic.legislation_code
    AND employee_disability.dt_valid_from <= employee_demographic.dt_valid_to
    AND employee_disability.dt_valid_to >= employee_demographic.dt_valid_from
    AND employee_disability.is_primary = TRUE
```

### Neurodiversity among people with documented disability (active workforce)

**Question:** Among active people with a primary disability record, how does self-declared neurodiversity break down?

```sql
SELECT
    COALESCE(employee_disability.neurodiversity, 'Unknown') AS neurodiversity,
    COUNT(DISTINCT fact_employees.sk_employee) AS employee_count
FROM
    dw_people.fact_employees AS fact_employees
INNER JOIN dw_demographics.dim_employee_disability AS employee_disability
    ON employee_disability.sk_employee = fact_employees.sk_employee
    AND employee_disability.is_primary = TRUE
GROUP BY
    COALESCE(employee_disability.neurodiversity, 'Unknown')
ORDER BY
    employee_count DESC
```

### Headcount by ethnicity (current active workforce)

**Question:** How many active employees, by ethnicity, as of the latest load?

```sql
SELECT
    employee_demographic.ethnicity,
    COUNT(DISTINCT fact_employees.sk_employee) AS employee_count
FROM
    dw_people.fact_employees AS fact_employees
INNER JOIN dw_demographics.dim_employee_demographic AS employee_demographic
    ON employee_demographic.sk_employee = fact_employees.sk_employee
    AND employee_demographic.is_current = TRUE
GROUP BY
    employee_demographic.ethnicity
ORDER BY
    employee_count DESC
```

For a **past reference month**, use `dw_employee_details.fact_assignment_snapshots` with `is_monthly_snapshot_for_employee = TRUE` and align demographic validity windows to `dt_reference`.

## Glossary

* **Validity Window** : A period of time during which specific attributes of an entity remain constant and true. A new window opens when a value changes; represented by `dt_valid_from` / `dt_valid_to` pairs.
* **Snapshot** : A representation of data as it existed at a specific, frozen point in time.
* **Current State** : The latest version of the data; for this schema, the row flagged as the current validity window for each person and legislation.
* **SCD (Slowly Changing Dimension)** : A design pattern for storing both current and historical attribute values over time. Both tables in this schema use SCD Type 2 (validity windows).
* **BIM** : Black, Indigenous, and Mixed-race. Inclusion signal under Brazilian legislation.
* **URG** : Underrepresented Group. Composite signal combining race, gender, sexual orientation, and disability inclusion.
* **LGBT+** : Inclusion signal derived from gender identity and sexual orientation.
* **PwD** : Person with a Disability. Distinguished here between self-declaration (`has_self_declared_pwd`, `has_self_declared_disability`) and formal documentation (`has_medical_disability_record`, disability rows in `dim_employee_disability`).
* **Documented disability narrative** : Free-text description, subclassification, work restrictions, accommodation requests, and clinical classification codes on the documented disability record — kept as entered in PIN. Restricted use; prefer `category`, `documented_name`, and status for open reporting.

