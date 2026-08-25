# `compliance_employee_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.compliance_employee_roster` |
| **Business owner** | Compliance |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Employee roster with role, cost center, VP, direct manager, L2, HRBP, residence country, and termination details for Compliance. |
| **Business purpose** | Base for Compliance with employee name, email, role, cost center, VP (L1), direct manager, L2, HRBP (name and email), residence country, company, band, status, and termination reason/date. |
| **Business consumer** | Compliance |
| **Operational source of truth** | `metric_people.employee_snapshots`. |
| **`gestor` / `email_gestor`** | Direct manager name and work email from `employee_snapshots.manager_name` / `manager_work_email` — added per `DBP-2017`. |
| **`l2_gestor` / `email_l2`** | Organizational L2 name and work email from `dim_management_hierarchy.name_l2` / `email_l2` (`is_current = TRUE`) — added per `DBP-2017`. |
| **`nome_hrbp` / `email_hrbp`** | Cost-center HRBP name and work email from `dim_cost_center.hrbp_name` / `hrbp_work_email` (joined on `sk_cost_center_version`) — added per `DBP-2017`. |
| **PII / LGPD** | New columns are `personal` (employee name, work email of manager/L2/HRBP). Precedent: `gestor`/`manager_name` in `dei_employee_diversity_roster` and `wfa_active_employee_roster`; `manager_work_email` in `license_to_hire_base`; `name_l2`/`email_l2` in `dei_employee_diversity_roster` and `tech_job_tenure_other_teams`; `hrbp_name` in `talent_review_performa_base`; `hrbp_work_email` in `dei_employee_diversity_roster`, `wfa_active_employee_roster`, and `dp_employee_master`. Necessity: Compliance roster process (PDA-528 / DBP-2017). |
| **Delivery channel** | Google Sheets tab **base** in workbook `1_3VUrs066sRdtQhzKz71g5S64ZlONbewj575BHWCk3E`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Portuguese column names preserved. Ordered by status and termination date (desc). |
