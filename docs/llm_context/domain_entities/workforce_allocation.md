# Workforce Allocation

## Ownership

**Data Owner:**
- pedro.prates@quintoandar.com.br

**Data Steward:**
- isabella.araujo@quintoandar.com.br

---

## Overview

- **Objective:** Model how employees are allocated across user-defined groups and tags for quarterly planning, scenario simulation, and org-wide FTE views — replacing ad-hoc spreadsheet workflows that drift over time.
- **Asset status / lifecycle:** **Prototype** (Allocation Tool on Base44). Production rollout is a separate decision after validation; treat the export contract and schema as unstable. Base44 writes a **full daily snapshot** to S3; the People pipeline loads it into the lake and publishes `dw_workforce_allocation.fact_workforce_allocations` for Trino/TARS, Superset, and ad-hoc reports.
- **Typical actions / events:** Admins and ET/LT create groups and tags, link employees to tags, or soft-deactivate them (`inactive` status). Allocations absent from a snapshot are treated as removed at source.
- **Common metrics:** Allocated FTE by group or tag, active allocation counts, tag completeness (coverage vs expected roster), historical allocation states.
- **Source systems:** Allocation Tool (Base44) → S3 export → People pipeline → `dw_workforce_allocation.fact_workforce_allocations` (Trino/TARS). Upstream enrich (`datalake_people.allocation_history`) is **technical-team only** — not a TARS or business consumer entry point. Employee records in the tool are **read-only**, seeded from PIN (D-1); sync is one-directional (PIN → S3 → tool; the tool never writes back to PIN).
- **Related entities:** For employee identity and assignment history, see [`employee_details.md`](employee_details.md). For public active-workforce org context, see [`people_public.md`](people_public.md). **Team Formation** (sheet-based Line/Team SoT) is **not** replaced during the PoC — do not treat allocation tags as authoritative for official P&T org structure; compare with `dw_people.dim_product_tech_team` when needed.

**Access:** `dw_workforce_allocation` is a restricted People dataset. It stores employee and allocation identifiers plus organizational attributes from the tool export — never employee names, email addresses, or contact data. Use only with authorized People access.

**Grain:** One row per allocation, employee, group, and tag **validity interval**. Intervals split when allocation status or equal-share FTE (1/N within the group) changes; active and inactive historical states are retained. Application-generated sample records (`is_sample`) are excluded.

**DAG:** `bietlejuice.dw_workforce_allocation` (Hive-synced to Trino).

## Known Limitations

- **Prototype:** groups, tags, and export shapes may change before production rollout.
- **No overlap guardrails with PIN:** `chapter`, `vertical`, and `team` on the fact come from the tool's PIN seed and may duplicate or contradict PIN-owned classifications — nothing validates consistency.
- **FTE is equal-split only:** within a group, each active tag gets `1/N` of the employee's capacity; arbitrary percentages are out of scope.
- **FTE is not additive across groups:** an employee in two groups contributes up to 1.0 FTE in each group separately — do not sum across groups as total headcount.
- **Tag names are unique only within a group:** always join tags on `id_tag` or `(id_group, tag_name)`, never on `tag_name` alone.

## TARS / Trino scope

**Catalog:** `delta`

| Table | What it contains |
|-------|------------------|
| `dw_workforce_allocation.fact_workforce_allocations` | SCD2 allocation history with precomputed `allocation_fte`, group/tag dimensions, and read-only org attributes (`chapter`, `vertical`, `team`). No PII. **Only table in this domain for TARS and business consumers.** |

`datalake_people.allocation_history` (Databricks enrich) is restricted to the **technical team** for pipeline debugging and modeling — do not query it from TARS or direct business users to it.

## Related Metric Entities

No official metric entity is currently defined for this domain.

---

## Glossary and Synonyms

| Term | Meaning | Notes |
|------|---------|-------|
| **Allocation Tool / ferramenta de alocação** | Base44 prototype where users manage groups, tags, and employee allocations | Source of truth for groups, tags, and allocations — not for official Line/Team |
| **Group / grupo (tag class)** | User-defined category holding 1–N tags; names unique **globally** | e.g. group `BU`; use `id_group`, `group_name` |
| **Tag** | Label within exactly one group; names unique **only within that group** | e.g. `ForSale` under `BU`; use `id_tag`, `tag_name`, or `(id_group, tag_name)` |
| **Allocation / alocação** | Link between an employee and a tag; FTE is derived from it | 0–N tags per employee **per group**; use `id_allocation` |
| **PIN tag class** | Reserved read-only group for PIN-sourced classifications in the tool | Not editable in the Allocation Tool |
| **Workforce allocation / alocação de pessoas** | Employee capacity assigned to organizational tags over time | Canonical table: `fact_workforce_allocations` |
| **Allocated FTE / FTE alocado** | Fraction of one employee assigned to a tag | `allocation_fte` = `1/N` for N active tags in the same group |
| **Reference date / data de referência** | Calendar date at which allocation state is read | `WHERE <date> BETWEEN dt_valid_from AND dt_valid_to` |
| **Team Formation** | Legacy sheet-based Line/Team allocation (P&T org) | Still SoT for official team structure during PoC; see [`people_public.md`](people_public.md) |
| **chapter / vertical / team** | Org attributes carried on the export (PIN seed) | Descriptive fields on the fact — **not** allocation tags; do not confuse with `group_name`/`tag_name` |
| **Soft delete** | Groups, tags, or allocations marked inactive in the app | Historical states remain queryable via SCD2 |
| **Tag completeness / completude** | Share of expected employees tagged in a group or tag | Compare active `person_number` counts to a roster (e.g. `fact_assignment_snapshots`); no official metric entity yet |

