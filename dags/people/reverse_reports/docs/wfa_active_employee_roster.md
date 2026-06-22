# `wfa_active_employee_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.wfa_active_employee_roster` |
| **Business owner** | Benefits |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Active employee roster with hierarchy for Work From Anywhere (WFA) benefit operations. |
| **Business purpose** | Base for the Benefits team to support WFA (Work From Anywhere) processes with employee identification, status, hierarchy, and org attributes. Migrated from `people_reports` notebook cell `base_wfa`. |
| **Business consumer** | Benefits |
| **Operational source of truth** | `metric_people.employee_snapshots` (+ `dw_*` joins where applicable). |
| **Delivery channel** | Google Sheets tab **base_oficial** in workbook `1QgICpSG4yJa1-zyvnSyTi0S8GPHf6Xg0hg0rgzg5v3Q`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Portuguese column names preserved. |
