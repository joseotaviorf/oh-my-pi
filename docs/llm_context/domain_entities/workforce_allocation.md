# Workforce Allocation

## Ownership

**Data Owner:**
- pedro.prates@quintoandar.com.br

**Data Steward:**
- isabella.araujo@quintoandar.com.br

---

## Overview

- **Objective:** Model how employees are allocated across Lines, teams, and project tags (including **IPO** / **tag de IPO**) for quarterly planning, scenario simulation, and org-wide FTE views — replacing ad-hoc spreadsheet workflows that drift over time. **TARS:** questions like “quais pessoas estão alocadas a uma tag de IPO”, “who is on IPO?”, “pessoas alocadas”, or “project tag roster” belong **here**, not in Employee Details, Org Chart, or Team Formation.
- **Asset status / lifecycle:** **Prototype** (Allocation Tool on Base44). Production rollout is a separate decision after validation; treat the export contract and schema as unstable. Base44 writes a **full daily snapshot** to S3; the People pipeline loads it into the lake and publishes `dw_workforce_allocation.fact_workforce_allocations` for Trino/TARS, Superset, and ad-hoc reports.
- **Typical actions / events:** Admins and ET/LT create teams under Lines, define project tags within teams, link employees to project tags, or soft-deactivate them (`inactive` status). Allocations absent from a snapshot are treated as removed at source.
- **Common metrics:** Allocated FTE by Line, team, or project tag; **people distribution by project** (which teams and Lines contribute to a project such as IPO); active allocation counts; project coverage across teams; historical allocation states.
- **Source systems:** Allocation Tool (Base44) → S3 export → People pipeline → `dw_workforce_allocation.fact_workforce_allocations` (Trino/TARS). Upstream enrich (`datalake_people.allocation_history`) is **technical-team only** — not a TARS or business consumer entry point. Employee records in the tool are **read-only**, seeded from PIN (D-1); sync is one-directional (PIN → S3 → tool; the tool never writes back to PIN).
- **Related entities:** For employee identity and assignment history, see [`employee_details.md`](employee_details.md). For public active-workforce org context, see [`people_public.md`](people_public.md). **Team Formation** (sheet-based Line/Team SoT) is **not** replaced during the PoC — do not treat allocation tags as authoritative for official P&T org structure; compare with `dw_people.dim_product_tech_team` when needed.

**Access:** `dw_workforce_allocation` is a restricted People dataset gated by the IDN domain **Data Contract - People - Allocation** (Allocation Tool app access does **not** grant TARS/Trino access). The fact stores identifiers and organizational attributes from the tool export — never employee names or contact data. Names require a separate join to `dw_people.dim_employee` when the requester also has People public access.

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
| how many people on tag X / qtde alocada em tag | `COUNT(DISTINCT person_number)` filtering `tag_name`, `is_active = TRUE` |
| people on tag X by chapter / por chapter | `GROUP BY chapter`, `COUNT(DISTINCT person_number)` |
| names on tag X / nomes alocados | join `dw_people.dim_employee` on `person_number`; select `emp.name` |
| teams on a Line / times de uma linha | `SELECT DISTINCT group_name WHERE line_name = '…'` |
| how many Lines / quantas linhas | `COUNT(DISTINCT line_name)` where `line_name IS NOT NULL` |
| people on a team / pessoas de um time | filter `group_name`; join `dim_employee` for `name` |
| people on chapter within Line / chapter numa linha | filter `line_name` and `chapter`; join `dim_employee` for `name` |
| which tags on date D / histórico de tag / tag history | `person_number` + `DATE '<D>' BETWEEN dt_valid_from AND dt_valid_to`; include `tag_name`, `group_name`, `dt_valid_from`, `dt_valid_to` |
| tag change over time / tinha tag X agora tenho A e B | `person_number`, order by `dt_valid_from`; list all intervals with `tag_name`, `is_active`, `allocation_fte` |

Project tag names may repeat across teams — for project-scoped questions, list **Line + team + project**; use a project-only total only when the user explicitly asks for a company-wide rollup.

## Known Limitations

