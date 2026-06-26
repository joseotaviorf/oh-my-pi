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

## TARS pilot scope (restricted audience)

**Status:** pilot — validate in Trino before broader publication. Access is limited to users who already have People analytical authorization.

**Trino catalog:** `delta` — only the tables below are registered for this pilot. No salary or compensation data in any of them (`dw_compensation` is out of scope).

| Table | What it contains |
|-------|------------------|
| `fact_assignment_snapshots` | Headcount, tenure, status flags, span of control, hire/termination dates. No PII columns on the fact itself. |
| `dim_employee` | Preferred name, work email, birth date, education, generation. **PII** (LGPD: birth date). |
| `dim_management_hierarchy` | Reporting chain L0–L9 (CEO → employee) with manager name and work email per level. **PII** (managers). |
| `dim_event_definition` | HR movement catalog (action + reason labels in PT/EN). No individual employee data. |

Join to `organization.md` tables for cost center, BU, and job context (`sk_cost_center_version`, `sk_business_unit`, `sk_job_version` on the fact).

**Not in this pilot (Databricks-only):** `dim_contact`, `dim_documentation`, `dim_emergency_contact`, `metric_people.employee_snapshots`, `dw_compensation`, `dw_demographics`.

## Related Business Entities

- `organization.md` — cost center, business unit, and job reference dimensions joined via `sk_cost_center_version`, `sk_business_unit`, and `sk_job_version` on the fact.
- `org_chart.md` — lightweight current org chart for active employees (`datalake_people_public.org_chart`) when DW joins are not needed.

## Glossary and Synonyms

