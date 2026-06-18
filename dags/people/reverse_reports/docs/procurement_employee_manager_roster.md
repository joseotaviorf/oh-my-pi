# `procurement_employee_manager_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.procurement_employee_manager_roster` |
| **Business owner** | Procurement |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Active and future-terminated employees with manager chain role and band per hierarchy level for Procurement. |
| **Business purpose** | Daily base for Procurement with employee role/band and each manager level (L0–L8) name, email, role, and band. |
| **Business consumer** | Procurement |
| **Operational source of truth** | `metric_people.employee_snapshots` (self-join on manager assignment numbers). |
| **Delivery channel** | Google Sheets tab **base_atualizada_diariamente** in workbook `1WNIqQi1uRYoBKxrGFLsJ0HGsLSVCvxNJpYl36eQcjQE`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Portuguese column names preserved. Filter: active or termination date after today. |
