# `talent_access_list` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.talent_access_list` |
| **Business owner** | People Team (Talent) |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Person number and hierarchy access list for talent sheets. |
| **Business purpose** | Access-control list of person numbers and hierarchy attributes for Performa/Talent dashboard cross-tab permissions. |
| **Business consumer** | Performa/Talent dashboard cross-tabs |
| **Operational source of truth** | `metric_people.employee_snapshots` (`access_list_no_employee_no_hrbp` = leadership chain L0–L9 excluding employee and HRBP). |
| **Delivery channel** | Google Sheets tab **access_list_talent** in workbook https://docs.google.com/spreadsheets/d/1smsqH7R_-xjxZm5Ca2eVSTKzN9OQqPOUF74uVtO2ZYE. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy column names preserved (`person_number`, `access_list`). Grain: one row per `person_number` on the current snapshot (`is_current = TRUE`). When multiple primary assignments exist for the same person, prefer the active row, then highest `assignment_number` (same dedupe pattern as `access_list_dp`). |
