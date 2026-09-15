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
| **1 — DW** | Almost always | Prefer **`dw_employee_details`** for employee identity, assignments, and hierarchy (richer internal model). Also: `dw_organization`, `dw_compensation`, `dw_demographics`, `dw_performance`, `dw_time`, `dw_learning`, `dw_payroll`, `dw_hiring`, `dw_equity`, `dw_survey`. Use **`dw_people` only** when the export must match the slim **public** employee surface — see [`people_domain.mdc`](../../rules/people/people_domain.mdc) § Query preference |
| **2 — Metrics** | Rollup / KPI already in a metric table | DAGs with `workflow.layer: metric`, often `metric_*` under `dags/` |
| **3 — Enrich / clean (avoid)** | No DW or metric path; temporary exception only | Enrich: `datalake_*` without `_clean`/`_raw`. Clean: `datalake_*_clean`. Document why in PR + ticket. |

### Do not add new references to

- **`datalake_people_analytics_sandbox`** (any table) — not an approved lake path for `reverse_reports`. Legacy notebooks often use sandbox static tables (e.g. `base_quintocred_ta`, `base_completa_hierarquia`); **never** carry them into `queries/reverse/*.sql`. Remap to DW 2.0 / metric / `gsheets_people*` ingestion instead (see [Sandbox static tables](#sandbox-static-tables-never-in-reverse-sql)).
- `datalake_hr_system*`, `datalake_employment`
- **`greenhouse` v1** — prefer **`greenhouse_v3`**
- **`dw_employee`** — use domain **`dw_*`**
- **`dw_people`** for identity / active-headcount filters when **`dw_employee_details`** already covers the need:
  - identity → `dw_employee_details.dim_employee`
  - active headcount without `dw_people.fact_employees` → filter `fact_assignment_snapshots` with `is_monthly_snapshot_for_employee` + `is_current_for_assignment` + `is_active` (mirrors the old `fact_employees` current/active grain), then join to the employee-current rows (`is_current_for_employee`) for job attributes
- Legacy enrich called out in `people_domain.mdc`

### Workable (`datalake_workable_redshift_clean`)

The Workable contract ended and the `workable_redshift` DAG was removed from bi-etl-ejuice, but the **frozen clean tables remain in the lake** and are a **legitimate source** for reverse exports. You may reference `datalake_workable_redshift_clean.*` directly whenever the logic can be expressed from those tables.

### Sandbox static tables (never in reverse SQL)

`datalake_people_analytics_sandbox` is a Databricks workspace scratchpad — **not** governed, not CI-approved, and **not** available on EMR. `reverse_reports` SQL must **never** reference it.

| Legacy sandbox pattern | Approved replacement |
| --- | --- |
| `base_completa_hierarquia` | `metric_people.employee_snapshots` (current-state filter per [Filtering `metric_people.employee_snapshots`](#filtering-metric_peopleemployee_snapshots)) |
| Curated static roster / mapping (e.g. `base_quintocred_ta`, `mapping_wb_to_gh`) | Ingest via **`gsheets_people_static`** or **`gsheets_people`** (`datalake_gsheets_people_clean.*`) **before** the reverse export — ask the user for `sheet_id` + tab; do not invent. Employee attributes (`email_pessoal`, `status`, hierarchy) still come from `employee_snapshots`. |
| Workable staging (`base_declinios`, `base_requisitions_wb`) | Inline from `datalake_workable_redshift_clean` in `queries/reverse/*.sql` — do not reference sandbox copies. |
| Ad-hoc sandbox dimension | DW `dw_*` / metric path, or new governed ingestion — document exception in PR + Jira |

### Resolving legacy `people_analytics_sandbox` dependencies

When a migrated notebook referenced `datalake_people_analytics_sandbox.{table}`:

1. **Search the repo** for an equivalent governed table (DW, metric, `gsheets_people_clean`, or `workable_redshift_clean`).
2. **Search Databricks workspace** [`/Workspace/People/People_Analytics`](https://dbc-931ee6e0-6803.cloud.databricks.com/browse/folders/1156481740231138?o=4531937035440038) for the notebook that materialized the sandbox table.
3. If the logic can run on **`datalake_workable_redshift_clean`** alone, inline it in the reverse SQL.
4. If the notebook is missing or the logic depends on other sandbox tables / GSheets, **bridge** via a one-time CTAS into `datalake_gsheets_people_clean.{snake_case_name}` and document the prerequisite in `docs/{table_name}.md`. **Ask the user** to run prod + forno CTAS before merge; never reference sandbox in the SQL.

After remapping, summarize: *old → new + one-line reason*.

**Agent gate:** if the legacy notebook SQL references `datalake_people_analytics_sandbox`, **stop** at the remap plan — do not implement `queries/reverse/*.sql` until the roster/mapping has an approved lake table.

---

## SQL style (mandatory)

All SQL under `dags/people/reverse_reports/queries/reverse/` follows [`sql_conventions.mdc`](../../rules/sql_conventions.mdc):

- Formatting, explicit `AS`, column order on outer `SELECT`
- Reorder to match conventions; use aliases for legacy sheet headers
- Align `docs/{table_name}.md` column inventory with `SELECT` list
- Partitions: `year`, `month`, `day` from `{load_start_date}` — never `CURRENT_DATE()` for partitions (see `reverse_reports_declaration.yml`)

Run skill **`databricks-emr-sql-lint`** after every `.sql` edit.

### SQL header comments

Keep the header minimal. Rules:

| Comment | Include? | Notes |
| --- | --- | --- |
| One-line description of what the report contains | **Yes** | e.g. `-- Active minority candidates in Jovem Aprendiz pipeline (requisition 435).` |
| `-- Exception:` when using clean/enrich instead of DW | **Yes (mandatory)** | Explain why DW has no path + reference Jira key. |
| `-- Sources:` listing tables | **No** | Redundant — visible from the `FROM`/`JOIN` clauses. |
| `-- Sheet:` or `-- sheet_id:` | **No** | Lives in `docs/{table_name}.md` and declaration `extra_spark_job_arguments`. |

---

## Declaration comments

In `reverse_reports_declaration.yml`, the only comment to add above a migration entry is:

```yaml
    # Former notebook: {notebook_name} ({source}).
    {table_name}:
```

- `{source}` = `Daily Pipeline` — the only pipeline source for reverse report notebook migrations.
- Do **not** include: card numbers, business owner names, governance doc paths, or section separators (`# ---`).
- Net-new exports (no legacy notebook) need no comment at all.

---

## Export column names

**Migrated sheet (Looker, PIN, fixed headers):** final aliases = legacy header strings; reorder per `sql_conventions.mdc`.

**Net-new or approved renames:** [`naming_conventions.mdc`](../../rules/naming_conventions.mdc).

**Unclear:** default to preserving names with `AS`.

**`column_mapping_mode: name`** (in `tables_customization`): Delta Lake only — last resort when
`load_delta_table` must persist SQL aliases that are not valid Delta identifiers. **Avoid** when
possible: those names break [`naming_conventions.mdc`](../../rules/naming_conventions.mdc). Use
only for reverse-layer exports where legacy headers cannot be renamed without breaking consumers.
Does **not** control Google Sheets column mapping. See `dag_build.mdc` (`DELTA_INVALID_CHARACTERS_IN_COLUMN_NAMES`).

### English identifiers everywhere except sheet headers

Pipeline SQL under `queries/reverse/` must use **English** for:

- CTE names (`eligible_employees`, not `base_funcionarios`)
- Internal column aliases in CTEs and intermediate `SELECT`s
- Metastore `table_name` / SQL file base name (`tech_job_tenure_ics_eng`, not `tech_recencia_cargos_ics_eng`)

**Portuguese is allowed only** in the **outermost** `SELECT` aliases that match the legacy Google Sheets / Looker contract (e.g. `AS fechamento`, `` AS `Número de Pessoa` ``). Map from English internal names at export time:

```sql
SELECT
    ms.dt_month_end AS fechamento,
    ms.employee_name AS nome
FROM
    monthly_snapshots AS ms
```

Do **not** propagate Portuguese names into CTEs, joins, or `GROUP BY` — even when the internal column will later be exported with a Portuguese header.

String literals in `CASE` that mirror sheet values (e.g. `'ativo'`, `'Férias'`) are allowed when required by the contract.

---

## Governance narrative (`docs/{table_name}.md`)

One file per sheet tab under `dags/people/reverse_reports/docs/`.

**Do not invent:** business consumer, upstream owner, why Sheets, API/integration patterns.

**Required from user (via skill questions or intake):**

- Business purpose, consumer, why Sheets (stakeholder wording) — often from [Intake inicial](SKILL.md#shared--intake-inicial)
- Business owner + technical owner
- Operational source of truth (DW tables and/or external owner)

### Canonical format

Use a **single Markdown table** — no separate sections (no column inventory, no owners heading, no governance heading):

```markdown
# `{table_name}` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.{table_name}` |
| **Business owner** | {name/email} ({team}) |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | {single sentence} |
| **Business purpose** | {1–3 sentences on process + consumer + why Sheets}. Migrated from Daily Pipeline notebook `{notebook_name}` ([{KEY}](https://quintoandar.atlassian.net/browse/{KEY})). |
| **Business consumer** | {team/person}. |
| **Operational source of truth** | {DW/metric tables used; exception note when clean/enrich required}. |
| **Delivery channel** | Google Sheets tab **{tab_name}** in workbook [{full_url}]({full_url}). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | {grain, header contract, known drifts, etc.} |
```

Rules:
- **Delivery channel:** always include the **full** Google Sheets URL (with `/edit?usp=sharing`), formatted as a clickable Markdown link — not just the `sheet_id`.
- Do not add programme index links unless the tab is part of a multi-tab export set that already has an index doc.

Optional programme index (link-only) for related tabs — e.g. `codex_pin_gsheet_exports.md`.

---

## Filtering `metric_people.employee_snapshots`

`employee_snapshots` is a **monthly snapshot** table. `dt_month_reference` holds the month-end reference date.

**When exporting the current state of employees** (latest snapshot, one row per primary assignment), use:

```sql
WHERE
    es.is_current = TRUE
    AND es.is_primary_assignment_for_snapshot = TRUE
```

`is_current = TRUE` always resolves to the latest available snapshot regardless of when the DAG runs. Reports querying historical snapshots or specific time ranges use their own predicates on `dt_month_reference` instead.

> `dt_month_reference = CURRENT_DATE()` returns rows only on the exact calendar day that matches the month-end reference date. Use `is_current` to get the current snapshot reliably.

### HRBP from `employee_snapshots` (mandatory remap)

`es.hrbp_work_email` is stamped from **`dim_cost_center` at the snapshot cost-center version** (`sk_cost_center_version`). For **terminated** (and some edge) rows that version often has **null** HRBP, while legacy notebooks / `base_completa_hierarquia` keep the **current** cost-center HRBP.

**Always** fall back to the current cost-center row when exporting `hrbp` (and when embedding HRBP in `access_list`):

```sql
LOWER(COALESCE(es.hrbp_work_email, cc_current.hrbp_work_email)) AS hrbp
```

```sql
LEFT JOIN
    dw_organization.dim_cost_center AS cc
        ON cc.sk_cost_center_version = es.sk_cost_center_version
LEFT JOIN
    dw_organization.dim_cost_center AS cc_current
        ON cc_current.id_organization = cc.id_organization
        AND cc_current.is_current = TRUE
```

Reference implementations: `performa_employee_base.sql`, X-Ray exports (`xray_general_info.sql` and siblings). Active employees typically already match; the COALESCE closes the terminated gap vs hierarchy/AppSheet.

Do **not** leave bare `LOWER(es.hrbp_work_email)` as the sole HRBP source in new reverse SQL.

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

- **Prefer Databricks for this workflow's diffs.** `reverse_reports.*` and `dw_*` are available in Trino like any other People table (see `people_domain.mdc`). The **legacy notebook outputs** they are diffed against, however, are not DAG-builder tables — they only exist on Databricks. Since one side of every Tier 1–3 diff is a legacy notebook output, run the full diff on Databricks against `reverse_reports.*`, `dw_*`, and the legacy notebook outputs as applicable, rather than splitting the query across two engines.

### Validation (before Forno / PR)

**Tier 1 — row counts:** compare legacy vs migrated total rows and distinct key counts.

**Tier 2 — column-by-column diff:** run an `EXCEPT`-based comparison for **every exported column**. All business columns must match; the only exclusions are load-time stamps (see table below). Investigate and explain every non-zero diff before marking validation OK.

**Tier 3 — sample inspection:** spot-check a handful of rows end-to-end.

User replies **validation OK** plus at least one of:

- Tier 1–3 outputs from **Databricks** (row counts, `only_in_legacy` / `only_in_migrated`, EXCEPT counts) — **prefer Databricks CLI** per [`people_domain.mdc`](../../rules/people/people_domain.mdc) and [`exodus_validation_playbook.md`](../../../dags/people/reverse_reports/docs/exodus_validation_playbook.md) when present
- Signed-off expected diffs with reasons (document in PR + playbook)
- Agent-run batch report: `.cursor/temp/{JIRA_KEY}/{branch}/validation/validation_report.md`

### Tier 2 — columns to exclude from EXCEPT diffs

Do **not** treat mismatches on **load-time stamps** as migration failures:

| Column / pattern | Reason |
| --- | --- |
| Raw **`ts_load`** | Pipeline load time; legacy `dw_employee` vs DW 2.0 / `employee_snapshots` **always** differ. |
| **`NOW()`**, **`CURRENT_TIMESTAMP()`**, or columns derived only from them | Run-time load stamp; differs every execution and across sources. |
| Date columns **based on load `ts_load`** | e.g. `dt_last_update`, `data_extracao` via `CAST(ts_load AS DATE)` or `FROM_UTC_TIMESTAMP(ts_load, …)` — still load metadata, not a business event. |

**In scope for Tier 2 — business dates:** all other exported date columns (`dt_birth`, `dt_hired`, `dt_inicio`, `dt_nascimento`, `dt_terminated`, `dt_desligamento`, SK-derived hire/termination dates, validity dates, etc.).

All other exported business columns (non-date) remain in scope for Tier 2 unless the user signs off a documented waiver in the PR.

### Local Forno (before PR)

User replies **local run OK** plus task success for `{table_name}` / `load_to_gsheet`, or agent ran trigger and confirms non-empty tab.

Waivers must be explicit and documented in the PR body.

---

## Quality checks before merge

- No new deprecated People sources; DW/metric default; enrich/clean only with exception note
- **No `datalake_people_analytics_sandbox` references** in reverse SQL (see [Resolving legacy `people_analytics_sandbox` dependencies](#resolving-legacy-people_analytics_sandbox-dependencies))
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
| Examples | [`access_list_dp.md`](../../../dags/people/reverse_reports/docs/access_list_dp.md) (compact single-table format), [`demographics_analytic_report.md`](../../../dags/people/reverse_reports/docs/demographics_analytic_report.md) (clean/enrich exception + full URL + Jira link), [`salary_tables.md`](../../../dags/people/reverse_reports/docs/salary_tables.md), [`jobs.md`](../../../dags/people/reverse_reports/docs/jobs.md), [`organization_codex_pin_sync.md`](../../../dags/people/reverse_reports/docs/organization_codex_pin_sync.md) |
| Validation playbook | [`exodus_validation_playbook.md`](../../../dags/people/reverse_reports/docs/exodus_validation_playbook.md) (prefer Databricks — legacy notebook outputs are not in Trino) |
| Cutover | [`exodus_migration_guide.md`](../../../dags/people/reverse_reports/docs/exodus_migration_guide.md) |
| Local Airflow | [`run-dag-locally`](../run-dag-locally/SKILL.md) |
| PR | [`review-pr`](../review-pr/SKILL.md), [`create-or-update-pr`](../create-or-update-pr/SKILL.md) |
| Jira kickoff / create DBP issue | [SKILL.md — Shared Jira (DBP kickoff)](SKILL.md#shared--jira-dbp-kickoff), [`dbp-jira-reference.md`](../../rules/people/dbp-jira-reference.md) |
| **DBP** | Jira project do squad **Enterprise Engineering** — kickoff: *"Já existe um card no board do Jira de Enterprise Engineering (DBP) para esse trabalho?"* (ver [`dbp-jira-reference.md`](../../rules/people/dbp-jira-reference.md) para nome legado do board) |
| **Interaction** | First turn → **AskQuestion** tool ([Flow selection](SKILL.md#flow-selection)); intake only after flows 1–2; bullets in chat ≠ AskQuestion |
| **Language** | Perguntas ao usuário → **PT-BR**; summary/description/comments no Jira → **English** |
| Jira branch | [`people-jira-branch-setup`](../people-jira-branch-setup/SKILL.md) |

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
