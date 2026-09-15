# Organization

## Ownership

**Data Owner:**
- pedro.prates@quintoandar.com.br

**Data Steward:**
- isabella.araujo@quintoandar.com.br
- gabriel.berger@quintoandar.com.br

## Overview

Organization (`dw_organization`) is the People DW schema for organizational reference data: cost centers and teams (with Codex attributes), business units, and the public job catalog. These dimensions classify headcount and power joins from `dw_employee_details.fact_assignment_snapshots` and `metric_people.employee_snapshots`.

**Sources:** PIN (HR org structures, jobs, core cost center attributes) and SAP/Codex (financial and planning taxonomy integrated into cost centers).

**SLA:** D-1, available by 08:00 BRT. DAG: `bietlejuice.dw_organization`.

**Temporal model:** `dim_cost_center` is SCD Type 2 (validity windows). `dim_business_unit` and `dim_job` are current-state catalogs only.

**Out of scope:** job compensation bands → `dw_compensation`; individual employee records → `dw_employee_details`.

For the full business-facing schema guide, see `dags/people/dw_organization/docs/dw_organization.md`.

## Known Limitations

PIN went live on **2024-03-01**; cost center, business unit, job, and employee-to-organization attributes may be inconsistent before that date because the source system was not yet live.

- For every organizational metric or descriptive statistic — including `MIN`, `MAX`, `AVG`, `SUM`, counts, median, percentiles, rates, distributions, trends, and period comparisons — use only records on or after `2024-03-01`. The requested analysis period must start on or after this date; never mix pre-go-live records into an aggregate.
- If a question requires any pre-go-live period, explain the PIN source-system limitation and direct the user to **People Insights** or **Enterprise Engineering** instead of approximating the result.

## TARS pilot scope (restricted audience)

**Status:** pilot — validate in Trino before broader publication. Access is limited to users who already have People analytical authorization.

**Trino catalog:** `delta` — all three tables in this schema are in the pilot. No salary or compensation bands (`dw_compensation` is out of scope).

| Table | What it contains |
|-------|------------------|
| `dim_cost_center` | Teams, Codex taxonomy (vertical, chapter, squad), HRBP name/email, cost-center owner names. **PII** (HRBPs and L owners). |
| `dim_business_unit` | Business unit code and name only. Reference data, no PII. |
| `dim_job` | Job catalog: name, family, career track. No compensation bands. |

## Related Domain Entities

- `employee_details.md` — daily assignment snapshots and employee identity; join on `sk_cost_center_version`, `sk_business_unit`, and `sk_job_version`.
- `people_public.md` — **preferred** public active-workforce DW (`dw_people`) for current org placement, company-wide management hierarchy, and P&T team formation (P&T only: wide `dim_product_tech_team`; other areas use cost center from this entity).

## Glossary and Synonyms