- **Prototype:** groups, tags, and export shapes may change before production rollout.
- **Legacy `line_name`:** in RA 2.0 every team must have a Line; historical SCD2 intervals from pre-2.0 exports may still show `line_name IS NULL`. Filter `line_name IS NOT NULL` when the question assumes the current model. DataHub and Databricks already expose `line_name`; the Hive-synced Trino table may lag — TARS golden queries for “who is allocated now” use `group_name` + `tag_name` and omit `line_name` until Hive catches up.
- **No overlap guardrails with PIN:** `chapter`, `vertical`, and `team` on the fact come from the tool's PIN seed and may duplicate or contradict PIN-owned classifications — nothing validates consistency.
- **FTE is equal-split only:** within a team, each active project tag gets `1/N` of the employee's capacity; arbitrary percentages are out of scope.
- **FTE is not additive across teams:** an employee in two teams contributes up to 1.0 FTE in each team separately — do not sum across teams as total headcount.
- **Project tag names may repeat across teams:** aggregate by `tag_name` only when the question is project-scoped across teams; for team-level detail, use `id_tag` or `(id_group, tag_name)`.
- **Tag assignment history vs Line history:** `tag_name` / `id_tag` per allocation interval are historized from daily snapshots (e.g. employee moved from tag X to tags A and B). `line_name` is resolved from current `groups` at enrich time — past Line membership of a team is not yet historized (see DBP-2106).

## TARS / Trino scope

**Catalog:** `delta`. In Trino, qualify the fact as `hive.dw_workforce_allocation.fact_workforce_allocations` (DataHub URN path). A two-part name can resolve to a stale Hive schema.

| Table | What it contains |
|-------|------------------|
| `dw_workforce_allocation.fact_workforce_allocations` | SCD2 allocation history with precomputed `allocation_fte`, Line/team/project dimensions (`line_name`, `group_name`, `tag_name`), and read-only org attributes (`chapter`, `vertical`, `team`). No PII. **Only table in this domain for TARS and business consumers.** Link this table as the primary Data Product asset — do not attach Team Formation or assignment-snapshot tables to this product. |

`datalake_people.allocation_history` (Databricks enrich) is restricted to the **technical team** for pipeline debugging and modeling — do not query it from TARS or direct business users to it.

### Do not confuse `dw_workforce_allocation` with `dw_people`

Both schemas live under People and reuse words like **line**, **chapter**, **team**, and **person_number** — but they answer **different questions**. TARS must pick the schema from the **business intent**, not from shared column labels.

| If the question is about… | Start here | Do **not** use |
|---------------------------|------------|----------------|
| Project tags, allocated FTE, allocation history, planning scenarios, “who is on IPO?” | `dw_workforce_allocation.fact_workforce_allocations` | `dw_people` tables as the primary source |
| Official active org: manager chain, hire date, cost center, P&T Team Formation roster | `dw_people` — see [`people_public.md`](people_public.md) | `fact_workforce_allocations` |
| Employee **name** or work email in an allocation answer | Join `dw_people.dim_employee` on `person_number` **after** filtering the fact | `dim_employee` alone (no allocation rows) or `employee_details` for names |
| “Which team is person X on?” (org / squad, no project tag) | `dw_people.dim_product_tech_team` or cost center + manager | `group_name` on the allocation fact |
| “Line” / “chapter” / “team” on the allocation export | `line_name`, `group_name`, `tag_name`, or PIN-seed `chapter` / `team` on the **fact** | `dim_product_tech_team.line` / `chapter` / `team_1`…`team_10` |
| Company active headcount | `dw_people.fact_employees` or `dim_employee` | `COUNT(*)` on the allocation fact (subset of employees with tags) |
| Headcount **allocated** to a project tag | `COUNT(DISTINCT person_number)` on the **fact** | `dim_product_tech_team` or `fact_employees` |

**Same word, different meaning:**

| Term | In `dw_workforce_allocation` | In `dw_people` |
|------|-------------------------------|----------------|
| **Line** | Macro group (`line_name`) from the Allocation Tool | P&T line (`dim_product_tech_team.line`) from Team Formation sheet |
| **Team** | Allocation Tool group (`group_name`, `id_group`) | P&T squad slot (`team_1`…`team_10`) or cost-center placement |
| **Chapter** | PIN seed on the export (`chapter` column on the fact) | P&T chapter (`dim_product_tech_team.chapter`) |
| **Tag / project** | Project label (`tag_name`) — planning only | **Not** in `dw_people` |

