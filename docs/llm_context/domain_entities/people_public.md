# People Public

## Ownership

**Data Owner:**
- pedro.prates@quintoandar.com.br

**Data Steward:**
- isabella.araujo@quintoandar.com.br
- gabriel.berger@quintoandar.com.br

---

## Overview

- **Objective:** Public, **active-workforce-only** employee surface for identity, current org placement, management hierarchy, and Product & Tech team formation — the migration target that replaces `datalake_people_public.org_chart` for new consumers.
- **Asset status / lifecycle:** **Active employees only.** Current state; no terminations, no inactive assignments, no history. Terminated / historical analysis belongs in `employee_details.md`.
- **Typical actions / events:** Who works where **today** (active people); tenure and hire date; manager chain L0+; Product & Tech line/chapter/teams (P&T only).
- **Common metrics:** Active headcount; tenure; span of control via hierarchy; headcount by cost center. Prefer person-level P&T attributes over squad rollups.
- **Source systems:** PIN (identity, placement, hierarchy) and the Product & Tech team-formation Google Sheet (line/chapter/`team_1`…`team_10` — P&T roster only).
- **Related entities:** For internal People DW depth (history, terminations, PII docs), see [`employee_details.md`](employee_details.md) — **People-team exclusive** (`dw_employee_details` access **only via IDN request**; not for general consumers). For cost center / BU / job catalogs, see [`organization.md`](organization.md). Legacy denormalized chart: [`org_chart.md`](org_chart.md) (prefer this entity for new queries).

**Business-facing schema guide:** `dags/people/dw_people/docs/dw_people.md`.

### Active-only (non-negotiable)

`dw_people` = **active QuintoAndar employees only**. Every table is filtered at load time.

| If the question is… | Do this |
|---------------------|---------|
| Who is active today / current org / current manager chain | Use `dw_people` |
| Someone left / was terminated / inactive | **People team only** — [`employee_details.md`](employee_details.md) via **IDN** (`dw_employee_details` is not public; they are **not** in `dw_people`) |
| Headcount or org structure on a past date | **People team only** — [`employee_details.md`](employee_details.md) via **IDN**; `dw_people` has no history |

There is **no** `is_active` column on the public fact — do **not** invent `WHERE is_active = TRUE`.

## TARS pilot scope (restricted audience)

**Status:** pilot — prefer Databricks / People-authorized surfaces until `dw_people` is fully public in Trino. Access follows People analytical authorization.

| Table | What it contains |
|-------|------------------|
| `dw_people.dim_employee` | **Active-only** identity: `person_number`, name, work email. **PII**. |
| `dw_people.fact_employees` | **Active-only** current org placement, tenure, hire date, FKs to job / cost center / BU / hierarchy. |
| `dw_people.dim_management_hierarchy` | **Active-only** company-wide reporting chain from CEO (L0) down. **PII** (manager names). |
| `dw_people.dim_product_tech_team` | **Active Product & Tech only** — **wide** sheet mirror: one row per employee with `line`, `chapter`, `team_1`…`team_10`, `line_leader`, `team_leader`, `is_line_leader`, `is_team_leader`. |

Join `organization.md` tables via `fact_employees.sk_job`, `sk_cost_center_version`, `sk_business_unit`.

### Answering “which team does this person belong to?”

Users usually ask in business language — for example which team someone is on, where they sit in the org, who their manager is, or who reports to them.

**Decision flow:**

1. Resolve the person in `dim_employee` (name / work email / `person_number`). If missing → not in the **active** public workforce; check `employee_details.md`.
2. Look up `dim_product_tech_team` on `sk_employee` / `person_number`.
   - **Hit (Product & Tech):** answer with `line`, `chapter`, `team_1` (primary), and any filled `team_2`…`team_10`, plus leaders / flags. State that this is Product & Tech team formation from the roster sheet.
   - **Miss (no dim row):** they are **not** on the Product & Tech roster. Do **not** invent a squad. Answer with **cost center + management**:
     - **Where they sit:** cost center (`dw_organization.dim_cost_center` via `fact_employees`).
     - **Who leads them:** direct manager from `dim_management_hierarchy` (`name_manager` / `person_number_manager`).
     - **Who they lead** (especially useful for managers outside Tech): active people whose `person_number_manager` equals this person’s `person_number`.

