# `dei_employee_diversity_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.dei_employee_diversity_roster` |
| **Business owner** | DEI |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Employee roster with DE&I self-declared attributes and derived inclusion flags for DEI programs. |
| **Business purpose** | Base for DEI with ethnicity, gender identity, sexual orientation, disability, neurodiversity, and derived BIM/Women/LGBT+ groupings plus manager and org context. Migrated from notebook cell `base_div_completa`. |
| **Business consumer** | DEI |
| **Operational source of truth** | `metric_people.employee_snapshots` plus `dw_demographics.dim_employee_disability`. |
| **Delivery channel** | Google Sheets tab **base** in workbook `12ao2yTFNffNaZWlb72hlU7mSS_WTob9MMs4UsFJLdBg`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Portuguese column names and inclusion CASE logic preserved from notebook. Sensitive DE&I data — restricted ACLs. |
