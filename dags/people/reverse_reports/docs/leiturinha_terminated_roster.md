# `leiturinha_terminated_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.leiturinha_terminated_roster` |
| **Business owner** | Benefits |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Terminated BR employees for Leiturinha benefit offboarding. |
| **Business purpose** | Benefits team export of terminated employees for Leiturinha partner offboarding (Brazil employees). |
| **Business consumer** | Benefits |
| **Operational source of truth** | `metric_people.employee_snapshots` + `dw_organization.dim_business_unit` + `dw_employee_details.dim_documentation` (CPF). |
| **Delivery channel** | Google Sheets tab **leiturinha_desligados** in workbook `1QgICpSG4yJa1-zyvnSyTi0S8GPHf6Xg0hg0rgzg5v3Q`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Terminated employees in QuintoAndar SP/SC/MG only. Filter: `is_current_for_employee = TRUE`, `LOWER(status) = 'terminated'`. `motivo_desligamento` maps `termination_type` → `voluntario` / `involuntario` (legacy sheet contract). CPF from `COALESCE(es.cpf, doc.cpf)` via `dim_documentation` on `person_number` + `is_current`. |