**Good non–P&T answer shape (example):**  
“*Person Name* is in cost center *X* and leads *A, B, C*. They report to *Manager Name*.”

**Do not** say the person “has no team” only because they are outside the P&T sheet — use cost center + leadership instead.

| Natural question | Route |
|------------------|--------|
| Team / line / chapter for a Product & Tech person | `dim_product_tech_team` (`team_1`…`team_10`) |
| Team / org placement for Ops, Corp, non–P&T, or no dim row | Cost center + manager + direct reports |
| Who reports to this person? | `dim_management_hierarchy` where `person_number_manager` = that person |
| Who is their manager? / L0+ chain | `dim_management_hierarchy` for that person’s row |

Do **not** invent team-formation attributes outside Product & Tech. Do **not** run Product & Tech **headcount-by-squad** rollups from this wide table (teams are spread across `team_1`…`team_10`). Prefer person-level answers. Legacy wide columns on `org_chart` used `product_and_tech_team_*` names; public DW uses `team_*`.

## Related Domain Entities

- `organization.md` — cost center, business unit, and job labels via fact FKs.
- `employee_details.md` — full internal People DW (history, terminations, restricted attributes). **`dw_employee_details` is exclusive to the People team** — access **only on IDN request** with data-owner approval. **Do not** route general consumers here; use `dw_people`.
- `workforce_allocation.md` — **planning** allocations (project tags, FTE, Allocation Tool Lines/teams). Use `dw_workforce_allocation.fact_workforce_allocations`, **not** `dw_people`, for those questions. Join `dim_employee` here only when an allocation answer needs a **name**.
- `org_chart.md` — legacy denormalized enrich table; keep for continuity until cutover completes.

### Do not confuse `dw_people` with `dw_workforce_allocation`

| If the question is about… | Use | Do **not** use |
|---------------------------|-----|----------------|
| Who is active, manager, cost center, tenure, official P&T squad | `dw_people` | `dw_workforce_allocation` |
| Project tag, allocated FTE, “who is on IPO?”, allocation history | [`workforce_allocation.md`](workforce_allocation.md) → `fact_workforce_allocations` | `dim_product_tech_team` or `fact_employees` as primary source |
| Name in an **allocation** answer | Join `dim_employee` to the allocation **fact** | Listing everyone in `dim_employee` and guessing tags |

