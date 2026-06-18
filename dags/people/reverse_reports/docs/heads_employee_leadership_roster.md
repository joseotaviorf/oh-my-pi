# `heads_employee_leadership_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.heads_employee_leadership_roster` |
| **Business owner** | Heads |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Active-employee leadership roster with org hierarchy for Heads programs. |
| **Business purpose** | Base of active employees with leadership flag, cost center, CODEX structure, and full manager chain for Heads stakeholders. |
| **Business consumer** | Heads |
| **Operational source of truth** | `metric_people.employee_snapshots`. |
| **Delivery channel** | Google Sheets tab **base** in workbook `1jyMMfZbfhV6olXFDAY5By1ptwyUOOJ5wqONAWLuqqsM`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Portuguese column names preserved. `tribo_time`, `squad`, `linha`, `tipo_de_linha` have no current lake source (NULL). |