When a question mixes allocation and identity (e.g. “names on tag IPO”), **anchor on the fact**, then join `dim_employee` for display fields only — never reverse the flow (starting from `dw_people` and inferring allocations).

### TARS routing triggers

Apply **in order** (see disambiguation tables above for column mapping):

1. **Access** — missing **Data Contract - People - Allocation**? Answer only from [`people_public.md`](people_public.md) (`dw_people`). Do **not** infer project tags or allocation FTE from `dim_product_tech_team` or cost center.
2. **Intent** — org/squad placement → `dw_people`; project planning / tags / FTE → this entity. Keywords below are tiebreakers when intent is unclear.
3. **Homonyms** — when `team`, `time`, `line`, or `chapter` appear, classify intent before picking a table or column.

**Canonical routing (same person, different intent):**

| Question pattern | Route to | Notes |
|------------------|----------|-------|
| Which **team** is person X on? / em qual **time** a pessoa está? | `dw_people` — `dim_product_tech_team` (P&T) or cost center + manager (non–P&T) | Official org / squad — **not** Allocation Tool `group_name` |
| Which **projects** is person X on? / em quais **projetos** a pessoa está? | `dw_workforce_allocation.fact_workforce_allocations` | Filter `person_number`, `is_active = TRUE`; list `tag_name`, `group_name`, `line_name` |
| Who is allocated to an **IPO** tag / pessoas alocadas a uma tag de IPO | `dw_workforce_allocation.fact_workforce_allocations` | Filter `is_current = TRUE`, `is_active = TRUE`, `LOWER(tag_name) LIKE '%ipo%'`; join `dim_employee` for names — **not** Org Chart `product_and_tech_team_*` |
| Names with either answer above | Join `dw_people.dim_employee` on `person_number` | Only when the requester has `dw_people` access |

**Ambiguous patterns — resolve by intent, not by shared words:**

| User says | Likely intent | Route |
|-----------|---------------|-------|
| em qual **time** a pessoa X está? / which **team** is person X on? | Org / squad placement for one person | `dw_people` |
| em quais **projetos** a pessoa X está? / which **projects** is person X on? | Planning tags for one person | `fact_workforce_allocations` |
| **people on team** [Allocation group] / pessoas do time [grupo da ferramenta] | Roster of an Allocation Tool **group** | `fact_workforce_allocations` — filter `group_name`; join `dim_employee` for names |
| **people on squad** X / time P&T / Team Formation / `team_1`…`team_10` | Official P&T roster | `dw_people.dim_product_tech_team` |
| **chapter** within Line + tags/FTE/allocation context | PIN seed on the export | `fact_workforce_allocations` — `chapter`, `line_name` |
| **chapter** / capítulo **of person** X (P&T attribute, no tag/FTE) | Team Formation | `dw_people.dim_product_tech_team.chapter` |
| **Line** / linha in allocation or IPO distribution context | Allocation Tool macro group | `fact_workforce_allocations` — `line_name` |
| **Line** / linha as P&T person attribute | Team Formation | `dim_product_tech_team.line` |

**Access-gated behavior:**

- **Has** `dw_workforce_allocation` access → allocation, project-tag, and FTE questions use this entity.
- **Lacks** `dw_workforce_allocation` access → do **not** query or proxy allocation data; answer team/org/placement from `dw_people` when possible and state that project-allocation answers require the Allocation data contract on IDN.
- Allocation Tool UI access alone does **not** imply TARS can read `dw_workforce_allocation`.

**Route here** when intent is **planning / allocation / project** — EN: allocation, allocated, allocate, workforce allocation, resource allocation, allocation tool, planning scenario, project tag, which projects, projects for person, tag allocation, allocation history, tag history, tag transition, allocated FTE, FTE on project, distribution by project, who is on [project], people on team [group] (with tags/FTE context), tag completeness, IPO (allocated / distribution), who is on IPO, people allocated to a tag.

