# Workforce Allocation

## Ownership

**Data Owner:**
- pedro.prates@quintoandar.com.br

**Data Steward:**
- isabella.araujo@quintoandar.com.br

## Overview

- **Objective:** Model how employees are allocated across Lines, teams, and project tags (e.g. `IPO-readiness`) for quarterly planning, scenario simulation, and org-wide FTE views — replacing ad-hoc spreadsheet workflows that drift over time.
- **Asset status / lifecycle:** **Prototype** (Allocation Tool on Base44). Base44 writes a full daily snapshot to S3; the People pipeline loads it into `dw_workforce_allocation.fact_workforce_allocations`. Access is gated by the IDN data contract **Data Contract - People - Allocation** — Allocation Tool app access does **not** grant TARS/Trino access.
- **Typical actions / events:** admins and ET/LT create teams under Lines, define project tags within teams, link employees to project tags, or soft-deactivate them (`inactive` status).
- **Common metrics:** allocated FTE by Line/team/project tag; people distribution by project (e.g. "who is on IPO?"); active allocation counts; tag history over time.
- **Source systems:** Allocation Tool (Base44), seeded read-only from PIN (D-1, one-directional).
- **Related entities:** For employee identity and assignment history, see [`employee_details.md`](employee_details.md). For active-workforce org context (official Line/Team/chapter), see [`people_public.md`](people_public.md) — Team Formation is **not** replaced by this PoC.

**Grain:** one row per allocation, employee, team (`id_group`), and project tag validity interval (SCD2). Intervals split when status or equal-share FTE (`1/N` within the team) changes.

## Related Metric Entities

No official metric entity is currently defined for this domain.

## Glossary and Synonyms

| Term | Meaning | Notes |
|------|---------|-------|
| **Macro group / Line / linha** | Top-level grouping of teams | `line_name`; export field `groups.line` (e.g. `For Rent`) — **near-miss:** different from `dw_people.dim_product_tech_team.line` (official P&T Line) |
| **Group / team / time** (Allocation Tool) | Team within a Line, export entity `groups` | `id_group`, `group_name` (e.g. `Billing & Payments`) — **near-miss:** different from a P&T squad (`team_1`…`team_10` in `dw_people`) |
| **Tag / project tag / tag de projeto** | Project label within exactly one team, export entity `tags` | `id_tag`, `tag_name` (e.g. `IPO-readiness`); use `(id_group, tag_name)` for team-scoped joins — names repeat across teams |
| **Pessoas alocadas / people allocated / who is allocated** | Employees linked to a project tag in the Allocation Tool | Start at `fact_workforce_allocations`; join `dw_people.dim_employee` for `name` |
| **Tag de IPO / IPO tag / who is on IPO?** | Project tag whose name contains IPO (canonical example: `IPO-readiness`) | `LOWER(tag_name) LIKE '%ipo%'` or `tag_name = 'IPO-readiness'` — **near-miss:** not Team Formation `team_1`…`team_10` |
| **Chapter** | Org attribute carried on the export (PIN seed) | `chapter` column on the fact — **near-miss:** different from `dw_people.dim_product_tech_team.chapter` (official P&T chapter) |
| **Allocation / alocação** | Link between an employee and a project tag | `id_allocation`; FTE is derived within the team, not across teams |
| **Allocated FTE / FTE alocado** | Fraction of one employee assigned to a project tag | `allocation_fte` = `1/N` for N active tags in the same team; equal-split only, not additive across teams |
| **Tag history / histórico de tag** | Which project tags an employee held on a date or over time | SCD2 on the fact: `BETWEEN dt_valid_from AND dt_valid_to` for a date, or full timeline ordered by `dt_valid_from` |
| **People distribution by project / distribuição por projeto** | How allocated people spread across Lines/teams for a project tag | Filter `tag_name`, group by `line_name`, `group_name` |
| **Team Formation** | Legacy sheet-based Line/Team SoT for official P&T org | Still the source of truth during the PoC — see [`people_public.md`](people_public.md); do not treat allocation tags as a substitute |
| **Reference date / data de referência** | Calendar date at which allocation state is read | `WHERE <date> BETWEEN dt_valid_from AND dt_valid_to` |

