# `quintocare_titular_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.quintocare_titular_roster` |
| **Business owner** | Benefits |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Active BR titulares for QuintoCare with CNPJ mapping. |
| **Business purpose** | Benefits team base of active Brazil benefit titulares for QuintoCare, including legal-entity CNPJ mapping. |
| **Business consumer** | Benefits |
| **Operational source of truth** | `metric_people.employee_snapshots` (+ `dw_*` joins where applicable). |
| **Delivery channel** | Google Sheets tab **quintocare_titular** in workbook `1QgICpSG4yJa1-zyvnSyTi0S8GPHf6Xg0hg0rgzg5v3Q`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Portuguese column names preserved. |