**Route here** — PT: alocação, alocado, alocada, pessoas alocadas, ferramenta de alocação, tag de projeto, tag de IPO, **em quais projetos**, projetos da pessoa, histórico de tag, FTE alocado, distribuição por projeto, quem está no [projeto], pessoas do time [grupo] (com contexto de tag/FTE), completude de tag, IPO (alocado / distribuição).

**Do not route here** — use `dw_people` for **org / squad placement** without project-allocation intent:

- which team is person X on, em qual time (placement), squad, Team Formation, P&T roster, org chart
- manager, reports to, hire date, tenure, cost center, company active headcount
- `team_1`…`team_10`, line leader, team leader, capítulo do colaborador (P&T sheet semantics)

**Homonym quick reference:** `team`/`time` + **where person belongs (org)** → `dw_people`. `team`/`time` + **Allocation Tool group roster or tags/FTE** → this entity. `project`/`projeto` → this entity unless clearly cost center or job family. `chapter` → P&T person attribute in `dw_people`; PIN-seed `chapter` on the fact when the question is allocation-scoped.

## Glossary and Synonyms

| Term | Meaning | Notes |
|------|---------|-------|
| **Pessoas alocadas / people allocated / who is allocated** | Employees linked to a project tag in the Allocation Tool | Start at `fact_workforce_allocations`; join `dw_people.dim_employee` for `name` |
| **Tag de IPO / IPO tag / IPO-readiness / who is on IPO?** | Project tag whose name contains IPO (canonical example: `IPO-readiness`) | `LOWER(tag_name) LIKE '%ipo%'` or `tag_name = 'IPO-readiness'`; **not** Team Formation `team_1`…`team_10` |
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
| Which people are allocated to an IPO tag (pessoas alocadas a uma tag de IPO) | `dw_workforce_allocation.fact_workforce_allocations` + `dw_people.dim_employee` on `person_number`; filter `is_current = TRUE` and `is_active = TRUE`; `LOWER(tag_name) LIKE '%ipo%'` — **neither** |
| Historical workforce allocation by employee, Line, team, project, and point in time | `dw_workforce_allocation.fact_workforce_allocations` — **neither** (workforce allocation) |
| Active allocated FTE by macro group / Line (`line_name`) | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; aggregate by `line_name`, filter `is_active = TRUE` |
| Active allocated FTE by team / Allocation Tool group (`group_name`) | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; aggregate by `group_name` or `id_group`, filter `is_active = TRUE` |
| Active allocated FTE by project tag (`tag_name`) within a team | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; aggregate by `line_name`, `group_name`, `tag_name`, filter `is_active = TRUE` |
| Which teams (and Lines) are allocated to a project (e.g. IPO) | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; filter `tag_name` (exact or `ILIKE`), group by `line_name`, `group_name`, `tag_name` |
| Which project tags an employee held on a reference date | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; filter `person_number` and `DATE '<ref>' BETWEEN dt_valid_from AND dt_valid_to` |
| How an employee's project tags changed over time (tag history / transitions) | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; filter `person_number`, order by `dt_valid_from`, show `tag_name`, `group_name`, validity columns |
| Headcount allocated to a project tag (overall or by chapter) | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; `COUNT(DISTINCT person_number)` by `tag_name` and optionally `chapter` |
| Names of people allocated to a project tag | `dw_workforce_allocation.fact_workforce_allocations` + `dw_people.dim_employee` — join on `person_number`; see [people_public.md](people_public.md) |
| Teams belonging to a Line (Allocation Tool) | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; `DISTINCT group_name` filtered by `line_name` |
| How many Lines exist in the Allocation Tool model | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; `COUNT(DISTINCT line_name)` |
| People on a team or on a chapter within a Line (with names) | `fact_workforce_allocations` + `dw_people.dim_employee` — filter `group_name` or `line_name` + `chapter`, join on `person_number` |
| Project FTE rolled up across teams (same project tag name) | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; aggregate `allocation_fte` by `tag_name` only when a single company-wide total is requested |
| Current allocation state (no reference date) | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; filter `is_current = TRUE` |
| PIN-seeded org attributes on the allocation export | `dw_workforce_allocation.fact_workforce_allocations` — **neither**; columns `chapter`, `vertical`, `team` (not allocation teams or project tags) |
| Official Product & Tech team / line / chapter (Team Formation) | Not this entity — see [people_public.md](people_public.md) |
| Employee identity, headcount, or assignment history | Not this entity — see [employee_details.md](employee_details.md) |

