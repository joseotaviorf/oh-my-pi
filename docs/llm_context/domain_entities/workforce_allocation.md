# Workforce Allocation

## Ownership

**Data Owner:**
- pedro.prates@quintoandar.com.br

**Data Steward:**
- isabella.araujo@quintoandar.com.br

---

## Overview

- **Objective:** Model how employees are allocated across Lines, teams, and project tags for quarterly planning, scenario simulation, and org-wide FTE views — replacing ad-hoc spreadsheet workflows that drift over time.
- **Asset status / lifecycle:** **Prototype** (Allocation Tool on Base44). Production rollout is a separate decision after validation; treat the export contract and schema as unstable. Base44 writes a **full daily snapshot** to S3; the People pipeline loads it into the lake and publishes `dw_workforce_allocation.fact_workforce_allocations` for Trino/TARS, Superset, and ad-hoc reports.
- **Typical actions / events:** Admins and ET/LT create teams under Lines, define project tags within teams, link employees to project tags, or soft-deactivate them (`inactive` status). Allocations absent from a snapshot are treated as removed at source.
- **Common metrics:** Allocated FTE by Line, team, or project tag; **people distribution by project** (which teams and Lines contribute to a project such as IPO); active allocation counts; project coverage across teams; historical allocation states.
- **Source systems:** Allocation Tool (Base44) → S3 export → People pipeline → `dw_workforce_allocation.fact_workforce_allocations` (Trino/TARS). Upstream enrich (`datalake_people.allocation_history`) is **technical-team only** — not a TARS or business consumer entry point. Employee records in the tool are **read-only**, seeded from PIN (D-1); sync is one-directional (PIN → S3 → tool; the tool never writes back to PIN).
- **Related entities:** For employee identity and assignment history, see [`employee_details.md`](employee_details.md). For public active-workforce org context, see [`people_public.md`](people_public.md). **Team Formation** (sheet-based Line/Team SoT) is **not** replaced during the PoC — do not treat allocation tags as authoritative for official P&T org structure; compare with `dw_people.dim_product_tech_team` when needed.

**Access:** `dw_workforce_allocation` is a restricted People dataset. It stores employee and allocation identifiers plus organizational attributes from the tool export — never employee names, email addresses, or contact data. Use only with authorized People access.

**Grain:** One row per allocation, employee, team (`id_group`), and project tag **validity interval**. Intervals split when allocation status or equal-share FTE (1/N within the team) changes; active and inactive historical states are retained. Application-generated sample records (`is_sample`) are excluded.

