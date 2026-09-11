# Employee Details

## Ownership

**Data Owner:**
- pedro.prates@quintoandar.com.br

**Data Steward:**
- isabella.araujo@quintoandar.com.br
- gabriel.berger@quintoandar.com.br

## Overview

Employee Details (`dw_employee_details`) is the primary internal People DW schema for workforce identity, contact and legal documentation, emergency contacts, management hierarchy, and daily assignment snapshots. It is the starting point for headcount, tenure, admissions, exits, and org-structure analysis within the People domain.

**Access (exclusive — People team only):** `dw_employee_details` is **not** a general-purpose dataset. Databricks/Trino access is **exclusive to the People team** and is granted **only on request through IDN**, with People data-owner approval. **Do not** direct analysts, TARS, or other consumers to open an IDN access request for this schema unless they are on People with a justified use case. For active-workforce org questions, use [`people_public.md`](people_public.md) (`dw_people`) instead.

**Population:** all current and former employees with a valid HR assignment (contractors and full-time). Test users and automated system accounts are excluded.

**Source:** PIN (Oracle HCM) — single source of truth for personal data, documents, contacts, assignments, and reporting structures.

**SLA:** D-1, available by 08:00 BRT. DAG: `bietlejuice.dw_employee_details`.

**Temporal model:** mixed. `dim_employee` is current state only. Contact, documentation, emergency contact, and hierarchy dimensions are SCD Type 2 validity windows (`dt_valid_from` / `dt_valid_to`). `fact_assignment_snapshots` is a daily snapshot — one row per `assignment_number` per calendar day.

**Out of scope (sibling schemas):** compensation → `dw_compensation`; cost center / BU / job definitions → `dw_organization`; DE&I self-declared attributes → `dw_demographics` (stricter access). **Project tags, allocated FTE, “pessoas alocadas”, “tag de IPO”** → Workforce Allocation (`workforce_allocation.md`) — not assignment snapshots and not Team Formation.

Sensitive personal data (CPF, address, legal name, marital status) lives here under restricted access. Prefer `dim_employee.name` (preferred name) for display; use `dim_documentation` only for compliance contexts.

For the full business-facing schema guide, see `dags/people/dw_employee_details/docs/dw_employee_details.md`.

## Known Limitations

PIN went live on **2024-03-01**; before that date, only `dt_employee_hired` and `dt_terminated` are reliable. Job, cost center, management hierarchy, workforce population attributes, and derived fields such as `is_effective_worker` may be inconsistent because the source system was not yet live.

- For every workforce metric or descriptive statistic — including `MIN`, `MAX`, `AVG`, `SUM`, counts, median, percentiles, rates, distributions, trends, and period comparisons — use only records on or after `2024-03-01`. The requested analysis period must start on or after this date; never mix pre-go-live records into an aggregate.
- Pre-go-live hire and termination dates may be returned as individual date facts, but they are not sufficient to reconstruct a reliable historical population or calculate workforce metrics.
- If a question requires any pre-go-live period, explain the PIN source-system limitation and direct the user to **People Insights** or **Enterprise Engineering** instead of approximating the result.

## TARS pilot scope (restricted audience)

**Status:** pilot — validate in Trino before broader publication. Access is **exclusive to the People team** via **IDN request**; not available to general analytical consumers.

**Trino catalog:** `delta` — only the tables below are registered for this pilot. No salary or compensation data in any of them (`dw_compensation` is out of scope).

| Table | What it contains |
|-------|------------------|
| `fact_assignment_snapshots` | Headcount, tenure, status flags, span of control, hire/termination dates. No PII columns on the fact itself. |
| `dim_employee` | Preferred name, work email, birth date, education, generation. **PII** (LGPD: birth date). |
| `dim_management_hierarchy` | Reporting chain L0–L9 (CEO → employee) with manager name and work email per level. **PII** (managers). |
| `dim_termination` | Assignment-termination event catalog (action + reason labels). No individual employee data. |

