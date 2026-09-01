# `ta_applications_funnel` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.ta_applications_funnel` |
| **Business owner** | Talent Acquisition |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Candidate application funnel across Workable and Greenhouse v3, by candidate, job and stage. |
| **Business purpose** | Feeds the Talent Acquisition daily funnel dashboard, which tracks candidates per stage and per pipeline across the two ATSs. Google Sheets is an interim delivery layer: the consumption is planned to move to Superset/Databricks, and this migration to `reverse_reports` is the intermediate step. Migrated from Daily Pipeline notebook `gh_funnel` ([DBP-1902](https://quintoandar.atlassian.net/browse/DBP-1902)). |
| **Business consumer** | Talent Acquisition team, daily. |
| **Operational source of truth** | Greenhouse v3: `datalake_greenhouse_v3_clean` (`application_stages`, `applications`, `candidates`, `jobs`, `job_interview_stages`, `departments`, `sources`). Workable (frozen contract): `datalake_workable_redshift_clean` (`activities`, `candidates`, `stages`, `jobs`, `pipelines`, `departments`). Job opening close dates: `datalake_hiring.job_openings`. Exception: there is no DW path for recruiting funnel data, so the export reads clean/enrich directly. |
| **Delivery channel** | Google Sheets tab **ta_funnel_full** in workbook [https://docs.google.com/spreadsheets/d/1Q5fzX2njlEZBUwrEfyCouuD07RsoMY1glKCVBm_UNCo/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1Q5fzX2njlEZBUwrEfyCouuD07RsoMY1glKCVBm_UNCo/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Grain is candidate × job × funnel stage, in two halves unioned as in the legacy `funnel_base_final`: resolved stages are aggregated (`candidate_id` and `candidate_name` masked as `'-'`, `candidate_count = COUNT(1)`), and in-process candidates are listed individually (`candidate_count = 1`). 18 legacy headers preserved verbatim, including the Portuguese `sistema` and `grupo_pipe`. `sistema` is `'wb'` for the Workable leg and `'gh'` for Greenhouse. `last_updated_datetime` is a source-freshness stamp (`MAX` of the ATS update timestamp), not a business date, and is excluded from Tier 2 diffs together with `year`/`month`/`day`. |

## Migration notes

The legacy notebook wrote three `datalake_people_analytics_sandbox` tables (`ta_candidate_status`,
`ta_funnel_accumulated`, `base_applications_funnel`) before exporting `funnel_base_final`. None of
them survive: the whole chain is inlined in `queries/reverse/ta_applications_funnel.sql`, so the
export has no sandbox dependency.

Three rewrites were needed for the dual Databricks/EMR runtime and for the source-layer rules:

- **`activities_job_id_updated`** was a Python loop that created one `id_job_{n}` column per candidate
  job change and `COALESCE`d them. It is now a single `ROW_NUMBER()` window: for each activity, keep
  the job of the most recent job-start event at or before the activity timestamp — the same value the
  `COALESCE` chain produced.
- **`QUALIFY`** in `ta_candidate_status` became a `ROW_NUMBER()` subquery with a `WHERE` filter, and the
  lateral column aliases (`WHEN status = 'hired' …` referencing an alias of the same `SELECT`) were
  split into nested CTEs. Both are Spark 4.0+/Databricks-only constructs.
- **Prospects** now read `datalake_greenhouse_v3_clean.applications` instead of
  `datalake_greenhouse_v3_raw.applications`, which adds the `prospective_job_ids IS NOT NULL` guard.

`MAX(last_updated_datetime)` used to be read back from the persisted `ta_funnel_accumulated` table;
it is now taken from the inline computation.

One asymmetry is kept **on purpose**: `workable_funnel_accumulated` joins back to raw
`activities` on the raw `id_job` and the unpatched timestamp, while `workable_stage_status`
was built from the resolved job and patched timestamps. This mirrors the legacy
`ta_funnel_accumulated` (sandbox 1,281,676 rows vs inline 1,281,666). Making the join identity
consistent (resolved job + patched timestamp) would add 13,752 candidate × stage rows (+3.7%)
that the legacy export never had — measured on an EMR cluster against the frozen Workable
tables: current leg 367,434 rows is a strict subset of the "consistent" variant's 381,197.

## Expected delta vs the legacy export

The Greenhouse leg matches the legacy `funnel_base_final` exactly (84,683 rows, 180,145 candidates on
2026-08-28). The Workable leg is **−266 rows / −2,507 candidates (−0.6%)**.

The legacy Workable numbers come from `ta_funnel_accumulated`, last written **2025-10-07** by the job
now named `[old] [People] Daily TA`, whose schedule is `PAUSED`. No notebook in the TA or Daily
Pipeline folders contains a Workable cutoff rule — the freeze is a side effect of decommissioning
that job, not a business rule.

Almost the whole delta traces to a single job: **4507332** (*(old) Grupo QuintoAndar | Analista de
Operações Jurídicas*) was **un-archived in Workable on 2025-10-13**, six days after the snapshot
froze. It carries 2,028 accumulated rows, and the `candidate_status` rule turns a job that is not
`published`/`open for internal use` into `'archived'` for its still-active candidates — so in the
legacy those candidates pass the `candidate_status <> 'active'` filter and in the recomputed version
they do not.

The numbers do not drift going forward: `workable_redshift_clean` is frozen too, because the Workable
contract ended (last load 2025-10-22).

Full Tier 1-3 evidence: `.cursor/temp/DBP-1902/migrate-ta-applications-funnel/validation/validation_report.md`.
