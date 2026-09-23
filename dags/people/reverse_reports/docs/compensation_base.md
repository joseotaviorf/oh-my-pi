# `compensation_base` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.compensation_base` |
| **Business owner** | Compensation |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Full workforce compensation export for the Compensation team workbook. |
| **Business purpose** | Daily compensation base with salary, variable-pay targets, job and org context for active and terminated employees on the current employee snapshot. Migrated from Daily Pipeline notebook `people_reports` view `base_compensation`. |
| **Business consumer** | Compensation team (Franciele Bilhar Vrielink). |
| **Operational source of truth** | `metric_people.employee_snapshots` with `dw_compensation` and `dw_organization` joins. |
| **Delivery channel** | Google Sheets tab **base comp** in workbook [https://docs.google.com/spreadsheets/d/1JdEi_cwBzs1NsY30dUCodAW3QOlxHarQgSRJTMeKTqo/edit](https://docs.google.com/spreadsheets/d/1JdEi_cwBzs1NsY30dUCodAW3QOlxHarQgSRJTMeKTqo/edit). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Portuguese column headers preserved. Grain: one row per employee (`is_current_for_employee = TRUE`). Tab name is **base comp** (not `base_compensation`). `l3_gestor` and `l4_gestor` added in DBP-1819. `dt_admissao_assignment` maps to `dt_assignment_started`. `tabela_salarial` maps to `dw_compensation.dim_job.salary_table` (grade ladder / directorate level), matching legacy `base_compensation`. `pos_faixa` consumes the canonical `metric_people.employee_snapshots.salary_midpoint_ratio`, which is the current salary divided by the effective salary-table midpoint and formatted to the existing output type. `people_insights_full_roster` and `xray_general_info` consume the same canonical metric. |