Join to `organization.md` tables for cost center, BU, and job context (`sk_cost_center_version`, `sk_business_unit`, `sk_job_version` on the fact).

**Not in this pilot (Databricks-only):** `dim_contact`, `dim_documentation`, `dim_emergency_contact`, `metric_people.employee_snapshots`, `dw_compensation`, `dw_demographics`.

## Related Domain Entities

- `organization.md` — cost center, business unit, and job reference dimensions joined via `sk_cost_center_version`, `sk_business_unit`, and `sk_job_version` on the fact.
- `people_public.md` — **preferred** public active-workforce DW (`dw_people`) replacing `org_chart` for new consumers; **Product & Tech team formation** lives there (`dim_product_tech_team`).
- `org_chart.md` — legacy lightweight current org chart (`datalake_people_public.org_chart`) during migration.
- `workforce_allocation.md` — **project tags**, allocated FTE, “pessoas alocadas”, “tag de IPO”, Allocation Tool Lines/teams. This schema has **no** project tags — do not answer IPO / allocation-roster questions from assignment snapshots or Team Formation.

## Teams / org placement

`dw_employee_details` has **management hierarchy** and **cost center** (via `organization.md`), but it does **not** store Product & Tech squad / line / chapter from the team-formation sheet.

| Need | Where |
|------|--------|
| Product & Tech line, chapter, teams, leaders | `dw_people.dim_product_tech_team` (wide) — see [`people_public.md`](people_public.md) |
| Manager chain / who reports to whom (history-capable) | `dw_employee_details.dim_management_hierarchy` (+ fact FKs) |
| Cost center / BU / job labels | [`organization.md`](organization.md) via fact SKs |
| Active-only public “which team?” without history | Prefer [`people_public.md`](people_public.md) end-to-end |
| People allocated to a project tag / tag de IPO / pessoas alocadas | [workforce_allocation.md](workforce_allocation.md) — not this schema |

**Product & Tech filter example** (join on `person_number`; dim is **active-only** and **wide** — one row per person):

```sql
SELECT
    emp.person_number,
    emp.name,
    pt.line,
    pt.chapter,
    pt.team_1,
    pt.team_2,
    pt.team_leader,
    pt.is_team_leader
FROM dw_employee_details.dim_employee AS emp
INNER JOIN dw_people.dim_product_tech_team AS pt
    ON emp.person_number = pt.person_number
WHERE emp.person_number = '<person_number>'
```

If the person has **no** dim row, they are outside the Product & Tech roster — do not invent a squad. For team / org-placement answers, use cost center + manager + direct reports (full playbook in [`people_public.md`](people_public.md)).

## Related Metric Entities

- [Turnover](../metric_entities/turnover.md) — Global Turnover, New Hire Attrition, early-tenure attrition (6/12-month), and Voluntary/Involuntary turnover.

## Glossary and Synonyms

