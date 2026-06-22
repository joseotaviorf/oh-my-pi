# `governance_pm_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.governance_pm_roster` |
| **Business owner** | Governance (karla.martins@quintoandar.com.br) |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Active roster for Deborah Saber org for project management. |
| **Business purpose** | Active employee base scoped to the Deborah Saber organisation for Governance PM project-management workflows. |
| **Business consumer** | Governance PM |
| **Operational source of truth** | `metric_people.employee_snapshots` (+ `dw_*` joins where applicable). |
| **Delivery channel** | Google Sheets tab **Base** in workbook `19JbdaddwOmC5cTdTWDLSSqFj4Vygehmeq7fDjPhMtp4`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Portuguese column names preserved. |