- **Cost center / CC / centro de custo** → `dw_organization.dim_cost_center`; financial and HR org unit; grain is one row per **version** (SCD2)
- **Team / squad / time** → `dim_cost_center.team` — organizational team label (distinct from cost center name)
- **Business unit / BU / unidade de negócio / filial** → `dim_business_unit` — legal-affiliation branch within a country; join on `sk_business_unit`
- **Job / role / position / job title / cargo / função** → `dim_job` — public job catalog (name, family, career track); no salary bands
- **Job family / job function family** → `dim_job.job_family`
- **Career track / contribution level** → `dim_job.career_track` (catalog only; compensation bands are in `dw_compensation`)
- **HR Business Partner / HRBP / People Partner** → `hrbp_name`, `hrbp_work_email`, `hrbp_person_number` on the cost center version valid for the period
- **Codex / financial taxonomy / planning taxonomy** → SAP/Codex attributes integrated into `dim_cost_center`; [official spreadsheet](https://docs.google.com/spreadsheets/d/1-85ApczFAw1B7ZfU59WJ_qwTaYGVmkw8efSa9K9umeA/edit?usp=sharing)
- **Vertical / business vertical / tribe** → `dim_cost_center.vertical` (derived from `structure`)
- **Chapter / guild / competency chapter** → `dim_cost_center.chapter` — variable attribute (can trigger new SCD2 version)
- **Line / product line** → `dim_cost_center.line`
- **Structure / org structure** → `dim_cost_center.structure` — fixed attribute derived from `cost_center_code`
- **Brand / product / business (Codex dimensions)** → `brand`, `product`, `business` on `dim_cost_center` — fixed within the same `cost_center_code`
- **Headcount type / capacity vs overhead** → `dim_cost_center.headcount_type` (e.g. Capacity, Overhead)
- **Cost center owner / unit leadership / L owner** → `owner_l1_name`, `owner_l2_name`, `owner_l3_name` — leaders of the **cost center as an org unit** (all employees in the CC share the same owners; not personal managers in `dim_management_hierarchy`)
- **Fixed attributes** → `structure`, `team`, `business`, `product`, `brand` — stable while `cost_center_code` unchanged
- **Variable attributes** → `chapter`, `line`, `owner_l1_name`, `owner_l2_name`, `owner_l3_name`, `headcount_type` — changes create new SCD2 versions
- **Cost center code / CC code** → `cost_center_code` — stable business key across PIN and Codex
- **Cost center version / SCD2 surrogate key** → `sk_cost_center_version` — use when joining from `fact_assignment_snapshots` (point-in-time for `dt_reference`)
- **Current cost center row / present-day catalog** → `dim_cost_center` with `is_current = TRUE` when browsing standalone (do not add on top of SK join from the fact)
- **Active cost center** → `is_active = TRUE`
- **Validity window / version period** → `dt_valid_from` / `dt_valid_to` on `dim_cost_center`; `9999-12-31` on `dt_valid_to` means current version
- **Headcount by vertical / BU / cost center** → join `fact_assignment_snapshots` to these dimensions on `sk_cost_center_version`, `sk_business_unit`, `sk_job_version`

## Tables

| You need... | Use this table |
|-------------|----------------|
| Cost center/team attributes and history | `dw_organization.dim_cost_center` (`cc`) — **TARS pilot**; grain: one row per cost center version (SCD2); filter `is_current = TRUE` unless time-traveling |
| Business unit catalog | `dw_organization.dim_business_unit` (`bu`) — **TARS pilot**; grain: one row per active BU; join on `sk_business_unit` |
| Job definitions (family, career track) | `dw_organization.dim_job` (`job`) — **TARS pilot**; grain: one row per active job; join on `sk_job` |
| Employee + org context | `dw_employee_details.fact_assignment_snapshots` joined to the dimensions above — see `employee_details.md` |

**Main join identifiers:** `sk_cost_center_version` (versioned FK), `cost_center_code` (stable business key), `sk_business_unit`, `sk_job`.

**Critical rules:**
- **TARS pilot (Trino `delta`):** all three tables in this schema are in scope. No salary data. Restricted audience until pilot sign-off.
- Joining from `fact_assignment_snapshots`: use `fact.sk_cost_center_version = cc.sk_cost_center_version` only — the fact already carries the version SK for `dt_reference`; do not add `cc.is_current` on top of the SK join.
- Querying `dim_cost_center` standalone (catalog browse): filter `is_current = TRUE` or a `dt_valid_from` / `dt_valid_to` window — otherwise SCD2 history duplicates rows.
- `owner_l1_name` / `owner_l2_name` / `owner_l3_name` describe the cost center unit's leadership — all employees in the same cost center share the same L owners, but may have different personal L1/L2/L3 in `dim_management_hierarchy`.
- Job compensation bands are in `dw_compensation`, not in `dim_job`.
- When an employee transfers business units, PIN creates a new assignment — do not expect BU changes on the same `assignment_number`.
- **Data floor: 2024-03-01 (PIN go-live).** All organizational metrics and descriptive statistics (`MIN`, `MAX`, `AVG`, counts, percentiles, rates, distributions, and trends) must use only records from this date forward. See Known Limitations.

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
- Include records before **2024-03-01** (PIN go-live) in any organizational metric or descriptive statistic, including `MIN`, `MAX`, `AVG`, counts, percentiles, rates, distributions, or trends; see Known Limitations.

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

## DataHub catalog

- **Data Product:** [urn:li:dataProduct:organization](https://datahub.apps.data-prd.habitat.zone/dataProducts/urn%3Ali%3AdataProduct%3Aorganization)
- **Datasets (TARS pilot):** `dw_organization.dim_cost_center`, `dim_business_unit`, `dim_job` — published to DataHub by CI from this Markdown (`organization.md` → `organization`).
- **People Data Catalog:** [People Data Catalog](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/5474320386/People+Data+Catalog)
- **Codex reference:** [Codex spreadsheet](https://docs.google.com/spreadsheets/d/1-85ApczFAw1B7ZfU59WJ_qwTaYGVmkw8efSa9K9umeA/edit?usp=sharing)
