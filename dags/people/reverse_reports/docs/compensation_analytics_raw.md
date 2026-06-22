# `compensation_analytics_raw` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.compensation_analytics_raw` |
| **Business owner** | Compensation |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Simplified active compensation export for analytics raw sheet. |
| **Business purpose** | Lightweight active-employee compensation export for Compensation downstream processing. |
| **Business consumer** | Compensation analytics |
| **Operational source of truth** | `metric_people.employee_snapshots` (+ `dw_*` joins where applicable). |
| **Delivery channel** | Google Sheets tab **base_analytics_raw** in workbook `1A-am4WUHHoFMMbdArbQxhviprC1UHL_Wvt7phOEhJRo`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Portuguese column names preserved. |