## Tables

| You need… | Schema / table |
|-----------|----------------|
| Historical or current workforce allocation by employee, Line, team, project, and point in time | `dw_workforce_allocation.fact_workforce_allocations` |
| Which teams/Lines are allocated to a project, or who is on an IPO tag ("pessoas alocadas a uma tag de IPO") | `fact_workforce_allocations` — filter `tag_name` (exact or `LIKE`), group by `line_name`, `group_name` |
| Which project tags an employee held on a date, or how they changed over time | `fact_workforce_allocations` — filter `person_number`; point-in-time via `BETWEEN dt_valid_from AND dt_valid_to`, timeline via `ORDER BY dt_valid_from` |
| Names of people allocated to a project tag | `fact_workforce_allocations` joined to `dw_people.dim_employee` on `person_number` — see [`people_public.md`](people_public.md) |
| Official Product & Tech team / Line / chapter (Team Formation) | Not this entity — see [`people_public.md`](people_public.md) |
| Employee identity or assignment history | Not this entity — see [`employee_details.md`](employee_details.md) |
| Pipeline debugging / modeling only | `datalake_people.allocation_history` — **technical-team only**, not a TARS or business entry point |

**Critical rules:** filter `is_active = TRUE` for current FTE/counts, or `is_current = TRUE` for the latest state without a reference date — never infer state from `ts_load`. Aggregate `allocation_fte` within a **single team**; do not sum across teams as total headcount. `tag_name` alone is not team-scoped — use `(id_group, tag_name)` or `id_tag` when a project name may repeat across teams. The Hive-synced Trino table may lag Databricks/DataHub on `line_name` — prefer `group_name` + `tag_name` and drop `line_name` from a query if it comes back empty.

## Key Metrics

