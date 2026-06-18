# `compliance_employee_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.compliance_employee_roster` |
| **Business owner** | Compliance |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Employee roster with role, cost center, VP, residence country, and termination details for Compliance. |
| **Business purpose** | Base for Compliance with employee name, email, role, cost center, VP (L1 manager), residence country, company, band, status, and termination reason/date. |
| **Business consumer** | Compliance |
| **Operational source of truth** | `metric_people.employee_snapshots`. |
| **Delivery channel** | Google Sheets tab **base** in workbook `1_3VUrs066sRdtQhzKz71g5S64ZlONbewj575BHWCk3E`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Portuguese column names preserved. Ordered by status and termination date (desc). |
