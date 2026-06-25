# Reverse export — reference

Technical rules for skill **`add-people-reverse-reports-export`**. The orchestration flow (one question at a time, PT-BR) is in [SKILL.md](SKILL.md).

---

## At a glance

| You are… | Deliverables |
| --- | --- |
| **Implementing in Git** | `queries/reverse/{table_name}.sql`, `docs/{table_name}.md`, row in `reverse_reports_declaration.yml`, service-account **Editor** on tab. **Do not** add `metadata/reverse/{table}.yml` unless CI re-enables it. |
| **Migrating a notebook** | Remap to **`dw_*` first**, then **metric**; avoid enrich/clean; preserve legacy headers with `AS` when contracted. |
| **Using an agent** | Interactive flow in SKILL.md — summary confirmation before any repo edit. |
| **Editing an export** | Flow 3 in SKILL.md — pick `table_name`, confirm diff, touch SQL/docs/declaration in sync. |

---

## Source SQL: priority, metrics, and deprecation

### Default priority for `queries/reverse/*.sql`

| Priority | Use when | Examples |
| --- | --- | --- |
| **1 — DW** | Almost always | `dw_organization`, `dw_employee_details`, `dw_compensation`, `dw_demographics`, `dw_performance`, `dw_people`, `dw_learning`, `dw_payroll`, `dw_hiring`, `dw_equity`, `dw_survey` — see [`people_domain.mdc`](../../rules/people/people_domain.mdc) |
| **2 — Metrics** | Rollup / KPI already in a metric table | DAGs with `workflow.layer: metric`, often `metric_*` under `dags/` |
| **3 — Enrich / clean (avoid)** | No DW or metric path; temporary exception only | Enrich: `datalake_*` without `_clean`/`_raw`. Clean: `datalake_*_clean`. Document why in PR + ticket. |

### Do not add new references to

- `datalake_hr_system*`, `datalake_employment`
- **`greenhouse` v1** — prefer **`greenhouse_v3`**
- **`dw_employee`** — use domain **`dw_*`**
- Legacy enrich called out in `people_domain.mdc`

After remapping, summarize: *old → new + one-line reason*.

---

## SQL style (mandatory)

All SQL under `dags/people/reverse_reports/queries/reverse/` follows [`sql_conventions.mdc`](../../rules/sql_conventions.mdc):

- Formatting, explicit `AS`, column order on outer `SELECT`
- Reorder to match conventions; use aliases for legacy sheet headers
- Align `docs/{table_name}.md` column inventory with `SELECT` list
- Partitions: `year`, `month`, `day` from `{load_start_date}` — never `CURRENT_DATE()` for partitions (see `reverse_reports_declaration.yml`)

Run skill **`databricks-emr-sql-lint`** after every `.sql` edit.

---

## Export column names

**Migrated sheet (Looker, PIN, fixed headers):** final aliases = legacy header strings; reorder per `sql_conventions.mdc`.

**Net-new or approved renames:** [`naming_conventions.mdc`](../../rules/naming_conventions.mdc).

**Unclear:** default to preserving names with `AS`.

For Oracle flexfield-style PIN headers, consider `column_mapping_mode: name` (see `organization_codex_pin_sync` in declaration).

---

## Governance narrative (`docs/{table_name}.md`)

One file per sheet tab under `dags/people/reverse_reports/docs/`.

**Do not invent:** business consumer, upstream owner, why Sheets, API/integration patterns.

**Required from user (via skill questions or intake):**