Shared labels (`line`, `chapter`, `team`) mean **different things** in each schema — see the homonym table in [`workforce_allocation.md`](workforce_allocation.md#do-not-confuse-dw_workforce_allocation-with-dw_people).

## Glossary and Synonyms

| Term | Meaning | Notes |
|------|---------|-------|
| **People public / dw_people / quadro público** | Public **active-only** workforce schema | Prefer over `org_chart` for new analysis; no terminated people |
| **Active employee / colaborador ativo** | Person with an active PIN assignment today | Only this population appears in `dw_people` |
| **Org chart / organograma** | Who works where today (active) | Prefer `dw_people` + `dw_organization`; legacy = `org_chart` |
| **Person number / matrícula PIN** | Stable employee business key | `person_number` |
| **Product & Tech team formation / time P&T** | Line, chapter, leaders + teams for **P&T only** | Wide `dim_product_tech_team` — not company-wide |
| **Line / capítulo / chapter (P&T)** | P&T structure labels from the roster sheet | On `dim_product_tech_team`; distinct from Codex on cost center |
| **team_1 … team_10** | Squad slots from the sheet (wide) | `team_1` is primary; later slots optional |
| **Cost center / centro de custo** | Org classification for placement (all areas) | `dw_organization.dim_cost_center` |
| **Manager chain / cadeia de gestão / hierarquia** | CEO → employee levels (company-wide) | `dim_management_hierarchy` |
| **Active headcount / quadro ativo** | Count of active employees | `COUNT(*)` on `fact_employees` or `dim_employee` |

## Tables

| You need… | Schema / table |
|-----------|----------------|
| Active employee name / work email | `dw_people.dim_employee` |
| Current placement, tenure, hire date | `dw_people.fact_employees` |
| Manager chain L0+ (any area) | `dw_people.dim_management_hierarchy` |
| Product & Tech line / chapter / teams | `dw_people.dim_product_tech_team` |
| Job / cost center / BU labels (any area) | Join `organization.md` from `fact_employees` FKs |
| Org / “time” outside P&T | Cost center + manager + direct reports — **not** the P&T dim |
| Terminated or month-end history | `employee_details.md` — not this schema |
| Project tags, allocation FTE, planning Lines/teams | [`workforce_allocation.md`](workforce_allocation.md) — not `dw_people` |
| Legacy single-table org chart (during migration) | `datalake_people_public.org_chart` — see [`org_chart.md`](org_chart.md) |

**Critical rules:**
- **Active-only:** all `dw_people` tables exclude terminated / inactive people. Do **not** add `is_active = TRUE`.
- Missing person in `dw_people` ≠ query bug by default — they may have left; route to `employee_details.md`.
- P&T dim exists **only for Product & Tech**. For team / org-placement questions outside P&T: cost center + who leads them + who they lead.
- Wide grain: one row per P&T employee — no fan-out when joining to `fact_employees` / `dim_employee`.
- Prefer `sk_employee` joins within `dw_people`; hierarchy also joins via `fact_employees.sk_manager_hierarchy`.
- Do not use this schema for exits, month-end archives, or compensation.

## Key Metrics

- **Active headcount:** `COUNT(*)` on `dw_people.fact_employees` (or `dim_employee`).
- **P&T roster size:** `COUNT(*)` on `dim_product_tech_team` (already one row per person).
- **Headcount by cost center (company-wide):** join `dim_cost_center` from `fact_employees`.
- **Average tenure:** `AVG(months_employee_tenure)` on `fact_employees`.

Do **not** publish Product & Tech headcount-by-squad from this entity (wide slots are for person attributes, not easy rollups).

## Relationships with Other Entities

### Organization

- `fact_employees.sk_job` → `dw_organization.dim_job`
- `fact_employees.sk_cost_center_version` → `dw_organization.dim_cost_center`
- `fact_employees.sk_business_unit` → `dw_organization.dim_business_unit`

### Employee Details

- Same people appear in `dw_employee_details` for history and restricted attributes; public consumers should stay on `dw_people`.

### Org Chart (legacy)

- `org_chart` denormalizes identity + manager + Codex + wide P&T columns in one enrich table.
- Replacement mapping: identity/manager/placement → `dw_people` + `dw_organization`; P&T → `dim_product_tech_team` (**wide** `team_1`…`team_10`); other areas → cost center + `dim_management_hierarchy`.

## Dos and Don'ts

**Do:**
- Prefer `dw_people` over `datalake_people_public.org_chart` for **new** queries about the **active** workforce.
- Use `dim_product_tech_team` for Product & Tech person attributes (`team_1` as primary squad).
- For team / org-placement questions outside P&T: answer with **cost center**, **who they report to**, and **who they lead** (direct reports) — never invent a P&T squad.
- Route historical / termination questions to `employee_details.md` **only when the requester is on the People team** (IDN access to `dw_employee_details`).

**Don't:**
- Answer allocation, project-tag, or FTE planning questions from `dw_people` — route to [`workforce_allocation.md`](workforce_allocation.md).
- Map `dim_product_tech_team.line` / `chapter` / `team_1` to Allocation Tool `line_name` / `group_name` / `tag_name` without stating both sources differ.
- Tell consumers to request `dw_employee_details` access via **IDN** — that schema is **exclusive to the People team**.
- Assume terminated or inactive people appear in `dw_people`.
- Filter `is_active` on `dw_people` tables.
- Answer only that the person is missing from the Product & Tech team-formation sheet without also giving cost center + leadership context.
- Build headcount-by-squad answers from `team_1`…`team_10` (not the supported use of this wide dim).
- Invent squad/line/chapter from the P&T sheet for Ops, Corp, or other areas.
- Use deprecated People sources (`datalake_hr_system`, `datalake_employment`) for new queries.

## Golden Queries

### Query 1 — Team placement for a Product & Tech person

```sql
SELECT
    emp.person_number,
    emp.name,
    emp.work_email,
    pt.line,
    pt.chapter,
    pt.team_1,
    pt.team_2,
    pt.line_leader,
    pt.team_leader,
    pt.is_line_leader,
    pt.is_team_leader
FROM dw_people.dim_employee AS emp
INNER JOIN dw_people.dim_product_tech_team AS pt
    ON emp.sk_employee = pt.sk_employee
WHERE emp.person_number = '<person_number>'
   OR LOWER(emp.name) LIKE '%<name_fragment>%'
   OR LOWER(emp.work_email) = LOWER('<work_email>')
```

### Query 2 — Who has a given squad in any team slot (person list, not headcount)

```sql
SELECT
    emp.person_number,
    emp.name,
    pt.line,
    pt.chapter,
    pt.team_1,
    pt.team_2,
    pt.team_3
FROM dw_people.dim_product_tech_team AS pt
INNER JOIN dw_people.dim_employee AS emp
    ON pt.sk_employee = emp.sk_employee
WHERE LOWER(pt.team_1) = LOWER('<squad_name>')
   OR LOWER(pt.team_2) = LOWER('<squad_name>')
   OR LOWER(pt.team_3) = LOWER('<squad_name>')
   OR LOWER(pt.team_4) = LOWER('<squad_name>')
   OR LOWER(pt.team_5) = LOWER('<squad_name>')
   OR LOWER(pt.team_6) = LOWER('<squad_name>')
   OR LOWER(pt.team_7) = LOWER('<squad_name>')
   OR LOWER(pt.team_8) = LOWER('<squad_name>')
   OR LOWER(pt.team_9) = LOWER('<squad_name>')
   OR LOWER(pt.team_10) = LOWER('<squad_name>')
ORDER BY emp.name
```

Use this to **list** people, not to answer “how many people on team X?” as a primary metric.

### Query 3 — Team / org placement outside Product & Tech (cost center + leads + manager)

Use when the person has **no** row in `dim_product_tech_team` (or the question is about a non–P&T manager). Answer shape: cost center, who they lead, who leads them.

```sql
-- Placement + direct manager
SELECT
    emp.person_number,
    emp.name,
    emp.work_email,
    cc.cost_center_name,
    hier.name_manager,
    hier.person_number_manager
FROM dw_people.fact_employees AS fact
INNER JOIN dw_people.dim_employee AS emp
    ON fact.sk_employee = emp.sk_employee
LEFT JOIN dw_organization.dim_cost_center AS cc
    ON fact.sk_cost_center_version = cc.sk_cost_center_version
LEFT JOIN dw_people.dim_management_hierarchy AS hier
    ON fact.sk_manager_hierarchy = hier.sk_manager_hierarchy
WHERE emp.person_number = '<person_number>'
   OR LOWER(emp.name) LIKE '%<name_fragment>%'
   OR LOWER(emp.work_email) = LOWER('<work_email>')
```

```sql
-- Direct reports (who this person leads)
SELECT
    report_emp.person_number,
    report_emp.name,
    report_emp.work_email
FROM dw_people.dim_management_hierarchy AS hier
INNER JOIN dw_people.dim_employee AS report_emp
    ON hier.person_number = report_emp.person_number
WHERE hier.person_number_manager = '<person_number>'
ORDER BY report_emp.name
```

### Query 4 — Management chain L0+ for an active employee

```sql
SELECT
    emp.person_number,
    emp.name,
    hier.name_manager,
    hier.name_l0,
    hier.name_l1,
    hier.name_l2,
    hier.name_l3,
    hier.name_l4
FROM dw_people.dim_employee AS emp
INNER JOIN dw_people.dim_management_hierarchy AS hier
    ON emp.person_number = hier.person_number
WHERE emp.person_number = '<person_number>'
```

## DataHub catalog

> Added automatically by the agent after Step 7 — do not fill in manually.
