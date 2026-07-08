# Org Chart

## Overview

`datalake_people_public.org_chart` is the public, denormalized organizational chart for **active employees and contractors** at QuintoAndar. Each row combines identity (name, work email), direct manager, job title, cost center, Codex taxonomy (business, product, vertical, directorate), and Product & Technology team-formation attributes (line, chapter, squad teams).

**Population:** active assignments only (`assignment_status_type = 'ACTIVE'`; types E and C). Terminated and inactive workers are excluded at load time.

**Source:** PIN (Oracle HCM) via `datalake_people.identifier_mapping` and `datalake_pin.movement_details`, enriched with cost-center org attributes from PIN Organization DFF (`datalake_hr_system_clean.organizations`) and GSheets Product & Tech team formation.

**SLA:** D-1 with the `enrich_people_public` DAG. Grain: **one row per active `assignment_number`**.

**Out of scope:** employment history, terminated employees, compensation, performance, and SCD2 validity windows — use `employee_details.md` (`dw_employee_details`) or `datalake_people.identifier_mapping` instead.

## TARS pilot scope (restricted audience)

**Status:** pilot — validate in Trino before broader publication. Access is limited to users who already have People analytical authorization.

**Trino catalog:** `delta` — table `datalake_people_public.org_chart`.

| Table | What it contains |
|-------|------------------|
| `datalake_people_public.org_chart` | Active workforce org chart: name, email, manager, job, cost center, Codex dimensions, P&T team formation. **PII** (employee and manager names/emails). |

This table is a **lighter alternative** to joining `dw_employee_details` + `dw_organization` when the question is only about the **current** org structure of active employees.

## Related Business Entities

- `employee_details.md` — full employee identity, daily snapshots, management hierarchy (L0–L9), and terminated workforce.
- `organization.md` — SCD2 cost centers, business units, and job catalog in `dw_organization`.

## Glossary and Synonyms

- **Org chart / organograma / estrutura organizacional** → `datalake_people_public.org_chart`
- **Active employee / colaborador ativo / quadro atual** → all rows in this table (pre-filtered at load)
- **Manager / gestor / líder direto** → `manager_name`, `manager_email`
- **Assignment number / matrícula** → `assignment_number` — unique grain key
- **Job title / cargo / função** → `assignment_name`
- **Job class / position class / nível de cargo** → `job_class` (job family from PIN)
- **Cost center / centro de custo** → `cost_center_name`
- **Business unit / BU / filial** → `business_unit_name`
- **Codex taxonomy / planejamento financeiro** → `business`, `product`, `vertical`, `vice_presidency`, `directorate`, `subdirectorate`
- **Vertical / vertical de negócio** → `vertical` — PIN Organization DFF values `Ops`, `Tech`, or `Corp`; NULL when unmatched or blank
- **Product & Tech team formation / time P&T** → `line`, `chapter`, `line_leader`, `team_leader`, `product_and_tech_team_1` … `product_and_tech_team_10`
- **Hire date / data de admissão** → `dt_hired`

## Tables

| You need... | Use this table |
|-------------|----------------|
| Current org chart for active employees (name, manager, job, area) | `datalake_people_public.org_chart` (`oc`) — grain: one row per active `assignment_number`; no extra `is_active` filter needed |
| Manager and employee contact for active workforce | `datalake_people_public.org_chart` — `work_email`, `manager_name`, `manager_email` |
| Codex / financial taxonomy per active employee | `datalake_people_public.org_chart` — `business`, `product`, `vertical`, `directorate`, `subdirectorate` |
| Product & Technology squad structure | `datalake_people_public.org_chart` — `line`, `chapter`, `product_and_tech_team_*` (NULL outside P&T) |
| Historical headcount or terminated employees | `dw_employee_details.fact_assignment_snapshots` — see `employee_details.md` |
| Full employment history (all statuses) | `datalake_people.identifier_mapping` |

