# Employee Details

## Overview

Employee Details (`dw_employee_details`) is the primary internal People DW schema for workforce identity, contact and legal documentation, emergency contacts, management hierarchy, and daily assignment snapshots. It is the starting point for headcount, tenure, admissions, exits, and org-structure analysis within the People domain.

**Population:** all current and former employees with a valid HR assignment (contractors and full-time). Test users and automated system accounts are excluded.

**Source:** PIN (Oracle HCM) — single source of truth for personal data, documents, contacts, assignments, and reporting structures.

**SLA:** D-1, available by 08:00 BRT. DAG: `bietlejuice.dw_employee_details`.

**Temporal model:** mixed. `dim_employee` is current state only. Contact, documentation, emergency contact, and hierarchy dimensions are SCD Type 2 validity windows (`dt_valid_from` / `dt_valid_to`). `fact_assignment_snapshots` is a daily snapshot — one row per `assignment_number` per calendar day.

**Out of scope (sibling schemas):** compensation → `dw_compensation`; cost center / BU / job definitions → `dw_organization`; DE&I self-declared attributes → `dw_demographics` (stricter access).

Sensitive personal data (CPF, address, legal name, marital status) lives here under restricted access. Prefer `dim_employee.name` (preferred name) for display; use `dim_documentation` only for compliance contexts.

For the full business-facing schema guide, see `dags/people/dw_employee_details/docs/dw_employee_details.md`.

## Related Business Entities

- `organization.md` — cost center, business unit, and job reference dimensions joined via `sk_cost_center_version`, `sk_business_unit`, and `sk_job_version` on the fact.

## Glossary and Synonyms

- **Colaborador / funcionário / employee** → `dim_employee` / `fact_assignment_snapshots`
- **Headcount / quadro** → active rows on `fact_assignment_snapshots` with `is_active = TRUE`
- **Base fotografias / snapshot mensal** → `fact_assignment_snapshots` with `is_monthly_snapshot = TRUE`
- **Base completa / estado atual** → `fact_assignment_snapshots` with `is_current = TRUE`
- **Nome social / preferred name** → `dim_employee.name` (not `dim_documentation.legal_name`)
- **Admissão / hire** → `dt_hired` (current contract start) vs `dt_original_hire` (first company contract)
- **Transferência interna** → `is_internal_transfer = TRUE` — person was already at the company before the current assignment started
- **Demissão / termination** → `is_terminated = TRUE`, `dt_terminated`; join `dim_event_definition` for `action_name` (voluntary/involuntary) and `reason_name` (finer label, EN + PT columns)
- **Hierarquia / reporting chain** → `dim_management_hierarchy` (`name_l0` … `name_l9`, L0 = CEO)
- **Assignment / vínculo** → `assignment_number`; one employee may have multiple after internal transfers
- **Validity window** → period where attributes are unchanged, tracked by `dt_valid_from` / `dt_valid_to` on SCD2 dimensions
- **OBT / base fotografias wide** → `metric_people.employee_snapshots` — pre-joined across compensation, demographics, and org

## Tables

| You need... | Use this table |
|-------------|----------------|
| Current employee identity (name, work email, education, generation) | `dw_employee_details.dim_employee` (`emp`) — current state, grain: one row per employee |
| Daily workforce history (tenure, headcount flags, org FKs) | `dw_employee_details.fact_assignment_snapshots` (`fact`) — grain: one row per assignment per `dt_reference`; scope with `is_current` or explicit date |
| Contact info history (phone, address, GitHub) | `dw_employee_details.dim_contact` — validity window; join via `sk_contact_version` from the fact |
| Legal documents (CPF, RG, legal name, marital status) | `dw_employee_details.dim_documentation` — validity window; join via `sk_documentation_version` |
| Emergency contacts | `dw_employee_details.dim_emergency_contact` — validity window; join via `sk_emergency_contact_version` |
| Termination reasons (action + reason, EN/PT) | `dw_employee_details.dim_event_definition` — current state; join via `sk_termination_event_definition` |
| Management chain up to CEO | `dw_employee_details.dim_management_hierarchy` — validity window; join via `sk_hierarchy_version` |
| Wide employee picture across domains | `metric_people.employee_snapshots` — official OBT joining compensation, demographics, org, and more |

**Main join identifiers:** `sk_employee` (preferred FK), `person_number` (business key), `assignment_number` (assignment-level key).

