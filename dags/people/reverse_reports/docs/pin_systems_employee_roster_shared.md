# `pin_systems_employee_roster_shared` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.pin_systems_employee_roster_shared` |
| **Business owner** | Performance and Navent |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Shared employee systems base for PIN tab `base_pin` (Performance / Navent workbook). |
| **Business purpose** | Same employee roster as `pin_systems_employee_roster`, delivered to a shared workbook consumed by Performance and Navent. Migrated from the second `table_to_gsheets` call for `wd_sistemas` in Daily Pipeline `reports_dw.py`. |
| **Business consumer** | Performance and Navent |
| **Operational source of truth** | Same as `pin_systems_employee_roster` (`metric_people.employee_snapshots`). |
| **Delivery channel** | Google Sheets tab **base_pin** in workbook `1PEy7dd54tor157fVI_UK7J3t4SLIDKtgk92x6dHJbmg`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Identical column contract to `pin_systems_employee_roster`. Primary assignment grain. Legacy Portuguese column names preserved. |
