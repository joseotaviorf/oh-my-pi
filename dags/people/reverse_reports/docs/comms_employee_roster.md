# `comms_employee_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.comms_employee_roster` |
| **Business owner** | Internal Comms |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Active employee roster for communications group management including new hire flag. |
| **Business purpose** | Base for Internal Comms to manage communication groups with employee identification, org attributes, and a new-hire indicator. |
| **Business consumer** | Comms team |
| **Operational source of truth** | `metric_people.employee_snapshots` (+ `dw_*` joins where applicable). |
| **Delivery channel** | Google Sheets tab **Grupo** in workbook `1k69O446Nk2jwfVwqrh2e3lf9LhUlzPE9VBivMTrYcRk`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Portuguese column names preserved (`flag_LT`, ``fl_new_hire (ult 7 dias)``). `column_mapping_mode: name` on this table so those headers map correctly to Google Sheets. New-hire flag uses a **7-day** window from the D-1 snapshot date (`dt_hired > DATE_SUB(DATE_SUB(dt_reference, 1), 7)`), matching legacy `base_comms` behavior with daily D-1 data. |
