# `dei_employee_diversity_analytics` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.dei_employee_diversity_analytics` |
| **Business owner** | Julia Mesquita |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Monthly employee DEI analytics feed (inclusion flags, PwD, rewards cycle, committee) for the DEI Looker Studio dashboard. |
| **Business purpose** | Powers DEI analytics in Looker Studio (`base_dei_v2`) for Julia, DEI, and Talent. Kept on Google Sheets because the team does not yet have full Superset access; this is an Exodus notebook migration. Migrated from Daily Pipeline notebook `dash_analytics_dei` ([DBP-1754](https://quintoandar.atlassian.net/browse/DBP-1754)). |
| **Business consumer** | Julia Mesquita; DEI and Talent teams. |
| **Operational source of truth** | `metric_people.employee_snapshots`; `dw_demographics.dim_employee_disability`; `dw_compensation.fact_compensations` + `dim_event_definition` (promo/merit by cycle); `dw_performance.fact_performance_calibrations` + `dim_committee_meeting` (`meeting_year = 2026`). |
| **Delivery channel** | Google Sheets tab **base_dei_v2** in workbook [https://docs.google.com/spreadsheets/d/16u0I2lV6dDzhslWyVw6S62N-M7XrIHgnWpy05awQPcQ/edit?usp=sharing](https://docs.google.com/spreadsheets/d/16u0I2lV6dDzhslWyVw6S62N-M7XrIHgnWpy05awQPcQ/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Looker column names preserved (`id_colaborador`, `fechamento`, `BIM`, `WOMEN`, `LGBT`, `URG`, `PwD`, etc.). Demographic CASE logic remapped to English lake values. `modo` has no DW path today (exported NULL). Committee year kept at 2026 as in the notebook. |