**Critical rules:**
- Always filter `fact_assignment_snapshots` by `is_current = TRUE`, `is_monthly_snapshot = TRUE`, or an explicit `dt_reference` — unscoped queries return every historical day per assignment.
- `sk_*_version` keys on the fact are point-in-time join keys, not permanent identifiers for an employee.
- Use `is_primary_assignment_for_snapshot = TRUE` when an employee has multiple assignments on the same date.
- `dim_management_hierarchy` exposes L0–L9 (L0 = CEO). Everyone in the same area shares the same L1 VP — filter by `name_l1`…`name_l9` without self-joins.
- The fact has no `year/month/day` partitions — expect full-table scans when unfiltered.

## Key Metrics

- **Active headcount** — `COUNT(DISTINCT person_number)` where `is_active = TRUE`, `is_current = TRUE`, `is_primary_assignment_for_snapshot = TRUE`
- **Tenure in company** — `days_tenure_in_company`, `months_tenure_in_company` (relative to `dt_reference`)
- **Tenure in assignment** — `days_tenure_in_assignment` (current role only)
- **Span of control** — `count_direct_report`, `count_indirect_report` (pre-computed on the fact)
- **Voluntary terminations** — `is_terminated = TRUE` + `dim_event_definition` filtered by `action_name` / `reason_name`
- **Managers vs ICs** — `is_manager`, `is_member_lt`

## Relationships with Other Entities

### Organization (N:1 per snapshot date)

- Cost center: `fact.sk_cost_center_version = dw_organization.dim_cost_center.sk_cost_center_version` — the fact carries the version SK valid on `dt_reference`; do not join on date range alone.
- Business unit: `fact.sk_business_unit = dw_organization.dim_business_unit.sk_business_unit`.
- Job catalog: `fact.sk_job_version` for versioned job on the snapshot; `dw_organization.dim_job` for current job definitions.

### Compensation (N:1 per snapshot date)

- `fact.sk_compensation_version` joins to `dw_compensation.fact_compensations` for salary and band on the same `dt_reference`.

### Demographics (separate schema)

- DE&I attributes are in `dw_demographics`. Use `metric_people.employee_snapshots` or join demographics facts when needed.

## Dos and Don'ts

**Do:**
- Start from `fact_assignment_snapshots` with `is_current = TRUE` for today's workforce state.
- Use `dim_employee.name` for communications; reserve `dim_documentation.legal_name` for compliance.
- Join versioned dimensions through the `sk_*_version` keys on the fact for the snapshot date in scope.
- Use `dt_original_hire` when tenure should credit prior company employment; `dt_hired` for seniority in the current contract only.
- Check `dim_event_definition` for exact `reason_name` / `action_name` values before filtering terminations.

**Don't:**
- Query `fact_assignment_snapshots` without a date scope — row counts inflate across every historical day.
- Treat `sk_contact_version` or `sk_hierarchy_version` as stable employee identifiers.
- Assume one row per employee without `is_primary_assignment_for_snapshot = TRUE` after internal transfers.
- Use `dim_employee` alone for point-in-time analysis — it is always overwritten to current state.
- Rely on work email history per assignment — only the most recent assignment's email is exposed in the current model.
- Expect incomplete hierarchy chains to L0 on active employees — gaps are data quality issues.
- Use deprecated People sources for new queries: `datalake_hr_system`, `datalake_employment`, `greenhouse` (v1), `enrich_employee`, `enrich_hr_system`, `enrich_pin`, or the legacy `dw_employee` DAG — prefer `datalake_pin_core_clean`, `datalake_people`, and `dw_*` schemas (see `people_domain.mdc`).

## Golden Queries

### Query 1 — Active headcount (current state)

```sql
SELECT
    COUNT(DISTINCT fact.person_number) AS active_headcount
FROM dw_employee_details.fact_assignment_snapshots AS fact
WHERE fact.is_current = TRUE
  AND fact.is_active = TRUE
  AND fact.is_primary_assignment_for_snapshot = TRUE
```

### Query 2 — Headcount at month-end (historical)

Monthly snapshot pattern (*base fotografias*). Replace the date with the target month-end `dt_reference`.

```sql
SELECT
    COUNT(DISTINCT fact.person_number) AS headcount
FROM dw_employee_details.fact_assignment_snapshots AS fact
WHERE fact.dt_reference = DATE '2025-12-31'
  AND fact.is_monthly_snapshot = TRUE
  AND fact.is_active = TRUE
  AND fact.is_primary_assignment_for_snapshot = TRUE
```

### Query 3 — Wide current workforce (all in-schema attributes)

Combines identity, contact, documentation, emergency contact, hierarchy, and termination context for active employees.

