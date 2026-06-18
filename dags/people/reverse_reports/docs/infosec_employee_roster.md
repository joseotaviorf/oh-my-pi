# `infosec_employee_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.infosec_employee_roster` |
| **Business owner** | InfoSec |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Daily employee roster with hierarchy and employment attributes for InfoSec operations. |
| **Business purpose** | Base for the InfoSec team with employee identification, status, band, role, manager, org structure (cost center, CODEX), employment dates, and personal email. |
| **Business consumer** | InfoSec |
| **Operational source of truth** | `metric_people.employee_snapshots` (DW 2.0 wide metric). |
| **Delivery channel** | Google Sheets tab **PIN** in workbook `19rND8lkHWR99AJVgf7pAI9mJQ_bkkECHOyP0b7zfNoo`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Portuguese column names preserved. `marca_produto_dedicado` has no current lake source (NULL). |