**Critical rules:**
- Table contains **only active** employees — do not add `is_active = TRUE` or `assignment_status_type = 'ACTIVE'` unless joining from another table.
- For terminated or historical analysis, use `employee_details.md` or `identifier_mapping`; this table will not return offboarded workers.
- `assignment_number` is unique — one row per person-assignment; use it as the join key to other People enrich tables.
- P&T columns (`line`, `chapter`, teams) are populated only for employees matched in the GSheets team-formation source; expect NULL elsewhere.
- **DataHub CI:** concrete table name only — `datalake_people_public.org_chart`.

## Key Metrics

- **Active headcount** — `COUNT(*)` or `COUNT(DISTINCT assignment_number)` on `datalake_people_public.org_chart`
- **Headcount by vertical** — `COUNT(*)` grouped by `vertical`
- **Headcount by directorate** — `COUNT(*)` grouped by `directorate`
- **Managers with direct reports** — `COUNT(DISTINCT manager_email)` where `manager_email IS NOT NULL`
- **P&T population** — `COUNT(*)` where `line IS NOT NULL` or `chapter IS NOT NULL`
- **New hires (recent)** — filter `dt_hired` for a rolling window

## Relationships with Other Entities

### Employee Details (subset — current active only)

- `org_chart.assignment_number` aligns with `dw_employee_details.fact_assignment_snapshots.assignment_number` for the current active snapshot (`is_current_for_employee = TRUE`, `is_active = TRUE`).
- For hierarchy levels L0–L9 (CEO chain), use `dw_employee_details.dim_management_hierarchy` — `org_chart` exposes only the **direct** manager.

### Organization (denormalized attributes)

- Cost center name and Codex dimensions on `org_chart` mirror attributes from `dw_organization.dim_cost_center` but without SCD2 history — values reflect the employee's **current** assignment only.
- For versioned cost center history, join `fact_assignment_snapshots` to `dim_cost_center` per `organization.md`.

### Identifier Mapping (1:1 for active rows)

- `datalake_people.identifier_mapping.assignment_number = org_chart.assignment_number` for active, latest assignments.
- `identifier_mapping` retains inactive and terminated rows; `org_chart` does not.

## Dos and Don'ts

**Do:**
- Use `datalake_people_public.org_chart` for quick questions about **who works where today** among active employees.
- Join on `assignment_number` when linking to other People enrich tables.
- Use `manager_email` or `manager_name` for direct-manager lookups.
- Fall back to `employee_details.md` when the question mentions termination, historical dates, or monthly snapshots.

**Don't:**
- Filter `is_active = TRUE` or `assignment_status_type = 'ACTIVE'` — the table is already scoped to active assignments.
- Use this table for terminated-employee analysis or month-end headcount history — rows disappear after offboarding.
- Confuse `manager_name` (direct manager) with cost-center owners (`owner_l1_name` in `dw_organization.dim_cost_center`).
- Expect P&T team columns for non-Product & Technology areas — they come from a GSheets supplement and are often NULL.
- Use deprecated People sources (`datalake_hr_system`, `datalake_employment`, `enrich_employee`) for new queries.

## Golden Queries

### Query 1 — Active employees by vertical and directorate

```sql
SELECT
    oc.vertical,
    oc.directorate,
    COUNT(*) AS active_headcount
FROM datalake_people_public.org_chart AS oc
GROUP BY 1, 2
ORDER BY 3 DESC
```

### Query 2 — Employee with manager and Codex context

```sql
SELECT
    oc.assignment_number,
    oc.name,
    oc.work_email,
    oc.assignment_name,
    oc.manager_name,
    oc.manager_email,
    oc.cost_center_name,
    oc.vertical,
    oc.directorate,
    oc.line,
    oc.chapter
FROM datalake_people_public.org_chart AS oc
WHERE LOWER(oc.work_email) = LOWER('name.surname@quintoandar.com.br')
```

### Query 3 — Product & Technology team roster

```sql
SELECT
    oc.name,
    oc.work_email,
    oc.line,
    oc.chapter,
    oc.product_and_tech_team_1,
    oc.team_leader
FROM datalake_people_public.org_chart AS oc
WHERE oc.line IS NOT NULL
ORDER BY oc.line, oc.chapter, oc.name
```

## DataHub catalog

> Added automatically by the agent after Step 7 — do not fill in manually.
