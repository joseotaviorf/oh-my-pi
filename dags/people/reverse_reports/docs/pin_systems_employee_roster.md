# `pin_systems_employee_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.pin_systems_employee_roster` |
| **Business owner** | DP (Personnel Department) |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Employee systems base for PIN tab `base_pin` (DP workbook). |
| **Business purpose** | Employee roster with org, job, manager, and cost center for DP PIN systems consumption. Migrated from Daily Pipeline `reports_dw.py` view `wd_sistemas`. |
| **Business consumer** | DP (Personnel Department) |
| **Operational source of truth** | `metric_people.employee_snapshots`. |
| **Delivery channel** | Google Sheets tab **base_pin** in workbook `1il9Cl7fuyXQ7AKrso-AQVN0A4LDEE1-vtgcv-rqSEDU`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Portuguese column names preserved. Primary assignment grain (`is_primary_assignment_for_snapshot = TRUE`). Oracle flexfield-style header `país` requires `column_mapping_mode: name`. Same workbook as `dp_employee_master` (different tab). |
