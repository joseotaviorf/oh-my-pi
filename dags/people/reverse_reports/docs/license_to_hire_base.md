# `license_to_hire_base` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.license_to_hire_base` |
| **Business owner** | TA / People |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Eligible employees with License to Hire Degreed pathway progress for the LTH dashboard. |
| **Business purpose** | Refreshes the License to Hire (LTH) dashboard base tab with TA pathway completion for eligible employees (band ≥ 7 / leaders / Talent). Migrated from notebook `license_to_hire` ([DBP-1736](https://quintoandar.atlassian.net/browse/DBP-1736)). |
| **Business consumer** | Learning / TA (LTH dashboard). |
| **Operational source of truth** | `metric_people.employee_snapshots` (current primary assignment); `datalake_learning.all_completions` + `datalake_learning.user_identifier_mapping` (no `dw_learning` yet). |
| **Delivery channel** | Google Sheets tab **base** in workbook [https://docs.google.com/spreadsheets/d/1AvkevkP2czvxlxscLGpSml6V1Az-lcH5BfSfKpx6b5c/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1AvkevkP2czvxlxscLGpSml6V1Az-lcH5BfSfKpx6b5c/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy column names preserved (`titulo_trilha`, `pct_completed_required_final`, `perfil_treinamento`, etc.). Pathway defaults by country × LIDER/IC. Pathway ranking uses `work_email` (not Degreed `id_user`) to avoid duplicate sheet rows. `ts_load` is Degreed enrich max load date (load-time stamp for Tier 2 exclusion). Distinct from export `license_to_hire_roster` (other sheet). |