---

## Tables

| You need… | Schema / table |
|-----------|----------------|
| Historical workforce allocation by employee, group, tag, and point in time | `dw_workforce_allocation.fact_workforce_allocations` — **neither** (workforce allocation) |
| Active allocated FTE by group or tag | `dw_workforce_allocation.fact_workforce_allocations` — **neither** (workforce allocation); filter `is_active = TRUE` |
| Current allocation state (no reference date) | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; filter `is_current = TRUE` |
| PIN-seeded org attributes on the allocation export | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; columns `chapter`, `vertical`, `team` (not allocation tags) |
| Official Product & Tech team / line / chapter (Team Formation) | `dw_people.dim_product_tech_team` — **neither**; see [`people_public.md`](people_public.md) |
| Employee identity, headcount, or assignment history | `dw_employee_details.fact_assignment_snapshots` — **neither** (workforce history); see [`employee_details.md`](employee_details.md) |

---

## Key Metrics

Use this entity for exploratory allocation metrics. No official metric entity overrides these definitions.

- **Allocated FTE:** `SUM(allocation_fte)` grouped by `group_name`, `tag_name`, or org attributes; scope to one group at a time when interpreting totals.
- **Active allocation count:** `COUNT(DISTINCT id_allocation)` where `is_active = TRUE`.
- **Active allocated employees:** `COUNT(DISTINCT person_number)` where `is_active = TRUE`.
- **FTE per tag:** `SUM(allocation_fte)` grouped by `group_name`, `tag_name` at a reference date — matches the Allocation Tool dashboard metric.
- **Tag completeness (exploratory):** ratio of distinct `person_number` with an active allocation in a tag (or group) vs an expected roster from `fact_assignment_snapshots` or another approved denominator; define the denominator explicitly in the question.
- **Historical allocation state:** filter `<date> BETWEEN dt_valid_from AND dt_valid_to`; do not use `ts_load` as the business reference date.

For active/inactive logic, prefer `is_active = TRUE` or `allocation_status = 'active'`; `status` is the raw source label.

## Relationships with Other Entities

- **Workforce Allocation → Employee Details:** join on `person_number` (stable business key) or `sk_employee` when not `-1`.
- **Workforce Allocation → People Public:** `person_number` links to `dw_people` for active-workforce context when the consumer has access.
- **Workforce Allocation ↔ Team Formation:** allocation tags are planning/simulation data; official P&T squad/line/chapter is in `dw_people.dim_product_tech_team` — do not substitute one for the other without stating the source.
- **SCD2 model:** `dt_valid_from` and `dt_valid_to` bound each interval; `is_current = TRUE` marks the open interval (`dt_valid_to = DATE '9999-12-31'`).

## Dos and Don'ts

**Do:**

- Filter `<date> BETWEEN dt_valid_from AND dt_valid_to` for point-in-time analysis, or `is_current = TRUE` for the latest state.
- Filter `is_active = TRUE` when calculating current allocated FTE or active allocation counts.
- Aggregate `allocation_fte` within a **single group**; interpret cross-group sums as planning views, not headcount.
- Join tags on `id_tag` or `(id_group, tag_name)`.
- Treat `sk_employee = -1` as an unresolved Allocation Tool employee mapping.
- Use `dw_workforce_allocation.fact_workforce_allocations` for all allocation analysis in TARS.

**Don't:**

- Query `datalake_people.allocation_history` — enrich-layer access is **technical team only**; use `fact_workforce_allocations` instead.

- Count rows as FTE; use `allocation_fte`.
- Sum `allocation_fte` across groups as if it were total company FTE.
- Assume every employee has an allocation or appears under every group.
- Join on `tag_name` alone — names repeat across groups.
- Mix active and inactive rows when reporting current allocation.
- Treat allocation tags as official Team Formation / Line/Team structure during the PoC.
- Infer current state from `ts_load`; use `is_current` and `is_active`.
- Count rows as allocations: one allocation spans multiple rows when its FTE share changed; use `COUNT(DISTINCT id_allocation)`.

## Golden Queries

Active allocated FTE by group at a reference date (canonical planning view):

```sql
SELECT
    group_name,
    SUM(allocation_fte) AS allocated_fte
FROM dw_workforce_allocation.fact_workforce_allocations
WHERE DATE '2026-08-28' BETWEEN dt_valid_from AND dt_valid_to
    AND is_active = TRUE
GROUP BY group_name
ORDER BY allocated_fte DESC, group_name
```

FTE per tag within each group (dashboard-style breakdown):

```sql
SELECT
    group_name,
    tag_name,
    SUM(allocation_fte) AS allocated_fte,
    COUNT(DISTINCT person_number) AS allocated_employees
FROM dw_workforce_allocation.fact_workforce_allocations
WHERE DATE '2026-08-28' BETWEEN dt_valid_from AND dt_valid_to
    AND is_active = TRUE
GROUP BY group_name, tag_name
ORDER BY group_name, allocated_fte DESC, tag_name
```

> **Note:** Replace the literal reference date. In Trino, qualify with the `delta` catalog when needed (`delta.dw_workforce_allocation.fact_workforce_allocations`). Date literals use `DATE 'YYYY-MM-DD'`.

## DataHub catalog

- **Data Product:** Published from this Markdown by the repository DataHub metadata workflow.
- **Dataset:** `dw_workforce_allocation.fact_workforce_allocations`