---

## Key Metrics

When the question asks for an official, MBR, or OKR number, use a linked metric-entity doc — do not compute it from this entity's tables.

### Component / exploratory metrics

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

## Relationships with other entities

- **Workforce Allocation → Employee Details:** join on `person_number` (stable business key) or `sk_employee` when not `-1`.
- **Workforce Allocation → People Public:** join `person_number` to `dw_people.dim_employee` for **active employee names** (`name`) and work email. The fact stores identifiers only — never join `employee_details` for names when `dw_people` suffices. See [`people_public.md`](people_public.md).
- **Workforce Allocation ↔ Team Formation:** allocation tags are planning/simulation data; official P&T squad/line/chapter is in `dw_people.dim_product_tech_team` — do not substitute one for the other without stating the source.
- **SCD2 model:** `dt_valid_from` and `dt_valid_to` bound each interval; `is_current = TRUE` marks the open interval (`dt_valid_to = DATE '9999-12-31'`).

## Dos and don'ts

**Do:**

- Filter `<date> BETWEEN dt_valid_from AND dt_valid_to` for point-in-time analysis, or `is_current = TRUE` for the latest state.
- Filter `is_active = TRUE` when calculating current allocated FTE or active allocation counts.
- Aggregate `allocation_fte` within a **single team** (`id_group`) when reporting team-level FTE; interpret cross-team sums as planning views, not headcount.
- For project-scoped questions (“distribution by project”, “teams on IPO”), filter `tag_name` and group by `line_name`, `group_name`, `tag_name` — show Line and team, not only the project total.
- For tag-history questions (“which tags on date D?”, “had tag X, now A and B”), filter `person_number` and use `BETWEEN dt_valid_from AND dt_valid_to` for a single date, or list all intervals ordered by `dt_valid_from` for a timeline.
- Use a `tag_name`-only rollup only when the user explicitly asks for a single company-wide project total.
- Join project tags on `id_tag` or `(id_group, tag_name)` for team-level detail.
- Treat `sk_employee = -1` as an unresolved Allocation Tool employee mapping.
- Join `dw_people.dim_employee` on `person_number` when the question asks for **names** or a named roster (active employees only).
- Use `dw_workforce_allocation.fact_workforce_allocations` for all allocation analysis in TARS.
- When names are needed, join `dw_people.dim_employee` on `person_number` — keep allocation logic on the fact.

**Don't:**

- Answer allocation, project-tag, FTE, “pessoas alocadas”, or “tag de IPO” questions from Employee Details, Org Chart, or Team Formation — those schemas have no project tags.
- Use `dim_product_tech_team` line/chapter/team as a substitute for `line_name` / `group_name` / `tag_name` on the fact.
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

Names of people currently allocated to an IPO project tag (**canonical TARS pattern** — “quais pessoas estão alocadas a uma tag de IPO”). Validated on Hive Trino with `is_current = TRUE`, `is_active = TRUE`, and `LOWER(tag_name) LIKE '%ipo%'`. Omits `line_name` because that column may be missing on the Hive-synced Trino table.

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

In Trino (catalog `delta`), qualify as `hive.dw_workforce_allocation.fact_workforce_allocations` and `hive.dw_people.dim_employee`. Canonical tag example: `tag_name = 'IPO-readiness'`.

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

### Planning questions — headcount and names on a project tag

Headcount allocated to a project tag (overall):

```sql
SELECT
    COUNT(DISTINCT person_number) AS allocated_employees
FROM dw_workforce_allocation.fact_workforce_allocations
WHERE DATE '2026-08-28' BETWEEN dt_valid_from AND dt_valid_to
    AND is_active = TRUE
    AND tag_name ILIKE '%IPO%'
```

Headcount allocated to a project tag by chapter:

```sql
SELECT
    chapter,
    COUNT(DISTINCT person_number) AS allocated_employees
FROM dw_workforce_allocation.fact_workforce_allocations
WHERE DATE '2026-08-28' BETWEEN dt_valid_from AND dt_valid_to
    AND is_active = TRUE
    AND tag_name ILIKE '%IPO%'
GROUP BY chapter
ORDER BY allocated_employees DESC, chapter
```

Names of people allocated to a project tag (join public `dw_people`):

```sql
SELECT
    wa.line_name,
    wa.group_name,
    wa.tag_name,
    wa.chapter,
    emp.person_number,
    emp.name
FROM dw_workforce_allocation.fact_workforce_allocations AS wa
INNER JOIN dw_people.dim_employee AS emp
    ON wa.person_number = emp.person_number
WHERE DATE '2026-08-28' BETWEEN wa.dt_valid_from AND wa.dt_valid_to
    AND wa.is_active = TRUE
    AND wa.tag_name ILIKE '%IPO%'
ORDER BY wa.line_name, wa.group_name, emp.name
```

`dim_employee` lists **active** employees only. Use `person_number` when someone is not in the public roster.

### Planning questions — Lines, teams, and org on the Allocation Tool model

Teams and Lines with people allocated to a project tag:

```sql
SELECT
    line_name,
    group_name,
    tag_name,
    COUNT(DISTINCT person_number) AS allocated_employees
FROM dw_workforce_allocation.fact_workforce_allocations
WHERE DATE '2026-08-28' BETWEEN dt_valid_from AND dt_valid_to
    AND is_active = TRUE
    AND tag_name ILIKE '%IPO%'
GROUP BY line_name, group_name, tag_name
ORDER BY line_name, group_name, allocated_employees DESC
```

Teams (Allocation Tool groups) belonging to a Line:

```sql
SELECT DISTINCT
    line_name,
    group_name
FROM dw_workforce_allocation.fact_workforce_allocations
WHERE is_current = TRUE
    AND is_active = TRUE
    AND line_name = 'For Rent'
    AND line_name IS NOT NULL
ORDER BY group_name
```

Returns teams that appear in active allocations. Teams with no allocated people may be absent.

How many Lines exist in the Allocation Tool model:

```sql
SELECT
    COUNT(DISTINCT line_name) AS line_count
FROM dw_workforce_allocation.fact_workforce_allocations
WHERE is_current = TRUE
    AND is_active = TRUE
    AND line_name IS NOT NULL
```

People on a given team (with names):

```sql
SELECT
    wa.line_name,
    wa.group_name,
    emp.person_number,
    emp.name,
    wa.tag_name,
    wa.allocation_fte
FROM dw_workforce_allocation.fact_workforce_allocations AS wa
INNER JOIN dw_people.dim_employee AS emp
    ON wa.person_number = emp.person_number
WHERE wa.is_current = TRUE
    AND wa.is_active = TRUE
    AND wa.group_name = 'Billing & Payments'
ORDER BY emp.name, wa.tag_name
```

People on a given chapter within a Line (with names):

```sql
SELECT
    wa.line_name,
    wa.chapter,
    wa.group_name,
    emp.person_number,
    emp.name,
    wa.tag_name
FROM dw_workforce_allocation.fact_workforce_allocations AS wa
INNER JOIN dw_people.dim_employee AS emp
    ON wa.person_number = emp.person_number
WHERE wa.is_current = TRUE
    AND wa.is_active = TRUE
    AND wa.line_name = 'For Rent'
    AND wa.chapter = 'Engineering'
ORDER BY wa.group_name, emp.name, wa.tag_name
```

`chapter` on the fact comes from the Allocation Tool export (PIN seed), not from Team Formation.

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

> **Note:** Replace the literal reference date. In Trino, catalog is `delta`; qualify tables as `hive.dw_workforce_allocation.fact_workforce_allocations` and `hive.dw_people.dim_employee`. Date literals use `DATE 'YYYY-MM-DD'`. Prefer `LOWER(tag_name) LIKE '%ipo%'` over `ILIKE` in TARS SQL. When Hive still lacks `line_name`, keep that column out of the SELECT.

## DataHub catalog

- **Data Product:** Published from this Markdown by the repository DataHub metadata workflow.
- **Dataset:** `dw_workforce_allocation.fact_workforce_allocations`
