# Employee Core & Structure

**Metastore schema:** `dw_employee_details`

> Covers all essential employee attributes (identity, contact details, official documents, org structure, and daily workforce history), making this the starting point for headcount, tenure, and demographic analyses in the People domain.

## People Data Catalog

This schema is indexed in the [People Data Catalog](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/4635951235/People+Data+Catalog).

[Link to Catalog Row](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/5473992727/Employee+Details)

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

**✅ Employee identity** : Preferred name, work email, date of birth, education level, and generation cohort.

**✅ Contact & legal documents** : Personal email, phone, residential address, and GitHub handle, versioned over time. Official documents (CPF, RG, PIS, CTPS, voter registration, legal name) are also versioned and stored for compliance use.

**✅ Emergency contacts** : Active and historical emergency contact records per employee.

**✅ Organizational structure** : Full reporting chain from CEO (L0) down to each employee, updated as the org evolves.

**✅ Daily workforce history** : One snapshot per assignment per calendar day, capturing tenure, headcount flags, active/terminated status, and all links to related dimensions.

### Out of Scope

Closely related employee topics that live in sibling schemas, not in `dw_employee_details`:

**❌ Compensation** : Salary history, job levels, pay tables, and variable pay are in `dw_compensation`.

**❌ Organization** : Business unit, cost center, team definitions, and Codex are in `dw_organization`.

**❌ DE&I** : Sensitive self-declared attributes (ethnicity, gender identity, sexual orientation, religion, disability category, neurodiversity) are in `dw_demographics`, under stricter access controls.

### Who is included

* **Target Population:** All current and former employees with a valid HR assignment, including both contractors and full-time employees.
* **Exclusions:** Test users and automated system accounts are not included.

## Data Model and Tables

### Data Sources and System Context

* **PIN** : The company's HR management platform and single source of truth for all employee records in this schema, covering personal data, official documents, contacts, org assignments, and reporting structures.

### About the data

* **Temporal coverage:** Mixed. Employee identity is Current State (latest version only); contact, documentation, emergency contact, and hierarchy tables are Validity Windows (history of changes); `fact_assignment_snapshots` is a Daily Snapshot.
* **Airflow DAG:** `bietlejuice.dw_employee_details`
* **SLA:** D-1 available by 08:00 BRT

| Table | Grain | Links |
| :--- | :--- | :--- |
| `dim_employee` | Current state: one record per employee (latest personal info) | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_employee_details.dim_employee,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_employee_details/queries/dw/dim_employee.sql) |
| `dim_contact` | Validity window: one record per employee per contact change | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_employee_details.dim_contact,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_employee_details/queries/dw/dim_contact.sql) |
| `dim_documentation` | Validity window: one record per employee per document period | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_employee_details.dim_documentation,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_employee_details/queries/dw/dim_documentation.sql) |
| `dim_emergency_contact` | Validity window: one record per emergency contact per employee | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_employee_details.dim_emergency_contact,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_employee_details/queries/dw/dim_emergency_contact.sql) |
| `dim_event_definition` | Current state: one record per termination reason | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_employee_details.dim_event_definition,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_employee_details/queries/dw/dim_event_definition.sql) |
| `dim_management_hierarchy` | Validity window: one record per assignment per hierarchy version | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_employee_details.dim_management_hierarchy,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_employee_details/queries/dw/dim_management_hierarchy.sql) |
| `fact_assignment_snapshots` | Daily snapshot: one record per assignment per calendar day | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_employee_details.fact_assignment_snapshots,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_employee_details/queries/dw/fact_assignment_snapshots.sql) |

> **Note:** VPN connection is required to access DataHub.

**Main join identifiers:**

* `sk_employee` (Standard PK/FK)
* `person_number` (Business Key from PIN)
* `assignment_number` (Assignment-level Business Key from PIN; one employee may have more than one)

## Core Features and Business Logic

### Domain logic and core concepts

