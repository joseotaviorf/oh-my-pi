# `base_app_org_health` — reverse export governance

| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_s3.base_app_org_health` |
| **Business owner** | People Insights |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Daily employee roster exported as a single CSV object to the Base44 office bucket for the Org Health analytics stack. |
| **Business purpose** | Replaces the Daily Pipeline notebook `dash_org_health` ([DBP-1310](https://quintoandar.atlassian.net/browse/DBP-1310) Exodus). Feeds the Base44 / S.A.R.A internal app and the Org Health Looker Studio dashboard with current employee identity, hierarchy, org structure, absence flags, Performa score, and PWD indicator. |
| **Business consumer** | Base44 / S.A.R.A app; Org Health Looker Studio dashboard. |
| **Operational source of truth** | `metric_people.employee_snapshots` (roster grain and most columns); `dw_time.fact_absence_requests` + `dw_time.dim_absence_type` (yesterday absence); `dw_performance.fact_performance_calibrations` + `dw_performance.dim_committee_meeting` + `dw_performance.dim_cycle_period` (current-year Performa). |
| **Delivery channel** | S3 object **`s3://5a-base44-office/orghealth/base_app_org_health.csv`** (prod). Canned ACL `bucket-owner-full-control` on write. Forno redirects to `people_bucket` under `reverse_s3_test/orghealth/base_app_org_health.csv` (no partner ACL). |
| **Grain** | One row per employee assignment on `metric_people.employee_snapshots` with `is_current_for_employee = TRUE`, limited to active employees plus terminated employees who still appear as a manager of at least one active employee (`active_managers` CTE). Absence and Performa joins are deduped to one row per `person_number` (`ROW_NUMBER` = 1). |
| **Contract notes** | Legacy Portuguese column names preserved (lowercase snake_case). CSV written by Spark (`header=true`, comma separator, UTF-8, empty nulls) — not pandas quote-doubling. Column order: `id_colaborador`, `nome`, `email`, `banda`, `id_gestor`, `gestor`, `cargo`, `classe_cargo`, `centro_de_custo`, `l1_cc`, `l2_cc`, `l3_cc`, `vertical`, `structure`, `team`, `diretos`, `layer`, `fl_lider`, `dt_inicio`, `dt_desligamento`, `motivo_desligamento`, `sexo`, `l1_gestor` … `l9_gestor`, `absence_type`, `dt_absence_ended`, `is_pwd`, `performa_score`, `performa_cycle`, `country`, `dt_last_update`. `diretos` is `count_direct_report` from `employee_snapshots`. Date filters use `{load_start_date}` / `{load_end_date}` — never `CURRENT_DATE()`. |

## Rollout and prod validation

IAM for the partner bucket is tracked in [infrastructure#42914](https://github.com/quintoandar/infrastructure/pull/42914). The grant on `orghealth/*` must also cover Spark staging under `orghealth/_staging/load_to_s3/*` (Put/Get/List/Delete) and cleanup of any legacy `orghealth/base_app_org_health.csv/` directory from an old Spark directory write.

**This export cannot be fully validated in Forno** (People DW / metric sources are not available there). After merge and once infrastructure#42914 is applied:

1. Keep `bietlejuice.reverse_s3` **paused** in prod Airflow until the smoke test passes.
2. Trigger a **manual prod run** of `base_app_org_health` only.
3. Confirm `s3://5a-base44-office/orghealth/base_app_org_health.csv` is a single GET-able object (not a Spark part directory) and that Base44 / Org Health consumers can read it.
4. If the run fails (IAM, ACL, or promote), leave the DAG paused until infrastructure or code is fixed; Forno cannot reproduce partner-bucket behaviour.