**Classification hierarchy:** three levels — macro group → team → project. See [Resource Allocation classification model](#resource-allocation-classification-model) for tool terms (`groups`, `tags`) and column mapping.

**DAG:** `bietlejuice.dw_workforce_allocation` (Hive-synced to Trino).

## Resource Allocation classification model

Resource Allocation 2.0 (Allocation Tool) classifies workforce planning in **three levels**. Stakeholders often ask using the tool/export names **macro groups**, **groups**, and **tags** — map them as follows in `fact_workforce_allocations`:

| Level | Tool / export term | Export entity | Column(s) on the fact | Example |
|-------|-------------------|---------------|------------------------|---------|
| 1 — Macro group | **macro group**, **Line**, **linha** | `groups.line` | `line_name` | `For Rent` |
| 2 — Team | **group**, **team**, **time** | `groups` record (`groups.name`) | `id_group`, `group_name` | `Billing & Payments` |
| 3 — Project | **tag**, **project tag**, **tag de projeto** | `tags` record (`tags.name`) | `id_tag`, `tag_name` | `IPO-readiness` |

**How to read the names:** in the Allocation Tool export, entity **`groups`** holds teams; each team row carries a `line` field naming its macro group. Entity **`tags`** holds project labels; each tag belongs to exactly one team (`id_group`). An **allocation** links an employee to a project tag; FTE is derived within the team (`id_group`), not across teams.

**Cardinality (RA 2.0):**

| Relationship | Rule |
|--------------|------|
| Line → team | Every team **must** belong to exactly one Line (`line_name` is mandatory on each team). A Line only exists in the model through its teams. |
| Team → project tag | Each project tag belongs to exactly one team (`id_group`). A team holds 1–N project tags. |
| Employee → allocation | An employee holds 0–N project tags **per team**; each allocation links one employee to one project tag. |

**Primary analysis pattern — people distribution by project:** when the question is “how are people distributed on project X?” or “which teams are allocated to IPO?”, filter by `tag_name` (exact or partial match), then break down by `line_name` and `group_name`. The same project name may appear in multiple teams — always show team (and Line) in the answer, not only the project total.

**Primary analysis pattern — tag allocation history:** project tags assigned to an employee are historized in `fact_workforce_allocations` as SCD2 intervals (`dt_valid_from`, `dt_valid_to`). Each row is one allocation (`id_allocation`) to one `tag_name` for one validity period. When the question is “which tags did person P have on date D?” or “I had tag X in period Y, now I have tags A and B”, filter by `person_number` (or `sk_employee`) and use a reference date or list intervals ordered by `dt_valid_from`. Tag **assignments** are point-in-time accurate; `line_name` on each row reflects the team's Line at processing time (see Known Limitations).

**When the question says…**

| User says | Query by |
|-----------|----------|
| macro group / Line / linha | `line_name` |
| group / team / time | `group_name` or `id_group` |
| tag / project / projeto | `tag_name` or `id_tag` (team-scoped: `(id_group, tag_name)`) |
| which teams are on project X / distribuição por projeto | filter `tag_name` (e.g. `ILIKE '%IPO%'`), group by `line_name`, `group_name`, `tag_name` |
| which tags on date D / histórico de tag / tag history | `person_number` + `DATE '<D>' BETWEEN dt_valid_from AND dt_valid_to`; include `tag_name`, `group_name`, `dt_valid_from`, `dt_valid_to` |
| tag change over time / tinha tag X agora tenho A e B | `person_number`, order by `dt_valid_from`; list all intervals with `tag_name`, `is_active`, `allocation_fte` |

Project tag names may repeat across teams — for project-scoped questions, list **Line + team + project**; use a project-only total only when the user explicitly asks for a company-wide rollup.

## Known Limitations

- **Prototype:** groups, tags, and export shapes may change before production rollout.
- **Legacy `line_name`:** in RA 2.0 every team must have a Line; historical SCD2 intervals from pre-2.0 exports may still show `line_name IS NULL`. Filter `line_name IS NOT NULL` when the question assumes the current model.
- **No overlap guardrails with PIN:** `chapter`, `vertical`, and `team` on the fact come from the tool's PIN seed and may duplicate or contradict PIN-owned classifications — nothing validates consistency.
- **FTE is equal-split only:** within a team, each active project tag gets `1/N` of the employee's capacity; arbitrary percentages are out of scope.
- **FTE is not additive across teams:** an employee in two teams contributes up to 1.0 FTE in each team separately — do not sum across teams as total headcount.
- **Project tag names may repeat across teams:** aggregate by `tag_name` only when the question is project-scoped across teams; for team-level detail, use `id_tag` or `(id_group, tag_name)`.
- **Tag assignment history vs Line history:** `tag_name` / `id_tag` per allocation interval are historized from daily snapshots (e.g. employee moved from tag X to tags A and B). `line_name` is resolved from current `groups` at enrich time — past Line membership of a team is not yet historized (see DBP-2106).

## TARS / Trino scope

**Catalog:** `delta`

| Table | What it contains |
|-------|------------------|
| `dw_workforce_allocation.fact_workforce_allocations` | SCD2 allocation history with precomputed `allocation_fte`, Line/team/project dimensions (`line_name`, `group_name`, `tag_name`), and read-only org attributes (`chapter`, `vertical`, `team`). No PII. **Only table in this domain for TARS and business consumers.** |

`datalake_people.allocation_history` (Databricks enrich) is restricted to the **technical team** for pipeline debugging and modeling — do not query it from TARS or direct business users to it.

## Related Metric Entities

No official metric entity is currently defined for this domain.

---

## Glossary and Synonyms

| Term | Meaning | Notes |
|------|---------|-------|
| **Allocation Tool / ferramenta de alocação** | Base44 app where users manage macro groups, teams, project tags, and employee allocations | Source of truth for allocation planning — not for official Line/Team |
| **Macro group / macro groups / grupo macro** | Top-level Line that groups related teams | `line_name`; export field `groups.line` (e.g. `For Rent`); exists only through its teams |
| **Group / groups** (Allocation Tool) | **Team** in RA 2.0 — stored in export entity `groups`, not the macro group | `id_group`, `group_name` (e.g. `Billing & Payments`); **must** have a `line_name`; do not confuse with `groups` as a generic word or with PIN `team` |
| **People distribution by project / distribuição por projeto** | How allocated people spread across Lines and teams for a given project tag | Filter `tag_name`, group by `line_name`, `group_name`; use `COUNT(DISTINCT person_number)` and `SUM(allocation_fte)` |
| **Tag allocation history / histórico de tag / histórico de alocação** | Which project tags an employee held during a date or over time | SCD2 on `fact_workforce_allocations`: point-in-time with `BETWEEN dt_valid_from AND dt_valid_to`, or full timeline ordered by `dt_valid_from` |
| **Tag transition / mudança de tag** | Employee moved from one project tag to others (e.g. had X, now has A and B) | List intervals per `person_number`; each `id_allocation` × `tag_name` has its own `dt_valid_from` / `dt_valid_to` |
| **Tag / tags** (Allocation Tool) | **Project** label within exactly one team — stored in export entity `tags` | `id_tag`, `tag_name` (e.g. `IPO-readiness`); use `(id_group, tag_name)` for team-scoped joins |
| **Line / linha** | Synonym for macro group | `line_name` |
| **Team / time** | Synonym for Allocation Tool group | `id_group`, `group_name` |
| **Project tag / tag de projeto** | Synonym for Allocation Tool tag | `id_tag`, `tag_name` |
| **Allocation / alocação** | Link between an employee and a project tag; FTE is derived from it | 0–N project tags per employee **per team**; use `id_allocation` |
| **PIN tag class** | Reserved read-only group for PIN-sourced classifications in the tool | Not editable in the Allocation Tool |
| **Workforce allocation / alocação de pessoas** | Employee capacity assigned to project tags over time | Canonical table: `fact_workforce_allocations` |
| **Allocated FTE / FTE alocado** | Fraction of one employee assigned to a project tag | `allocation_fte` = `1/N` for N active project tags in the same team |
| **Reference date / data de referência** | Calendar date at which allocation state is read | `WHERE <date> BETWEEN dt_valid_from AND dt_valid_to` |
| **Team Formation** | Legacy sheet-based Line/Team allocation (P&T org) | Still SoT for official team structure during PoC; see [`people_public.md`](people_public.md) |
| **chapter / vertical / team** | Org attributes carried on the export (PIN seed) | Descriptive fields on the fact — **not** allocation teams or project tags; do not confuse with `line_name`/`group_name`/`tag_name` |
| **Soft delete** | Teams, project tags, or allocations marked inactive in the app | Historical states remain queryable via SCD2 |
| **Tag completeness / completude** | Share of expected employees tagged in a team or project | Compare active `person_number` counts to a roster (e.g. `fact_assignment_snapshots`); no official metric entity yet |

---

## Tables

| You need… | Schema / table |
|-----------|----------------|
| Historical workforce allocation by employee, Line, team, project, and point in time | `dw_workforce_allocation.fact_workforce_allocations` — **neither** (workforce allocation) |
| Active allocated FTE by macro group / Line (`line_name`) | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; aggregate by `line_name`, filter `is_active = TRUE` |
| Active allocated FTE by team / Allocation Tool group (`group_name`) | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; aggregate by `group_name` or `id_group`, filter `is_active = TRUE` |
| Active allocated FTE by project tag (`tag_name`) within a team | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; aggregate by `line_name`, `group_name`, `tag_name`, filter `is_active = TRUE` |
| Which teams (and Lines) are allocated to a project (e.g. IPO) | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; filter `tag_name` (exact or `ILIKE`), group by `line_name`, `group_name`, `tag_name` |
| Which project tags an employee held on a reference date | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; filter `person_number` and `DATE '<ref>' BETWEEN dt_valid_from AND dt_valid_to` |
| How an employee's project tags changed over time (tag history / transitions) | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; filter `person_number`, order by `dt_valid_from`, show `tag_name`, `group_name`, validity columns |
| Project FTE rolled up across teams (same project tag name) | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; aggregate `allocation_fte` by `tag_name` only when a single company-wide total is requested |
| Current allocation state (no reference date) | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; filter `is_current = TRUE` |
| PIN-seeded org attributes on the allocation export | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; columns `chapter`, `vertical`, `team` (not allocation teams or project tags) |
| Official Product & Tech team / line / chapter (Team Formation) | `dw_people.dim_product_tech_team` — **neither**; see [`people_public.md`](people_public.md) |
| Employee identity, headcount, or assignment history | `dw_employee_details.fact_assignment_snapshots` — **neither** (workforce history); see [`employee_details.md`](employee_details.md) |

---

## Key Metrics

Use this entity for exploratory allocation metrics. No official metric entity overrides these definitions.

- **Allocated FTE:** `SUM(allocation_fte)` grouped by `line_name`, `group_name`, `tag_name`, or org attributes; scope to one team at a time when interpreting team-level totals.
- **Active allocation count:** `COUNT(DISTINCT id_allocation)` where `is_active = TRUE`.
- **Active allocated employees:** `COUNT(DISTINCT person_number)` where `is_active = TRUE`.
- **FTE per project tag within a team:** `SUM(allocation_fte)` grouped by `line_name`, `group_name`, `tag_name` at a reference date — matches the Allocation Tool team view.
- **People distribution by project:** filter `tag_name` (e.g. `ILIKE '%IPO%'`), then `COUNT(DISTINCT person_number)` and `SUM(allocation_fte)` grouped by `line_name`, `group_name`, `tag_name` — answers “which teams are on IPO?”
- **FTE per project across teams (rollup only):** `SUM(allocation_fte)` grouped by `tag_name` when the user wants one total, not a team breakdown.
- **Tag completeness (exploratory):** ratio of distinct `person_number` with an active allocation in a project tag (or team) vs an expected roster from `fact_assignment_snapshots` or another approved denominator; define the denominator explicitly in the question.
- **Historical allocation state:** filter `<date> BETWEEN dt_valid_from AND dt_valid_to`; do not use `ts_load` as the business reference date.
- **Tag allocation history:** list `tag_name`, `group_name`, `allocation_fte`, `dt_valid_from`, `dt_valid_to` per `person_number` — answers “which tags on date D?” and “how did tags change over time?”.

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
- Aggregate `allocation_fte` within a **single team** (`id_group`) when reporting team-level FTE; interpret cross-team sums as planning views, not headcount.
- For project-scoped questions (“distribution by project”, “teams on IPO”), filter `tag_name` and group by `line_name`, `group_name`, `tag_name` — show Line and team, not only the project total.
- For tag-history questions (“which tags on date D?”, “had tag X, now A and B”), filter `person_number` and use `BETWEEN dt_valid_from AND dt_valid_to` for a single date, or list all intervals ordered by `dt_valid_from` for a timeline.
- Use a `tag_name`-only rollup only when the user explicitly asks for a single company-wide project total.
- Join project tags on `id_tag` or `(id_group, tag_name)` for team-level detail.
- Treat `sk_employee = -1` as an unresolved Allocation Tool employee mapping.
- Use `dw_workforce_allocation.fact_workforce_allocations` for all allocation analysis in TARS.

**Don't:**

- Query `datalake_people.allocation_history` — enrich-layer access is **technical team only**; use `fact_workforce_allocations` instead.

- Count rows as FTE; use `allocation_fte`.
- Sum `allocation_fte` across teams as if it were total company FTE.
- Assume every employee has an allocation or appears under every team.
- Use `tag_name` alone for team-scoped joins — project names repeat across teams; use `(id_group, tag_name)` or `id_tag` instead.
- Mix active and inactive rows when reporting current allocation.
- Treat allocation tags as official Team Formation / Line/Team structure during the PoC.
- Infer current state from `ts_load`; use `is_current` and `is_active`.
- Count rows as allocations: one allocation spans multiple rows when its FTE share changed; use `COUNT(DISTINCT id_allocation)`.

## Golden Queries

Project tags held by one employee on a reference date (tag history — point in time):

```sql
SELECT
    person_number,
    line_name,
    group_name,
    tag_name,
    allocation_fte,
    dt_valid_from,
    dt_valid_to,
    is_active
FROM dw_workforce_allocation.fact_workforce_allocations
WHERE person_number = '123456'
    AND DATE '2026-06-15' BETWEEN dt_valid_from AND dt_valid_to
    AND is_active = TRUE
ORDER BY group_name, tag_name
```

Project tag timeline for one employee (tag transitions — e.g. had tag X, now tags A and B):

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

Show active tags only in the timeline by adding `AND is_active = TRUE`. Each closed interval keeps `tag_name` as it was during that period.

Teams and people allocated to a project (e.g. IPO) — **primary project-distribution pattern**:

```sql
SELECT
    line_name,
    group_name,
    tag_name,
    SUM(allocation_fte) AS allocated_fte,
    COUNT(DISTINCT person_number) AS allocated_employees
FROM dw_workforce_allocation.fact_workforce_allocations
WHERE DATE '2026-08-28' BETWEEN dt_valid_from AND dt_valid_to
    AND is_active = TRUE
    AND tag_name ILIKE '%IPO%'
GROUP BY line_name, group_name, tag_name
ORDER BY line_name, group_name, allocated_fte DESC, tag_name
```

Use exact match (`tag_name = 'IPO-readiness'`) when the project name is known. Prefer the breakdown above over a single `GROUP BY tag_name` total unless the question asks only for company-wide FTE on the project.

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

FTE per project tag within each team (team view):

```sql
SELECT
    line_name,
    group_name,
    tag_name,
    SUM(allocation_fte) AS allocated_fte,
    COUNT(DISTINCT person_number) AS allocated_employees
FROM dw_workforce_allocation.fact_workforce_allocations
WHERE DATE '2026-08-28' BETWEEN dt_valid_from AND dt_valid_to
    AND is_active = TRUE
GROUP BY line_name, group_name, tag_name
ORDER BY line_name, group_name, allocated_fte DESC, tag_name
```

Company-wide FTE rollup for one project tag name (use only when team breakdown is not needed):

```sql
SELECT
    tag_name,
    SUM(allocation_fte) AS allocated_fte,
    COUNT(DISTINCT person_number) AS allocated_employees
FROM dw_workforce_allocation.fact_workforce_allocations
WHERE DATE '2026-08-28' BETWEEN dt_valid_from AND dt_valid_to
    AND is_active = TRUE
    AND tag_name ILIKE '%IPO%'
GROUP BY tag_name
ORDER BY allocated_fte DESC, tag_name
```

> **Note:** Replace the literal reference date. In Trino, qualify with the `delta` catalog when needed (`delta.dw_workforce_allocation.fact_workforce_allocations`). Date literals use `DATE 'YYYY-MM-DD'`.

## DataHub catalog

- **Data Product:** Published from this Markdown by the repository DataHub metadata workflow.
- **Dataset:** `dw_workforce_allocation.fact_workforce_allocations`