* **Daily workforce history** : `fact_assignment_snapshots` holds one row per assignment per calendar day; it is historical and continuous, not a single latest-version or monthly table. Always apply a date-scope filter to avoid unintended row multiplication.
* **Org chain depth** : `dim_management_hierarchy` maps up to ten levels (L0 to L9), where L0 is always the CEO. For a given date, every person in the same area shares the same L1: the director, manager, analyst, and intern of a team will all have the same VP in `name_l1`. This makes it straightforward to filter or aggregate by any reporting chain without self-joins.
* **Termination classification** : `dim_event_definition` stores two levels of termination detail: the action (voluntary or involuntary) and the reason (a finer label describing why). Both are available in English and Portuguese. Link via `sk_termination_event_definition` on the fact.
* **Tenure** : Time at the company is pre-computed on the fact and available in two granularities: `days_tenure_in_company` and `months_tenure_in_company`. For scenarios where the focus is the current assignment rather than the full company history, `days_tenure_in_assignment` measures how long the person has been in their current role. All three are calculated relative to `dt_reference`, so they update automatically as the snapshot advances each day.
* **Span of control** : `count_direct_report` holds the number of employees who report directly to a person; `count_indirect_report` holds the full count of people below them in the hierarchy. Both are pre-joined on the fact, making it straightforward to identify managers, measure team sizes, or filter for individual contributors without additional aggregations.

### Business Assumptions

* **Preferred name is the standard** : The `name` column in `dim_employee` reflects the employee's preferred (social) name. Legal names are stored separately in `dim_documentation` and should only be used for compliance or contractual contexts.
* **Work email is the primary PIN address** : The `work_email` in `dim_employee` always reflects the employee's primary email as registered in PIN, even if the person has additional addresses or aliases configured elsewhere.
* **Every active employee has a complete reporting chain** : For every `dt_reference`, all active employees are expected to have a manager whose chain, when followed upward, reaches the CEO (L0). Rows where the hierarchy does not connect all the way to L0 are considered data quality gaps and should not occur in normal conditions.

## Attention and Limitations

* **`sk_*_version` keys are point-in-time, not fixed** : Foreign keys like `sk_contact_version`, `sk_documentation_version`, and `sk_hierarchy_version` in the fact table do not identify a single, stable record for an entity. They identify the version of that attribute that was valid on a specific `dt_reference`. The same employee will have different `sk_contact_version` values across dates if their contact info changed. Treat these as temporal join keys, not as permanent identifiers.
* **Always scope `dt_reference`** : `fact_assignment_snapshots` contains one row per assignment per calendar day. Querying without a date filter will return every historical day for every assignment, multiplying row counts and producing inflated totals. Use `is_current = TRUE` to get today's state (equivalent to the former *base completa*), or filter to a specific `dt_reference` value. Use `is_monthly_snapshot = TRUE` for monthly headcount, replacing the former *base fotografias* pattern.
* **Multi-assignment employees** : An employee who transferred internally or was rehired may hold more than one `assignment_number`. Use `is_primary_assignment_for_snapshot = TRUE` for the canonical assignment on a given `dt_reference`. For person-grain current exports, use `is_current_for_person = TRUE` to get exactly one row per person.
* **Work email history not available** : Each assignment has an associated work email, but the current model exposes only the email from the person's most recent assignment. Emails from previous assignments are not accessible through this schema.
* **Hire date semantics** : The fact table exposes two hire dates that serve different purposes. `dt_hired` is the start date of the employee's most recent contract, regardless of any prior employment history. `dt_original_hire` is the start date of their very first contract at the company, which may predate a cross-entity transfer. For tenure calculations that should credit prior employment, use `dt_original_hire`; for calculating seniority within the current contract, use `dt_hired`. The flag `is_internal_transfer` indicates that the current contract began as a transfer from a previous one, meaning the person was already at the company before this assignment started.

## How to Use

### Standard Join Pattern

When joining this schema's tables with other DW domains:

1. Always join on `sk_employee` (preferred) or `person_number`.
2. Reference `dw_employee_details.dim_employee` for identity attributes such as preferred name, work email, and generation.

### Wide Join (Exploratory Query)

**Question:** What does the current workforce look like, combining all available attributes?