```sql
SELECT
    emp.name,
    emp.work_email,
    emp.generation,
    emp.highest_education_level,
    ct.full_phone_number,
    ct.address_city,
    ct.address_state,
    doc.marital_status,
    ec.contact_name AS emergency_contact_name,
    ec.contact_relationship AS emergency_contact_relationship,
    hier.name_l1 AS vp_name,
    hier.name_l2 AS director_name,
    hier.name_l3 AS manager_name,
    evt.action_name AS termination_action,
    evt.reason_name AS termination_reason,
    fact.days_tenure_in_company,
    fact.is_manager,
    fact.is_member_lt,
    fact.is_active,
    fact.is_terminated
FROM dw_employee_details.fact_assignment_snapshots AS fact
INNER JOIN dw_employee_details.dim_employee AS emp
    ON fact.sk_employee = emp.sk_employee
LEFT JOIN dw_employee_details.dim_contact AS ct
    ON fact.sk_contact_version = ct.sk_contact_version
LEFT JOIN dw_employee_details.dim_documentation AS doc
    ON fact.sk_documentation_version = doc.sk_documentation_version
LEFT JOIN dw_employee_details.dim_emergency_contact AS ec
    ON fact.sk_emergency_contact_version = ec.sk_emergency_contact_version
LEFT JOIN dw_employee_details.dim_management_hierarchy AS hier
    ON fact.sk_hierarchy_version = hier.sk_hierarchy_version
LEFT JOIN dw_employee_details.dim_event_definition AS evt
    ON fact.sk_termination_event_definition = evt.sk_event_definition
WHERE fact.is_current = TRUE
  AND fact.is_active = TRUE
  AND fact.is_primary_assignment_for_snapshot = TRUE
```

### Query 4 — Current workforce with org context

```sql
SELECT
    emp.name,
    emp.work_email,
    hier.name_l1 AS vp_name,
    hier.name_l2 AS director_name,
    hier.name_l3 AS manager_name,
    cc.cost_center_name,
    cc.vertical,
    bu.business_unit_name,
    fact.days_tenure_in_company,
    fact.is_manager
FROM dw_employee_details.fact_assignment_snapshots AS fact
INNER JOIN dw_employee_details.dim_employee AS emp
    ON fact.sk_employee = emp.sk_employee
LEFT JOIN dw_employee_details.dim_management_hierarchy AS hier
    ON fact.sk_hierarchy_version = hier.sk_hierarchy_version
LEFT JOIN dw_organization.dim_cost_center AS cc
    ON fact.sk_cost_center_version = cc.sk_cost_center_version
LEFT JOIN dw_organization.dim_business_unit AS bu
    ON fact.sk_business_unit = bu.sk_business_unit
WHERE fact.is_current = TRUE
  AND fact.is_active = TRUE
  AND fact.is_primary_assignment_for_snapshot = TRUE
```

### Query 5 — Voluntary terminations by manager chain

Check `dim_event_definition` for the exact `reason_name` before running in production.

```sql
SELECT
    DATE_TRUNC('month', fact.dt_terminated) AS termination_month,
    COUNT(DISTINCT fact.person_number) AS voluntary_terminations
FROM dw_employee_details.fact_assignment_snapshots AS fact
INNER JOIN dw_employee_details.dim_event_definition AS evt
    ON fact.sk_termination_event_definition = evt.sk_event_definition
INNER JOIN dw_employee_details.dim_management_hierarchy AS hier
    ON fact.sk_hierarchy_version = hier.sk_hierarchy_version
WHERE fact.is_terminated = TRUE
  AND YEAR(fact.dt_terminated) = 2026
  AND evt.reason_name = '<voluntary_reason_label>'
  AND (
      LOWER(hier.name_l1) LIKE LOWER('%<manager_name>%')
      OR LOWER(hier.name_l2) LIKE LOWER('%<manager_name>%')
      OR LOWER(hier.name_l3) LIKE LOWER('%<manager_name>%')
      OR LOWER(hier.name_l4) LIKE LOWER('%<manager_name>%')
  )
GROUP BY 1
ORDER BY 1
```

## DataHub catalog

- **Data Product:** [urn:li:dataProduct:employee-details](https://datahub.apps.data-prd.habitat.zone/dataProducts/urn%3Ali%3AdataProduct%3Aemployee-details)
- **Datasets:** listed in `dags/governance/datahub_business_context/datahub_entities/employee-details.datahub.yaml`
- **People Data Catalog:** [Employee Details](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/5473992727/Employee+Details)
- **Ad-hoc templates:** [Ad-hoc Analytics](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/5468979201/Ad-hoc+Analytics) (includes `metric_people.employee_snapshots` patterns)
