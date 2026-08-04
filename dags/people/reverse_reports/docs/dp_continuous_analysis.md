# `dp_continuous_analysis` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.dp_continuous_analysis` |
| **Business owner** | DP (Personnel Department) |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Employee roster with org, compensation, and demographics for DP ad-hoc analysis. |
| **Business purpose** | Continuous analysis base for the DP team. Migrated from `people_reports` notebook view `dp_analysis`. |
| **Business consumer** | DP — joao.starling@quintoandar.com |
| **Operational source of truth** | `metric_people.employee_snapshots` (+ `dw_organization.dim_business_unit` for `empresa`, `dw_compensation.dim_job` for `workload` / `working_hours_regime`). |
| **Delivery channel** | Google Sheets tab **data** in workbook https://docs.google.com/spreadsheets/d/19wejhwGjx6YCFg3At5Jfnw-90TpMOkyTr5Cl3bhsIzw. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
