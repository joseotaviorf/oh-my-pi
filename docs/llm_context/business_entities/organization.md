# Organization

## Overview

Organization (`dw_organization`) is the People DW schema for organizational reference data: cost centers and teams (with Codex attributes), business units, and the public job catalog. These dimensions classify headcount and power joins from `dw_employee_details.fact_assignment_snapshots` and `metric_people.employee_snapshots`.

**Sources:** PIN (HR org structures, jobs, core cost center attributes) and SAP/Codex (financial and planning taxonomy integrated into cost centers).

**SLA:** D-1, available by 08:00 BRT. DAG: `bietlejuice.dw_organization`.

**Temporal model:** `dim_cost_center` is SCD Type 2 (validity windows). `dim_business_unit` and `dim_job` are current-state catalogs only.

**Out of scope:** job compensation bands → `dw_compensation`; individual employee records → `dw_employee_details`.

For the full business-facing schema guide, see `dags/people/dw_organization/docs/dw_organization.md`.

## Related Business Entities

- `employee_details.md` — daily assignment snapshots and employee identity; join on `sk_cost_center_version`, `sk_business_unit`, and `sk_job_version`.

## Glossary and Synonyms

- **Cost center / centro de custo / time / team** → `dw_organization.dim_cost_center`
- **Business unit / unidade de negócio / filial** → `dw_organization.dim_business_unit` — local branch within a country legal entity; legal affiliation for assignments
- **Job / cargo / função** → `dw_organization.dim_job` — public catalog with job family and career track
- **Codex** → SAP/Codex-sourced financial and taxonomy attributes on `dim_cost_center`; [official spreadsheet](https://docs.google.com/spreadsheets/d/1-85ApczFAw1B7ZfU59WJ_qwTaYGVmkw8efSa9K9umeA/edit?usp=sharing)
- **HRBP** → `hrbp_name`, `hrbp_work_email`, `hrbp_person_number` on the cost center version active for the period
- **Vertical / chapter / line** → variable classification columns on `dim_cost_center`
- **Fixed attributes (from cost center code)** → `structure`, `team`, `business`, `product`, `brand` — stable within the same `cost_center_code`
- **Variable attributes (trigger new SCD2 version)** → `chapter`, `line`, `owner_l1_name`, `owner_l2_name`, `owner_l3_name`, `headcount_type`
- **L owner (cost center)** → `owner_l1_name`…`owner_l3_name` — managers of the cost center as an org unit (not each employee's personal reporting chain in `dim_management_hierarchy`)
- **Validity window** → `dt_valid_from` / `dt_valid_to` on `dim_cost_center`; `is_current = TRUE` marks today's active version

## Tables

| You need... | Use this table |
|-------------|----------------|
| Cost center/team attributes and history | `dw_organization.dim_cost_center` (`cc`) — grain: one row per cost center version (SCD2); filter `is_current = TRUE` unless time-traveling |
| Business unit catalog | `dw_organization.dim_business_unit` (`bu`) — grain: one row per active BU; join on `sk_business_unit` |
| Job definitions (family, career track) | `dw_organization.dim_job` (`job`) — grain: one row per active job; join on `sk_job` |
| Employee + org context | `dw_employee_details.fact_assignment_snapshots` joined to the dimensions above |

**Main join identifiers:** `sk_cost_center_version` (versioned FK), `cost_center_code` (stable business key), `sk_business_unit`, `sk_job`.

**Critical rules:**
- Joining from `fact_assignment_snapshots`: use `fact.sk_cost_center_version = cc.sk_cost_center_version` only — the fact already carries the version SK for `dt_reference`; do not add `cc.is_current` on top of the SK join.
- Querying `dim_cost_center` standalone (catalog browse): filter `is_current = TRUE` or a `dt_valid_from` / `dt_valid_to` window — otherwise SCD2 history duplicates rows.
- `owner_l1_name` / `owner_l2_name` / `owner_l3_name` describe the cost center unit's leadership — all employees in the same cost center share the same L owners, but may have different personal L1/L2/L3 in `dim_management_hierarchy`.
- Job compensation bands are in `dw_compensation`, not in `dim_job`.
- When an employee transfers business units, PIN creates a new assignment — do not expect BU changes on the same `assignment_number`.

## Key Metrics

- **Headcount by vertical** — join fact to `dim_cost_center` on `sk_cost_center_version`, group by `vertical`
- **Active cost centers** — `COUNT(*)` where `is_active = TRUE` and `is_current = TRUE`
- **Cost centers by HRBP** — group `dim_cost_center` by `hrbp_name` with `is_current = TRUE`
- **Employees per business unit** — join fact to `dim_business_unit`, count distinct `person_number`

## Relationships with Other Entities

### Employee Details (1:N — one cost center version maps to many snapshots)

- Join from fact: `fact.sk_cost_center_version = cc.sk_cost_center_version` — the fact already carries the version SK valid on `dt_reference`.
- Standalone cost center catalog (current): filter `dim_cost_center` with `is_current = TRUE`.
- Business unit: `fact.sk_business_unit = bu.sk_business_unit`.

### Compensation (via job, not direct)

- Pay bands and salary history are in `dw_compensation`; `dim_job` holds only the public job catalog.

## Dos and Don'ts

**Do:**
- When browsing `dim_cost_center` alone, add `is_current = TRUE` for today's catalog or filter `dt_valid_from` / `dt_valid_to` for a historical date.
- When joining from `fact_assignment_snapshots`, match on `sk_cost_center_version` only.
- Use `cost_center_code` as the stable business key across PIN and Codex.
- Attribute HRBP partnership to the cost center version valid on the analysis date.

**Don't:**
- Query `dim_cost_center` standalone without `is_current` or a validity window — SCD2 history inflates counts.
- Add `cc.is_current = TRUE` when joining from the fact via `sk_cost_center_version` — the SK already identifies the correct version.
- Confuse cost-center L owners with employee hierarchy levels in `dim_management_hierarchy`.
- Look for salary ranges in `dim_job` — use `dw_compensation`.
- Assume fixed attributes (`structure`, `brand`, etc.) change independently of the cost center code — they are derived from the code and stable within it.
- Use deprecated People sources for new queries: `datalake_hr_system`, `datalake_employment`, `greenhouse` (v1), `enrich_employee`, `enrich_hr_system`, `enrich_pin`, or the legacy `dw_employee` DAG — prefer `datalake_pin_core_clean`, `datalake_people`, and `dw_*` schemas (see `people_domain.mdc`).

## Golden Queries

### Query 1 — Active cost centers by vertical

```sql
SELECT
    cc.cost_center_code,
    cc.cost_center_name,
    cc.team,
    cc.chapter,
    cc.vertical,
    cc.headcount_type,
    cc.is_active
FROM dw_organization.dim_cost_center AS cc
WHERE cc.vertical = 'Tech'
  AND cc.is_current = TRUE
ORDER BY cc.cost_center_name
```

### Query 2 — Headcount by business unit (current)

```sql
SELECT
    bu.business_unit_name,
    COUNT(DISTINCT fact.person_number) AS active_headcount
FROM dw_employee_details.fact_assignment_snapshots AS fact
INNER JOIN dw_organization.dim_business_unit AS bu
    ON fact.sk_business_unit = bu.sk_business_unit
WHERE fact.is_current = TRUE
  AND fact.is_active = TRUE
  AND fact.is_primary_assignment_for_snapshot = TRUE
GROUP BY 1
ORDER BY 2 DESC
```

### Query 3 — Employees with current cost center attributes

```sql
SELECT
    fact.sk_employee,
    fact.person_number,
    cc.cost_center_name,
    cc.vertical,
    cc.headcount_type,
    cc.hrbp_name,
    cc.owner_l1_name,
    bu.business_unit_name
FROM dw_employee_details.fact_assignment_snapshots AS fact
LEFT JOIN dw_organization.dim_cost_center AS cc
    ON fact.sk_cost_center_version = cc.sk_cost_center_version
LEFT JOIN dw_organization.dim_business_unit AS bu
    ON fact.sk_business_unit = bu.sk_business_unit
WHERE fact.is_current = TRUE
  AND fact.is_active = TRUE
  AND fact.is_primary_assignment_for_snapshot = TRUE
```

## DataHub catalog

- **Data Product:** [urn:li:dataProduct:organization](https://datahub.apps.data-prd.habitat.zone/dataProducts/urn%3Ali%3AdataProduct%3Aorganization)
- **Datasets:** listed in `dags/governance/datahub_business_context/datahub_entities/organization.datahub.yaml`
- **People Data Catalog:** [People Data Catalog](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/4635951235/People+Data+Catalog)
- **Codex reference:** [Codex spreadsheet](https://docs.google.com/spreadsheets/d/1-85ApczFAw1B7ZfU59WJ_qwTaYGVmkw8efSa9K9umeA/edit?usp=sharing)