- **Employee / worker / workforce member / FTE / contractor** (colaborador, funcionário) → `dim_employee` / `fact_assignment_snapshots`; contractors and full-time included when they have a valid assignment
- **Headcount / active workforce / FTE count / quadro** → `COUNT(DISTINCT person_number)` on `fact_assignment_snapshots` where `is_current_for_employee = TRUE` and `is_active = TRUE`; the same two flags are the correct filter for row-level (not distinct-counting) queries too
- **Monthly snapshot / month-end headcount / base fotografias** → `fact_assignment_snapshots` with `is_monthly_snapshot_for_employee = TRUE` (default, one row per employee per month); use `is_monthly_snapshot_for_assignment = TRUE` only when you specifically need assignment-grain history
- **Current state / latest snapshot / as-of today / base completa** → `fact_assignment_snapshots` with `is_current_for_employee = TRUE`; use `is_current_for_assignment = TRUE` only when you specifically need assignment-grain history (an employee can have multiple `is_current_for_assignment` rows across past assignments)
- **Snapshot date / as-of date / reference date** → `dt_reference` on the fact (one row per assignment per calendar day)
- **Person number / employee ID / HR ID / matrícula** → `person_number` — stable business key across assignments
- **Assignment / employment record / vínculo** → `assignment_number`; one person may have multiple after internal transfers
- **Primary assignment** → `is_primary_assignment_for_snapshot = TRUE` when multiple assignments overlap on the same date
- **Preferred name / display name / social name / nome social** → `dim_employee.name` (not `dim_documentation.legal_name`, Databricks-only)
- **Work email / corporate email** → `dim_employee.work_email`
- **Birth date / date of birth** → `dim_employee` (PII; LGPD-sensitive)
- **Education level / highest education / generation** → `dim_employee.highest_education_level`, `dim_employee.generation`
- **Assignment start / start date / admissão (current contract)** → `dt_assignment_started` (current assignment only; restarts on both internal transfers and rehires)
- **Company hire date / original hire / tenure start** → `dt_employee_hired` (current continuous cycle; stays across internal transfers, resets on a genuine rehire — use for company tenure)
- **Tenure / time in company / time in role** → two kinds of tenure on the fact, both relative to `dt_reference`. **Employee tenure** (`days_employee_tenure`, `months_employee_tenure`) is company time anchored on `dt_employee_hired`: it keeps counting across internal transfers and resets only on a genuine rehire — the default for tenure questions. **Assignment tenure** (`days_tenure_in_assignment`) is time in the current assignment anchored on `dt_assignment_started`: it restarts on every transfer or rehire — use it for "time in current role/contract" questions.
- **Employee country / country / país** → `fact_assignment_snapshots.business_unit_country` (job/business-unit country, e.g. Brazil, Mexico, Portugal) — the default for "employee country" questions, not `dw_compensation.dim_job.country` and not address country. Residence → `dim_contact.address_country` (Databricks-only); birth → `dim_documentation.birth_country` (Databricks-only)
- **Termination / separation / offboarding / exit / turnover / demissão** → a real company exit is `termination_type IS NOT NULL`; use `dt_terminated` for the date and join `dim_termination` via `sk_termination_event_definition` for action/reason labels. For the official turnover rate, follow `../metric_entities/turnover.md`
- **Intern / Estagiário / Young Apprentice / Jovem Aprendiz / JA** → `dw_employee_details.dim_job.employment_type` (`'intern'`, `'young apprentice'`; lowercase), reached via `fact.sk_job_version = dim_job.sk_job_version`. `NULL` reflects an unmapped `job_family` (legacy job codes) and counts as regular population, not Intern/JA. To exclude Interns/JA without the join, use `is_effective_worker = FALSE` on the fact (effective/CLT employees are `is_effective_worker = TRUE`)
- **Termination type / voluntary vs involuntary / tipo de desligamento** → `termination_type` on the fact: `voluntary`, `involuntary`, `pending` (a real exit not yet classified), or `NULL` (not a company exit). Any non-NULL value is a real exit; slice by value for the voluntary/involuntary split
- **Voluntary termination / resignation / quit / pedido de demissão** → `termination_type = 'voluntary'` on the fact; `dim_termination` (`action_name`, `reason_name_ptb`) gives the detailed reason
- **Involuntary termination / dismissal / firing** → `termination_type = 'involuntary'` on the fact
- **Layoff / reorganization exit / restructuring** → `is_reorganization_termination = TRUE` on the fact (set only on the terminated snapshots of a reorganization exit)
- **Future / scheduled termination / desligamento futuro** → `dt_terminated` in the **future** while still active. These rows are **voluntary only** and can be reported in advance. Involuntary exits never appear with a future date — report them only after `dt_terminated` has passed (do not infer notice timing separately)
- **HR movement / lifecycle event / action & reason** → `dim_termination`; join via `sk_termination_event_definition` on the fact
- **Reporting chain / management hierarchy / org chart / hierarquia** → `dim_management_hierarchy` (`name_l0` … `name_l9`, `assignment_number_l0` … `assignment_number_l9`)
- **Product & Tech team / squad / line / chapter (P&T)** → **not** in `dw_employee_details` — use `dw_people.dim_product_tech_team` ([`people_public.md`](people_public.md)); wide `team_1`…`team_10`
- **CEO / L0 / top-level manager** → `name_l0`, `email_l0` (Layer 0)
- **VP / director / manager (by level)** → `name_l1` (VP), `name_l2` (director), `name_l3` (manager), etc.
- **Direct manager / line manager** → immediate level in hierarchy (lowest non-empty `name_l*` for the employee's chain)
- **Span of control / direct reports / team size** → `count_direct_report` on the fact
- **Indirect reports** → `count_indirect_report`; **total reports** → `count_total_report`
- **Manager / people manager** → `is_manager = TRUE`
- **Leadership Team / LT / liderança** → `is_leadership_team_member = TRUE` (band 10+ or EXEC)
- **Executive Team / ET** → `is_executive_team_member = TRUE` (L0/L1 in hierarchy and band 14+)
- **Internal transfer / mobility / transferência interna** → `is_transfer_hire = TRUE` (flag on the **new** assignment created by the transfer — the incoming side, symmetric to `is_transfer_termination`)
- **Global Transfer / transfer termination event / transferência** → `dim_termination.action_name = 'Global Transfer'` on the old assignment's termination event — an internal move, **not** a real exit; must be excluded from dismissals and turnover
- **Transfer termination / assignment closed by transfer** → `is_transfer_termination = TRUE` (flag on the **old** assignment closed by a Global Transfer) — the simplest way to exclude internal transfers from termination and turnover counts without joining `dim_termination`
- **Intern/apprentice effectivation / efetivação** → `is_effectivation_hire = TRUE` on the incoming assignment and `is_effectivation_termination = TRUE` on the closed intern/apprentice assignment. Effectivation is a PIN conversion event and does not always produce a permanent CLT role — use `is_effective_worker` on the incoming assignment when counting new effective hires
- **Termination count / desligamentos (default)** → real company exits: `termination_type IS NOT NULL` with `is_effective_worker = TRUE`. Internal transfers, expatriate movements, and effectivation closures are already `termination_type = NULL`, so they are excluded automatically. To **include Interns/Young Apprentices**, drop the `is_effective_worker` filter
- **New hire / admission / genuine hire / admissão** → a genuine company admission with `is_effective_worker = TRUE`: either `dt_employee_hired` is within the period with `is_transfer_hire = FALSE`, or an intern/apprentice effectivation has `is_effectivation_hire = TRUE` and `dt_assignment_started` within the period. Internal transfer-ins do not count. Count per month with `COUNT(DISTINCT person_number)`
- **Turnover flag / real exit / leaver flag** → `termination_type IS NOT NULL` with `is_effective_worker = TRUE` (a real company exit; internal transfers, expatriate movements, and effectivations are `termination_type = NULL` and excluded). Add `NOT COALESCE(is_reorganization_termination, FALSE)` for the official layoff-excluded turnover. For the official rate, follow `../metric_entities/turnover.md`
- **Effective worker / efetivo (excludes interns & apprentices)** → `is_effective_worker = TRUE` (excludes Interns and Young Apprentices). Filter for official turnover and headcount
- **Turnover denominator / headcount base** → the official denominator is **average monthly headcount** = (start-of-month + end-of-month) / 2, where start-of-month = end-of-month actives + month terminations − month new hires; every input must use `is_monthly_snapshot_for_employee = TRUE`. See `../metric_entities/turnover.md`
- **Validity window / SCD2 version** → `dt_valid_from` / `dt_valid_to` on hierarchy (and other SCD2 dims); `is_current = TRUE` for latest hierarchy version
- **OBT / wide employee snapshot** (not in TARS pilot) → `metric_people.employee_snapshots`

## Tables

| You need... | Use this table |
|-------------|----------------|
| Current employee identity (name, work email, education, generation) | `dw_employee_details.dim_employee` (`emp`) — **TARS pilot**; current state, grain: one row per employee |
| Daily workforce history (tenure, headcount flags, org FKs) | `dw_employee_details.fact_assignment_snapshots` (`fact`) — **TARS pilot**; grain: one row per assignment per `dt_reference`; scope with `is_current_for_employee` (current) or `is_monthly_snapshot_for_employee` (historical) |
| Contact info history (phone, address, GitHub) | `dw_employee_details.dim_contact` — **not in TARS pilot** (Databricks-only); validity window; join via `sk_contact_version` from the fact |
| Legal documents (CPF, RG, legal name, marital status) | `dw_employee_details.dim_documentation` — **not in TARS pilot** (Databricks-only); validity window; join via `sk_documentation_version` |
| Emergency contacts | `dw_employee_details.dim_emergency_contact` — **not in TARS pilot** (Databricks-only); validity window; join via `sk_emergency_contact_version` |
| Termination reasons (action + reason, EN/PT) | `dw_employee_details.dim_termination` — **TARS pilot**; current state; join via `sk_termination_event_definition` |
| Management chain up to CEO | `dw_employee_details.dim_management_hierarchy` — **TARS pilot**; validity window; join via `sk_hierarchy_version` |
| Wide employee picture across domains | `metric_people.employee_snapshots` — **not in TARS pilot**; official OBT joining compensation, demographics, org, and more |
| People allocated to a project tag / tag de IPO / pessoas alocadas | Not this entity — see workforce_allocation.md |

**Main join identifiers:** `sk_employee` (preferred FK), `person_number` (business key), `assignment_number` (assignment-level key).

**Critical rules:**
- **TARS pilot (Trino `delta`):** only `fact_assignment_snapshots`, `dim_employee`, `dim_termination`, and `dim_management_hierarchy` from this schema. No salary data. Restricted audience until pilot sign-off.
- **Default approach:** for current-state analysis, filter `is_current_for_employee = TRUE`. For historical analysis, filter `is_monthly_snapshot_for_employee = TRUE`. Both are enforced defaults — use them unless you specifically need assignment grain. The default approach omits employees who were rehired and/or have multiple terminations and transfers. For these cases, use `is_current_for_assignment` and `is_monthly_snapshot_for_assignment` — they return the latest information for every assignment, so employees with 2+ assignments appear on multiple rows.
- **`is_current_for_employee = TRUE`** returns exactly one row per employee — the assignment active today, or their most recent terminated assignment if none is active today.
- **`is_monthly_snapshot_for_employee = TRUE`** returns exactly one row per employee per `dt_month_reference` — the primary assignment's monthly snapshot for that month, mirroring the legacy `base_fotografias` table.
- `sk_*_version` keys on the fact are point-in-time join keys, not permanent identifiers for an employee.
- Use `is_primary_assignment_for_snapshot = TRUE` when an employee has multiple assignments on the same date.
- `dim_management_hierarchy` exposes L0–L9 (L0 = CEO). Everyone in the same area shares the same L1 VP — filter by `name_l1`…`name_l9` without self-joins.
- The fact has no `year/month/day` partitions — expect full-table scans when unfiltered.
- **Data floor: 2024-03-01 (PIN go-live).** All workforce metrics and descriptive statistics (`MIN`, `MAX`, `AVG`, counts, percentiles, rates, distributions, and trends) must use only records from this date forward. See Known Limitations.
- **Internal transfers are not exits.** An internal move terminates the old assignment with `dim_termination.action_name = 'Global Transfer'` and opens a new `assignment_number` starting the **next day**. Never count these termination rows as dismissals, turnover, or attrition — the person remains employed. These rows carry `is_transfer_termination = TRUE`; filter it out of any termination analysis.
- **Transferred employees stay active on the transfer date.** The pipeline keeps `is_active = TRUE` (and `employment_status = 'Active'`) on the old assignment's termination date when it is a Global Transfer, so daily active headcount does not dip on batch transfer dates (e.g. 2026-01-31, ~396 Global Transfers). If a sudden single-day headcount drop still appears, check terminations on that date against `is_transfer_termination` / `action_name = 'Global Transfer'` before reporting it as attrition.
## Key Metrics

Use [Related Metric Entities](#related-metric-entities) for **official** turnover and attrition. The bullets below are **component** workforce metrics on `fact_assignment_snapshots`.

### Official metrics (metric entities)

| When you need… | Metric entity |
|----------------|---------------|
| Global Turnover, New Hire Attrition, Voluntary/Involuntary turnover | [Turnover](../metric_entities/turnover.md) |

### Component / exploratory metrics

- **Active headcount** — `COUNT(DISTINCT person_number)` where `is_current_for_employee = TRUE` and `is_active = TRUE`
- **Tenure in company** — `days_employee_tenure`, `months_employee_tenure` (relative to `dt_reference`)
- **Tenure in assignment** — `days_tenure_in_assignment` (current role only)
- **Span of control** — `count_direct_report`, `count_indirect_report` (pre-computed on the fact)
- **Real exits / leavers** — `termination_type IS NOT NULL` with `is_effective_worker = TRUE` (internal transfers, expatriate movements, and effectivations are `termination_type = NULL` and excluded); slice by `termination_type` for voluntary vs. involuntary
- **Managers vs ICs** — `is_manager`, `is_leadership_team_member`
- **Turnover / attrition** — see [Turnover](../metric_entities/turnover.md) (never approximate ad hoc); all inputs use `is_monthly_snapshot_for_employee = TRUE` only

## Relationships with Other Entities

### Organization (N:1 per snapshot date)

- Cost center: `fact.sk_cost_center_version = dw_organization.dim_cost_center.sk_cost_center_version` — the fact carries the version SK valid on `dt_reference`; do not join on date range alone.
- Business unit: `fact.sk_business_unit = dw_organization.dim_business_unit.sk_business_unit`.
- Job catalog (versioned, point-in-time): `fact.sk_job_version = dw_employee_details.dim_job.sk_job_version` — SCD Type 2; the fact already carries the version valid on `dt_reference`, no additional date filter needed. Use for historical attribution (e.g. the job/band a person held at termination).
- Job catalog (current only): `dw_organization.dim_job` (`sk_job`, SCD Type 1) — current job attributes only; do not use it for point-in-time or historical analysis.

### Compensation (N:1 per snapshot date)

- `fact.sk_compensation_version` joins to `dw_compensation.fact_compensations` for salary and band on the same `dt_reference`.

### Demographics (separate schema)

- DE&I attributes are in `dw_demographics`. Use `metric_people.employee_snapshots` or join demographics facts when needed.

## Dos and Don'ts

**Do:**
- Start from `fact_assignment_snapshots` with `is_current_for_employee = TRUE` for today's workforce state, or `is_monthly_snapshot_for_employee = TRUE` for historical state, one row per employee either way; reach for `is_current_for_assignment` / `is_monthly_snapshot_for_assignment` only when you need assignment-grain history.
- Route Product & Tech squad / line / chapter questions to `dw_people.dim_product_tech_team` ([`people_public.md`](people_public.md)); join on `person_number` (wide, one row per person).
- Use `dim_employee.name` for communications; reserve `dim_documentation.legal_name` for compliance.
- Join versioned dimensions through the `sk_*_version` keys on the fact for the snapshot date in scope.
- Use `dt_employee_hired` for company tenure (credits internal transfers, resets on rehire); `dt_assignment_started` for seniority in the current assignment only.
- Classify voluntary/involuntary with `termination_type`; use `dim_termination` (`action_name`, `reason_name_ptb`) for detailed exit-cause labels.
- Treat a future `dt_terminated` (while still active) as a scheduled termination.

**Don't:**
- Answer “pessoas alocadas”, “tag de IPO”, project-tag, or allocated-FTE questions from this schema — route to Workforce Allocation (`workforce_allocation.md`).
- Suggest or process **IDN access requests** for `dw_employee_details` for users **outside the People team** — route them to [`people_public.md`](people_public.md) (`dw_people`) instead.
- Expect Product & Tech squad / line / chapter columns on `dw_employee_details` — those live only on `dw_people.dim_product_tech_team` ([`people_public.md`](people_public.md)).
- Count `Global Transfer` termination events as dismissals or turnover — filter them out with `is_transfer_termination = FALSE`; the person remains employed under a new `assignment_number`.
- Report a single-day active-headcount drop as attrition without first checking for a `Global Transfer` batch on that date (transferred employees are kept active on the transfer date, but always verify with `is_transfer_termination`).
- Query `fact_assignment_snapshots` without a date scope — row counts inflate across every historical day.
- Report involuntary exits before `dt_terminated` has passed — see Future / scheduled termination in the glossary.
- Treat `sk_contact_version` or `sk_hierarchy_version` as stable employee identifiers.
- Assume one row per employee without `is_current_for_employee = TRUE` (current-state queries) or `is_monthly_snapshot_for_employee = TRUE` (historical queries) after internal transfers.
- Use `dim_employee` alone for point-in-time analysis — it is always overwritten to current state.
- Rely on work email history per assignment — only the most recent assignment's email is exposed in the current model.
- Expect incomplete hierarchy chains to L0 on active employees — gaps are data quality issues.
- Compute or approximate an official turnover/attrition figure without following `../metric_entities/turnover.md` — it defines the exact formula, exclusions, segments, and the safety rule for missing inputs.
- Use deprecated People sources for new queries: `datalake_hr_system`, `datalake_employment`, `greenhouse` (v1), `enrich_employee`, `enrich_hr_system`, `enrich_pin`, or the legacy `dw_employee` DAG — prefer `datalake_pin_core_clean`, `datalake_people`, and `dw_*` schemas (see `people_domain.mdc`).
- Include records before **2024-03-01** (PIN go-live) in any workforce metric or descriptive statistic, including `MIN`, `MAX`, `AVG`, counts, percentiles, rates, distributions, or trends. Only individual `dt_employee_hired` and `dt_terminated` facts are reliable before go-live; see Known Limitations.

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
    fact.termination_type,
    evt.action_name AS termination_action,
    evt.reason_name_ptb AS termination_reason,
    fact.days_employee_tenure,
    fact.is_manager,
    fact.is_leadership_team_member,
    fact.is_active,
    fact.dt_terminated
FROM dw_employee_details.fact_assignment_snapshots AS fact
INNER JOIN dw_employee_details.dim_employee AS emp
    ON fact.sk_employee = emp.sk_employee
LEFT JOIN dw_employee_details.dim_management_hierarchy AS hier
    ON fact.sk_hierarchy_version = hier.sk_hierarchy_version
LEFT JOIN dw_employee_details.dim_termination AS evt
    ON fact.sk_termination_event_definition = evt.sk_event_definition
WHERE fact.is_current_for_employee = TRUE
  AND fact.is_active = TRUE
```

## DataHub catalog

- **Data Product:** [urn:li:dataProduct:employee-details](https://datahub.apps.data-prd.habitat.zone/dataProducts/urn%3Ali%3AdataProduct%3Aemployee-details)
- **Datasets (TARS pilot):** `dw_employee_details.fact_assignment_snapshots`, `dim_employee`, `dim_management_hierarchy`, `dim_termination` — published to DataHub by CI from this Markdown (`employee_details.md` → `employee-details`).
- **People Data Catalog:** [Employee Details](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/5473992727/Employee+Details)