Use [Related Metric Entities](#related-metric-entities) — none currently defined for this domain; the bullets below are exploratory metrics on this entity's tables.

- **Allocated FTE:** `SUM(allocation_fte)` grouped by `line_name`, `group_name`, `tag_name`; interpret cross-team sums as planning views, not headcount.
- **Active allocation count:** `COUNT(DISTINCT id_allocation)` where `is_active = TRUE`.
- **Active allocated employees:** `COUNT(DISTINCT person_number)` where `is_active = TRUE`.
- **People distribution by project:** filter `tag_name` (e.g. `LOWER(tag_name) LIKE '%ipo%'`), then `COUNT(DISTINCT person_number)` and `SUM(allocation_fte)` grouped by `line_name`, `group_name`, `tag_name`.
- **Tag completeness (exploratory):** ratio of distinct `person_number` with an active allocation vs. an expected roster (e.g. `fact_assignment_snapshots`); define the denominator explicitly in the question — no official metric yet.

## Relationships with Other Entities

- **Workforce Allocation → Employee Details:** join on `person_number` (stable business key) or `sk_employee` when not `-1`.
- **Workforce Allocation → People Public:** join `person_number` to `dw_people.dim_employee` for active employee names and work email. The fact stores identifiers only — join for display fields, never in place of the allocation logic.
- **Workforce Allocation ↔ Team Formation:** allocation tags are planning/simulation data; official P&T squad/Line/chapter lives in `dw_people.dim_product_tech_team` — do not substitute one for the other without stating the source.
- **SCD2 model:** `dt_valid_from` / `dt_valid_to` bound each interval; `is_current = TRUE` marks the open interval (`dt_valid_to = DATE '9999-12-31'`).

## Dos and Don'ts

**Do:**
- Filter `<date> BETWEEN dt_valid_from AND dt_valid_to` for point-in-time analysis, or `is_current = TRUE` for the latest state.
- Filter `is_active = TRUE` when calculating current allocated FTE or active allocation counts.
- For project-scoped questions ("distribution by project", "who is on IPO"), filter `tag_name` and group by `line_name`, `group_name`, `tag_name` — show Line and team, not only the project total.
- For tag-history questions, filter `person_number` and use `BETWEEN dt_valid_from AND dt_valid_to` for a single date, or list all intervals ordered by `dt_valid_from` for a timeline.
- Join `dw_people.dim_employee` on `person_number` only when the question needs names, after filtering the allocation fact.
- Route org/squad placement questions with no project-tag intent (e.g. "which team is person X on?") to [`people_public.md`](people_public.md) / `dw_people` instead of this entity.

**Don't:**
- Answer allocation, project-tag, FTE, "pessoas alocadas", or "tag de IPO" questions from Employee Details, Org Chart, or Team Formation — those schemas have no project tags.
- Use `dim_product_tech_team.line` / `chapter` / `team_1`…`team_10` as a substitute for `line_name` / `group_name` / `tag_name` on the fact — different sources, different meaning.
- Query `datalake_people.allocation_history` — enrich-layer access is technical-team only; use `fact_workforce_allocations` instead.
- Count rows as FTE (use `allocation_fte`) or as allocations (one allocation spans multiple rows when its FTE share changed — use `COUNT(DISTINCT id_allocation)`).
- Sum `allocation_fte` across teams as if it were total company FTE.
- Mix active and inactive rows when reporting current allocation state.
- Proxy allocation FTE or tags from `dim_product_tech_team` when the requester lacks the Allocation data contract — state that project-allocation answers require IDN access instead.

## Golden Queries

Names of people currently allocated to a project tag — the canonical pattern for "who is on IPO?" / "pessoas alocadas a uma tag de IPO". Omits `line_name` because that column may lag on the Hive-synced Trino table (see Tables):

```sql
SELECT
    wa.group_name,
    wa.tag_name,
    emp.person_number,
    emp.name,
    wa.allocation_fte
FROM dw_workforce_allocation.fact_workforce_allocations AS wa
INNER JOIN dw_people.dim_employee AS emp
    ON wa.person_number = emp.person_number
WHERE wa.is_current = TRUE
    AND wa.is_active = TRUE
    AND LOWER(wa.tag_name) LIKE '%ipo%'
ORDER BY wa.group_name, emp.name
```

Use exact match (`tag_name = 'IPO-readiness'`) when the project name is known. `dim_employee` lists active employees only; drop the join and aggregate with `COUNT(DISTINCT wa.person_number)` / `SUM(wa.allocation_fte)` for headcount/FTE totals instead of names.

Project tags held by one employee on a reference date — the canonical tag-history pattern (point in time):

```sql
SELECT
    person_number,
    line_name,
    group_name,
    tag_name,
    allocation_fte,
    dt_valid_from,
    dt_valid_to
FROM dw_workforce_allocation.fact_workforce_allocations
WHERE person_number = '123456'
    AND DATE '2026-06-15' BETWEEN dt_valid_from AND dt_valid_to
    AND is_active = TRUE
ORDER BY group_name, tag_name
```

Tag timeline for one employee (tag transitions — e.g. had tag X, now tags A and B):

```sql
SELECT
    person_number,
    line_name,
    group_name,
    tag_name,
    allocation_fte,
    dt_valid_from,
    dt_valid_to,
    is_current,
    is_active
FROM dw_workforce_allocation.fact_workforce_allocations
WHERE person_number = '123456'
ORDER BY dt_valid_from, group_name, tag_name
```

Active allocated FTE by Line and team at a reference date (team view):

```sql
SELECT
    line_name,
    group_name,
    SUM(allocation_fte) AS allocated_fte
FROM dw_workforce_allocation.fact_workforce_allocations
WHERE DATE '2026-08-28' BETWEEN dt_valid_from AND dt_valid_to
    AND is_active = TRUE
GROUP BY line_name, group_name
ORDER BY line_name, allocated_fte DESC, group_name
```

> **Note:** replace the literal reference date. In Trino, catalog is `delta`; if the two-part name resolves to a stale Hive schema, qualify explicitly as `hive.dw_workforce_allocation.fact_workforce_allocations`. Date literals use `DATE 'YYYY-MM-DD'`. Prefer `LOWER(tag_name) LIKE '%pattern%'` over `ILIKE` in TARS-generated SQL.

## DataHub catalog

- **Data Product:** published from this Markdown by the repository DataHub metadata workflow. Link `fact_workforce_allocations` as the primary asset — do not attach Team Formation or assignment-snapshot tables to this product.
- **Dataset:** `dw_workforce_allocation.fact_workforce_allocations`
