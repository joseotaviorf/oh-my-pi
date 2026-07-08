# `pin_cost_center_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.pin_cost_center_roster` |
| **Business owner** | People Insights |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Person number to cost center code mapping for PIN Classifieds sync. |
| **Business purpose** | Assignment-level mapping of `person_number` to `cost_center_code` for People Insights PIN Classifieds updates. Migrated from Daily Pipeline `reports_dw.py` view `centro_de_custo_pin`. |
| **Business consumer** | People Insights |
| **Operational source of truth** | `metric_people.employee_snapshots`. |
| **Delivery channel** | Google Sheets tab **centro_de_custo_pin** in workbook `1UJu1xFgPjBtHIIeJTq28kmc4AFNYQv4nvkUIfP5i-A0`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy column names preserved. Employee-current grain (`is_current_for_employee = TRUE`) — one row per employee on the current snapshot. |
