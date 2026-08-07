# `tech_neotribes_study` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.tech_neotribes_study` |
| **Business owner** | People Insights |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Engineering Neotribes study roster with team assignments unpivoted across up to five teams per employee. |
| **Business purpose** | Refreshes the Neotribes engineering org study workbook with active software and data employees, their hierarchy layers, talent ratings, and team labels from the QA Database input tab. Migrated from Daily Pipeline notebook `eng_neotribes_study_update` ([DBP-1774](https://quintoandar.atlassian.net/browse/DBP-1774)). |
| **Business consumer** | Engineering leadership and People Analytics running the Neotribes study. |
| **Operational source of truth** | `metric_people.employee_snapshots` for employee master and hierarchy fields; `datalake_gsheets_people_clean.team_formation_product_tech` for team labels (`team_1` through `team_5`) from sheet `team_formation_tech_active`. |
| **Delivery channel** | Google Sheets tab **updated_db** in workbook [https://docs.google.com/spreadsheets/d/1LZRTxkJCnJIQILmYgfMFeu7xzmd8z5YkxnafiV7FVeg/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1LZRTxkJCnJIQILmYgfMFeu7xzmd8z5YkxnafiV7FVeg/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