- **Employee / worker / workforce member / FTE / contractor** (colaborador, funcionário) → `dim_employee` / `fact_assignment_snapshots`; contractors and full-time included when they have a valid assignment
- **Headcount / active workforce / FTE count / quadro** → `COUNT(DISTINCT person_number)` on `fact_assignment_snapshots` where `is_active = TRUE`, `is_current = TRUE`, `is_primary_assignment_for_snapshot = TRUE`
- **Monthly snapshot / month-end headcount / base fotografias** → `fact_assignment_snapshots` with `is_monthly_snapshot = TRUE` and explicit `dt_reference` (typically month-end)
- **Current state / latest snapshot / as-of today / base completa** → `fact_assignment_snapshots` with `is_current = TRUE`
- **Snapshot date / as-of date / reference date** → `dt_reference` on the fact (one row per assignment per calendar day)
- **Person number / employee ID / HR ID / matrícula** → `person_number` — stable business key across assignments
- **Assignment / employment record / vínculo** → `assignment_number`; one person may have multiple after internal transfers
- **Primary assignment** → `is_primary_assignment_for_snapshot = TRUE` when multiple assignments overlap on the same date
- **Preferred name / display name / social name / nome social** → `dim_employee.name` (not `dim_documentation.legal_name`, Databricks-only)
- **Work email / corporate email** → `dim_employee.work_email`
- **Birth date / date of birth** → `dim_employee` (PII; LGPD-sensitive)
- **Education level / highest education / generation** → `dim_employee.highest_education_level`, `dim_employee.generation`
- **Hire date / start date / assignment start / admissão** → `dt_hired` (current assignment only)
- **Original hire date / company start date / first hire** → `dt_original_hire` (tenure crediting full company history)
- **Tenure / time in company / time in role** → `days_tenure_in_company`, `months_tenure_in_company`, `days_tenure_in_assignment` on the fact (relative to `dt_reference`)
- **Termination / separation / offboarding / exit / turnover / demissão** → `is_terminated = TRUE`, `dt_terminated`; join `dim_event_definition` for labels
- **Voluntary termination / resignation / quit / pedido de demissão** → filter `dim_event_definition` (`action_name`, `reason_name` in EN; `action_name_ptb`, `reason_name_ptb` in PT)
- **Involuntary termination / dismissal / firing** → `dim_event_definition` labels; recorded only **after** employee communication — cannot predict in advance
- **Layoff / reorganization exit / restructuring** → `is_reorganization_termination = TRUE` on the fact
- **Scheduled voluntary exit / future termination / desligamento futuro** → `dt_terminated` in the **future** while still active — **voluntary only**; involuntary never appears with a future date
- **HR movement / lifecycle event / action & reason** → `dim_event_definition`; join via `sk_termination_event_definition` on the fact
- **Reporting chain / management hierarchy / org chart / hierarquia** → `dim_management_hierarchy` (`name_l0` … `name_l9`, `assignment_number_l0` … `assignment_number_l9`)
- **CEO / L0 / top-level manager** → `name_l0`, `email_l0` (Layer 0)
- **VP / director / manager (by level)** → `name_l1` (VP), `name_l2` (director), `name_l3` (manager), etc.
- **Direct manager / line manager** → immediate level in hierarchy (lowest non-empty `name_l*` for the employee's chain)
- **Span of control / direct reports / team size** → `count_direct_report` on the fact
- **Indirect reports** → `count_indirect_report`; **total reports** → `count_total_report`
- **Manager / people manager** → `is_manager = TRUE`
- **Leadership Team / LT / liderança** → `is_member_lt = TRUE` (band 10+ or EXEC)
- **Executive Team / ET** → `is_member_et = TRUE` (L0/L1 in hierarchy and band 14+)
- **Internal transfer / mobility / transferência interna** → `is_internal_transfer = TRUE`
- **Validity window / SCD2 version** → `dt_valid_from` / `dt_valid_to` on hierarchy (and other SCD2 dims); `is_current = TRUE` for latest hierarchy version
- **OBT / wide employee snapshot** (not in TARS pilot) → `metric_people.employee_snapshots`

## Tables

| You need... | Use this table |
|-------------|----------------|
| Current employee identity (name, work email, education, generation) | `dw_employee_details.dim_employee` (`emp`) — **TARS pilot**; current state, grain: one row per employee |
| Daily workforce history (tenure, headcount flags, org FKs) | `dw_employee_details.fact_assignment_snapshots` (`fact`) — **TARS pilot**; grain: one row per assignment per `dt_reference`; scope with `is_current` or explicit date |
| Contact info history (phone, address, GitHub) | `dw_employee_details.dim_contact` — **not in TARS pilot** (Databricks-only); validity window; join via `sk_contact_version` from the fact |
| Legal documents (CPF, RG, legal name, marital status) | `dw_employee_details.dim_documentation` — **not in TARS pilot** (Databricks-only); validity window; join via `sk_documentation_version` |
| Emergency contacts | `dw_employee_details.dim_emergency_contact` — **not in TARS pilot** (Databricks-only); validity window; join via `sk_emergency_contact_version` |
| Termination reasons (action + reason, EN/PT) | `dw_employee_details.dim_event_definition` — **TARS pilot**; current state; join via `sk_termination_event_definition` |
| Management chain up to CEO | `dw_employee_details.dim_management_hierarchy` — **TARS pilot**; validity window; join via `sk_hierarchy_version` |
| Wide employee picture across domains | `metric_people.employee_snapshots` — **not in TARS pilot**; official OBT joining compensation, demographics, org, and more |

**Main join identifiers:** `sk_employee` (preferred FK), `person_number` (business key), `assignment_number` (assignment-level key).

**Critical rules:**
- **TARS pilot (Trino `delta`):** only `fact_assignment_snapshots`, `dim_employee`, `dim_event_definition`, and `dim_management_hierarchy` from this schema. No salary data. Restricted audience until pilot sign-off.
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
- Treat future `dt_terminated` as scheduled **voluntary** exits only — not as a signal of impending involuntary dismissal.

**Don't:**
- Query `fact_assignment_snapshots` without a date scope — row counts inflate across every historical day.
- Use `dt_terminated` or `dim_event_definition` to predict **involuntary** layoffs — involuntary termination dates are recorded only after communication.
- Treat `sk_contact_version` or `sk_hierarchy_version` as stable employee identifiers.
- Assume one row per employee without `is_primary_assignment_for_snapshot = TRUE` after internal transfers.
- Use `dim_employee` alone for point-in-time analysis — it is always overwritten to current state.
- Rely on work email history per assignment — only the most recent assignment's email is exposed in the current model.
- Expect incomplete hierarchy chains to L0 on active employees — gaps are data quality issues.
- Use deprecated People sources for new queries: `datalake_hr_system`, `datalake_employment`, `greenhouse` (v1), `enrich_employee`, `enrich_hr_system`, `enrich_pin`, or the legacy `dw_employee` DAG — prefer `datalake_pin_core_clean`, `datalake_people`, and `dw_*` schemas (see `people_domain.mdc`).

## Golden Queries

### Query 1 — Wide current workforce (TARS pilot)

Identity, hierarchy, and termination context for active employees. Uses only tables in the TARS pilot (no contact/documentation dimensions).

```sql
SELECT
    emp.name,
    emp.work_email,
    emp.generation,
    emp.highest_education_level,
    hier.name_l1 AS vp_name,
    hier.name_l2 AS director_name,
    hier.name_l3 AS manager_name,
    evt.action_name AS termination_action,
    evt.reason_name AS termination_reason,
    fact.days_tenure_in_company,
    fact.is_manager,
    fact.is_leadership_team_member,
    fact.is_active,
    fact.dt_terminated
FROM dw_employee_details.fact_assignment_snapshots AS fact
INNER JOIN dw_employee_details.dim_employee AS emp
    ON fact.sk_employee = emp.sk_employee
LEFT JOIN dw_employee_details.dim_management_hierarchy AS hier
    ON fact.sk_hierarchy_version = hier.sk_hierarchy_version
LEFT JOIN dw_employee_details.dim_event_definition AS evt
    ON fact.sk_termination_event_definition = evt.sk_event_definition
WHERE fact.is_current = TRUE
  AND fact.is_active = TRUE
  AND fact.is_primary_assignment_for_snapshot = TRUE
```

## DataHub catalog

- **Data Product:** [urn:li:dataProduct:employee-details](https://datahub.apps.data-prd.habitat.zone/dataProducts/urn%3Ali%3AdataProduct%3Aemployee-details)
- **Datasets (TARS pilot):** `dw_employee_details.fact_assignment_snapshots`, `dim_employee`, `dim_management_hierarchy`, `dim_event_definition` — published to DataHub by CI from this Markdown (`employee_details.md` → `employee-details`).
- **People Data Catalog:** [Employee Details](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/5473992727/Employee+Details)