```sql
SELECT
    -- Identity
    emp.name,
    emp.work_email,
    emp.generation,
    emp.highest_education_level,
    -- Contact
    ct.full_phone_number,
    ct.address_city,
    ct.address_state,
    -- Documentation
    doc.marital_status,
    -- Emergency contact
    ec.contact_name                        AS emergency_contact_name,
    ec.contact_relationship                AS emergency_contact_relationship,
    -- Org structure
    hier.name_l1                           AS vp_name,
    hier.name_l2                           AS director_name,
    hier.name_l3                           AS manager_name,
    -- Termination reason (null for active employees)
    evt.action_name                        AS termination_action,
    evt.reason_name                        AS termination_reason,
    -- Workforce metrics
    fact.days_tenure_in_company,
    fact.is_manager,
    fact.is_leadership_team_member,
    fact.is_active
FROM
    dw_employee_details.fact_assignment_snapshots AS fact
INNER JOIN
    dw_employee_details.dim_employee AS emp
    ON fact.sk_employee = emp.sk_employee
LEFT JOIN
    dw_employee_details.dim_contact AS ct
    ON fact.sk_contact_version = ct.sk_contact_version
LEFT JOIN
    dw_employee_details.dim_documentation AS doc
    ON fact.sk_documentation_version = doc.sk_documentation_version
LEFT JOIN
    dw_employee_details.dim_emergency_contact AS ec
    ON fact.sk_emergency_contact_version = ec.sk_emergency_contact_version
LEFT JOIN
    dw_employee_details.dim_management_hierarchy AS hier
    ON fact.sk_hierarchy_version = hier.sk_hierarchy_version
LEFT JOIN
    dw_employee_details.dim_event_definition AS evt
    ON fact.sk_termination_event_definition = evt.sk_event_definition
WHERE
    fact.is_current = TRUE
    AND fact.is_active = TRUE
```

### Analytical Snapshot (Voluntary Terminations by Manager's Chain)

**Question:** How many voluntary terminations occurred below a specific manager's structure, month by month in 2026?

```sql
SELECT
    DATE_TRUNC('month', fact.dt_terminated)     AS termination_month,
    COUNT(DISTINCT fact.person_number)           AS voluntary_terminations
FROM
    dw_employee_details.fact_assignment_snapshots AS fact
INNER JOIN
    dw_employee_details.dim_event_definition AS evt
    ON fact.sk_termination_event_definition = evt.sk_event_definition
INNER JOIN
    dw_employee_details.dim_management_hierarchy AS hier
    ON fact.sk_hierarchy_version = hier.sk_hierarchy_version
WHERE
    fact.is_current = TRUE
    AND NOT fact.is_active
    AND YEAR(fact.dt_terminated) = 2026
    AND evt.reason_name = '<voluntary_reason_label>'
    AND (
        hier.name_l1 ILIKE '%<manager_name>%'
        OR hier.name_l2 ILIKE '%<manager_name>%'
        OR hier.name_l3 ILIKE '%<manager_name>%'
        OR hier.name_l4 ILIKE '%<manager_name>%'
    )
GROUP BY 1
ORDER BY 1
```

> **Tip:** Replace `<manager_name>` with the manager's name as it appears in `dim_management_hierarchy`. Check `dim_event_definition` to confirm the exact `reason_name` value for voluntary terminations before running in production.

## Glossary

* **Validity Window** : A period during which specific attributes of an employee remain unchanged and valid, represented by `dt_valid_from` / `dt_valid_to` pairs in dimension tables.
* **Snapshot** : A representation of data as it existed at a specific point in time. `fact_assignment_snapshots` stores one snapshot per assignment per calendar day.
* **Current State** : The latest version of the data, with no historical records. `dim_employee` is always current state.
* **SCD (Slowly Changing Dimension)** : A design pattern for storing both current and historical attribute values over time. Most dimensions in this schema use SCD Type 2 (validity windows).

## See Also

* **Ad-hoc Analytics** : [Ad-hoc Analytics](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/5468979201/Ad-hoc+Analytics): curated query examples and ready-to-use analytical templates. Includes `people_metric.employee_snapshots`, the official One Big Table (OBT) that joins `dw_employee_details` with compensation, demographics, and other DW domains to recreate the full employee picture previously known as *base fotografias*.
