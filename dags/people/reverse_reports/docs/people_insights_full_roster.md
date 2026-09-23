# `people_insights_full_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.people_insights_full_roster` |
| **Business owner** | kevin.trindade (People Insights) |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Wide employee roster with org, demographics, compensation, and talent data for People Insights. |
| **Business purpose** | Full employee base used by the People Insights team for ad-hoc analysis and reporting. Migrated from Daily Pipeline notebook `LEGADO_export`. |
| **Business consumer** | People Insights. |
| **Delivery channel** | Google Sheets tab **base_completa_grupo** in workbook [https://docs.google.com/spreadsheets/d/1OI1OoQCZWP37HrPQsFGn2VmpQkgbE5-apJIa4qJnGMo/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1OI1OoQCZWP37HrPQsFGn2VmpQkgbE5-apJIa4qJnGMo/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | `pos_faixa` consumes the canonical `metric_people.employee_snapshots.salary_midpoint_ratio`, representing current `amount_salary` divided by the effective salary-table midpoint (`salary_range_mid`), formatted to 3 decimals. The canonical value is NULL when salary or midpoint is missing or the midpoint is not positive. |
