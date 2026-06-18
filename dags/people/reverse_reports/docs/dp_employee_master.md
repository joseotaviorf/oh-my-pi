# `dp_employee_master` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.dp_employee_master` |
| **Business owner** | DP (Personnel Department) |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Extended employee master with documentation and TMF identifiers for the Personnel Department (DP). |
| **Business purpose** | Comprehensive employee export for DP with person/assignment numbers, org data, PII, mother's name, and TMF legacy registration. Migrated from notebook cell `base_sistemas_dp`. |
| **Business consumer** | DP (Personnel Department) |
| **Operational source of truth** | `metric_people.employee_snapshots` plus `dw_employee_details.dim_documentation` and `dim_employee`. |
| **Delivery channel** | Google Sheets tab **base** in workbook `1il9Cl7fuyXQ7AKrso-AQVN0A4LDEE1-vtgcv-rqSEDU`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Portuguese column names preserved. `sub_diretoria_depara` has no current lake source (NULL). |