- Business purpose, consumer, why Sheets (stakeholder wording) — often from [Intake inicial](SKILL.md#shared--intake-inicial)
- Business owner + technical owner
- Operational source of truth (DW tables and/or external owner)

Optional programme index (link-only) for related tabs — e.g. `codex_pin_gsheet_exports.md`.

Mirror key facts in `reverse_reports_declaration.yml` comments when helpful.

---

## Filtering `metric_people.employee_snapshots`

`employee_snapshots` is a **monthly snapshot** table. `dt_month_reference` holds the month-end reference date.

**When exporting the current state of employees** (latest snapshot, one row per active assignment), use:

```sql
WHERE
    es.is_current = TRUE
    AND es.is_primary_assignment_for_snapshot = TRUE
```

`is_current = TRUE` always resolves to the latest available snapshot regardless of when the DAG runs. Reports querying historical snapshots or specific time ranges use their own predicates on `dt_month_reference` instead.

> `dt_month_reference = CURRENT_DATE()` returns rows only on the exact calendar day that matches the month-end reference date. Use `is_current` to get the current snapshot reliably.

---

## Implementation checklist

1. **SQL** — `queries/reverse/{table_name}.sql` → `reverse_reports.{table_name}` with partition columns.
2. **Governance** — `docs/{table_name}.md` per tab.
3. **Declaration** — `tables_customization.{table_name}.extra_spark_job_arguments: [sheet_id, tab]`.
4. **Sheet ACL** — Editor for `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`.
5. **Validate** — `make validate-dag-declaration-files` and other checks the PR touches.
6. **Cutover** — after prod Airflow: comment notebook write cells; remove Daily Pipeline task if full notebook migrated.

---

## Proof requirements

### Validation runtime (mandatory)

- **Databricks only** — full People lake/DW data for reverse exports is **not** in Trino. Tier 1–3 diff queries must run on Databricks against `reverse_reports.*`, `dw_*`, and legacy notebook outputs as applicable.
- **Do not** suggest Trino, `@tars`, or skill **`trino`** for validation in this workflow — results would be incomplete or wrong.

### Validation (before Forno / PR)

User replies **validation OK** plus at least one of:

- Tier 1–3 outputs from **Databricks** (row counts, `only_in_legacy` / `only_in_migrated`, EXCEPT counts)
- Signed-off expected diffs with reasons
- Description of Databricks notebook run (user pastes numbers)

### Local Forno (before PR)

User replies **local run OK** plus task success for `{table_name}` / `load_to_gsheet`, or agent ran trigger and confirms non-empty tab.

Waivers must be explicit and documented in the PR body.

---

## Quality checks before merge

- No new deprecated People sources; DW/metric default; enrich/clean only with exception note
- SQL per `sql_conventions.mdc`; EMR-safe (no QUALIFY, etc.)
- Downstream headers match contract
- Service account Editor on production workbook
- Sane row/column volume for Sheets limits
- Governance prose matches **confirmed** stakeholders only
- Forno Airflow run succeeded (unless waived in writing)

---

## Authoritative paths

| Topic | Location |
| --- | --- |
| DW 2.0 / deprecations | [`people_domain.mdc`](../../rules/people/people_domain.mdc) |
| Declaration / service account | [`reverse_reports_declaration.yml`](../../../dags/people/reverse_reports/reverse_reports_declaration.yml) |
| `load_to_gsheet` | [`load_to_gsheet.py`](../../../dags/people/reverse_reports/spark_jobs/load_to_gsheet.py) |
| Examples | [`salary_tables.md`](../../../dags/people/reverse_reports/docs/salary_tables.md), [`jobs.md`](../../../dags/people/reverse_reports/docs/jobs.md), [`organization_codex_pin_sync.md`](../../../dags/people/reverse_reports/docs/organization_codex_pin_sync.md) |
| Validation playbook | [`exodus_validation_playbook.md`](../../../dags/people/reverse_reports/docs/exodus_validation_playbook.md) (Databricks; not Trino) |
| Cutover | [`exodus_migration_guide.md`](../../../dags/people/reverse_reports/docs/exodus_migration_guide.md) |
| Local Airflow | [`run-dag-locally`](../run-dag-locally/SKILL.md) |
| PR | [`review-pr`](../review-pr/SKILL.md), [`create-or-update-pr`](../create-or-update-pr/SKILL.md) |
| Jira kickoff / create DBP issue | [SKILL.md — Shared Jira (DBP kickoff)](SKILL.md#shared--jira-dbp-kickoff), [`dbp-jira-reference.md`](../../rules/people/dbp-jira-reference.md) |
| **DBP** | Jira project do squad **People Data** — kickoff: *"Já existe um card no board do Jira de People Data (DBP) para esse trabalho?"* (ver [`dbp-jira-reference.md`](../../rules/people/dbp-jira-reference.md) para nome legado do board) |
| **Interaction** | First turn → **AskQuestion** tool ([Flow selection](SKILL.md#flow-selection)); intake only after flows 1–2; bullets in chat ≠ AskQuestion |
| **Language** | Perguntas ao usuário → **PT-BR**; summary/description/comments no Jira → **English** |
| Jira branch | [`people-jira-branch-setup`](../people/jira-branch-setup/SKILL.md) |

---

## PR body checklist

| Topic | Content |
| --- | --- |
| Export / `table_name` | Agreed snake_case name(s) |
| Business use case | From skill Q&A |
| Sheets justification | User wording |
| Target sheet | sheet_id + tab |
| Owners / consumer | From governance Q&A |
| Sources + deprecation | DW/metric list; deprecated → replacement bullets |
| Column naming | Legacy `AS` or naming_conventions |
| Validation + Forno | Evidence or waiver |
| Governance | `docs/{table_name}.md` per tab |

---

## Minimal declaration fragment

```yaml
  tables_customization:
    example_export:
      extra_spark_job_arguments:
        - "<production_sheet_id>"
        - "<tab_name>"
```
