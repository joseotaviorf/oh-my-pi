# `quintocred_ta` — reverse export governance

| Field | Value |
| --- | --- |
| **Business owner** | Talent Acquisition (Fernanda Conde, Thais Martinez) |
| **Technical owner** | People Insights |
| **Metastore table** | `reverse_reports.quintocred_ta` |
| **One-line summary** | Greenhouse applications from QuintoCred roster employees for internal mobility tracking. |
| **Business purpose** | TA prioritizes QuintoAndar employees who were part of QuintoCred when they apply to other company roles. This export surfaces those applications alongside ATS data. Migrated from Daily Pipeline notebook `TA_Quintocred.sql` ([DBP-1831](https://quintoandar.atlassian.net/browse/DBP-1831)). |
| **Business consumer** | TA Corp |
| **Delivery channel** | Google Sheets tab **base_aplicações** in workbook [https://docs.google.com/spreadsheets/d/1RR72o-4OZt0KgFomVu8ZHrY4KR2S8oKI3eISbhFeJAU](https://docs.google.com/spreadsheets/d/1RR72o-4OZt0KgFomVu8ZHrY4KR2S8oKI3eISbhFeJAU). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
