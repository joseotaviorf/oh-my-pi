# `offer_outcomes` — reverse export governance

| Field | Value |
| --- | --- |
| **Business owner** | Talent Acquisition |
| **Technical owner** | People Insights |
| **Metastore table** | `reverse_reports.offer_outcomes` |
| **One-line summary** | Workable and Greenhouse offer accept/decline history for TA decline analytics. |
| **Business purpose** | Consolidates declined and accepted offers from Workable (legacy) and Greenhouse into a single sheet for TA decline analysis. Migrated from Daily Pipeline notebook `declinios.sql` ([DBP-1832](https://quintoandar.atlassian.net/browse/DBP-1832)). |
| **Business consumer** | TA |
| **Operational source of truth** | Greenhouse: `datalake_greenhouse_v3_clean`. Workable declined: `datalake_workable_redshift_clean` (inline). Workable accepted: `datalake_workable_redshift_clean` (inline, ported from `base_requisitions_workable`). WB→GH migration filter: `datalake_gsheets_people_clean.mapping_wb_to_gh` (`gsheets_people_static` DAG). |
| **Delivery channel** | Google Sheets tab **base_nova_com_gh** in workbook [https://docs.google.com/spreadsheets/d/1o1vg_ekZFODKCDLjCcww9lxmGZutxDn2f90Z1DboD0o/edit](https://docs.google.com/spreadsheets/d/1o1vg_ekZFODKCDLjCcww9lxmGZutxDn2f90Z1DboD0o/edit). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy sheet headers preserved in outer `SELECT` (`dpto_job`, `dpto_job_macro`, `fl_system`, `data_atualizacao`). Internal CTEs use English identifiers. `data_atualizacao` follows load date (`{load_start_date}`). |

## Workable sources

`reverse_reports` SQL must **never** reference `datalake_people_analytics_sandbox`.

| Workable input | Source in SQL | Notes |
| --- | --- | --- |
| Declined offers | Inline from `datalake_workable_redshift_clean` | Ported from [`old_others/base_declinios`](https://dbc-931ee6e0-6803.cloud.databricks.com/editor/notebooks/2494525713546427). |
| Accepted offers | Inline from `datalake_workable_redshift_clean` | Ported from [`TA/base_requisitions_workable`](https://dbc-931ee6e0-6803.cloud.databricks.com/editor/notebooks/784807127998146) (`requisitions_new` logic). |
| GH migration filter | `datalake_gsheets_people_clean.mapping_wb_to_gh` | Ingested by `gsheets_people_static` from GSheet `1C1YVTrZPY7...`, tab `mapping_requisitions_openings`. |

### Known parity waiver (accepted Workable L1)

Legacy `base_requisitions_workable` falls back to `base_completa_hierarquia` when requisition-form L1 is missing. Inline SQL uses `l1_manager_form` only (no sandbox/DW join at reverse layer). String literals preserve legacy Workable field values (e.g. candidate source labels). Tier 2 validation may show L1 diffs on accepted WB rows; row counts and other columns should match.
