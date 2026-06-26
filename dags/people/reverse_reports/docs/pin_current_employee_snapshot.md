# `pin_current_employee_snapshot` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.pin_current_employee_snapshot` |
| **Business owner** | People Insights |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Full employee assignment snapshot for PIN Classifieds sync. |
| **Business purpose** | Employee roster with org, manager, compensation, and contact fields used by People Insights to update PIN with Classifieds data. Migrated from Daily Pipeline `reports_dw.py` view `foto_atual_pin`. |
| **Business consumer** | People Insights |
| **Operational source of truth** | `metric_people.employee_snapshots` (+ `dw_compensation.fact_compensations` for `moeda`; `dw_employee_details.fact_assignment_snapshots` + `dim_employee` for `gestor_person_number`). |
| **Delivery channel** | Google Sheets tab **foto_atual_pin** in workbook `1UJu1xFgPjBtHIIeJTq28kmc4AFNYQv4nvkUIfP5i-A0`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Portuguese column names preserved. Primary assignment grain (`is_primary_assignment_for_snapshot = TRUE`). Includes salary and PII columns per legacy contract. Status column aliased as `status` (legacy notebook exported an unaliased `IF` expression — validate header during Tier-2 diff). |
