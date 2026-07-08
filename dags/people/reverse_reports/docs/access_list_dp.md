# `access_list_dp` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.access_list_dp` |
| **Business owner** | DP — `mariana.reberte@quintoandar.com.br` |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Per-employee Google Sheets access list for leaders and HR business partners (time bank). |
| **Business purpose** | Supplies the `access_list` tab used by the time bank workbook so leaders and BPs can see only the rows they are allowed to view. Migrated from Daily Pipeline notebook `access_list.py` (cell `access_list_dp`). |
| **Business consumer** | DP; end users are leaders and BPs via the time bank spreadsheet. |
| **Operational source of truth** | `metric_people.employee_snapshots` (`access_list_no_employee` = HRBP plus leadership chain L0–L9, excluding the employee email). |
| **Delivery channel** | Google Sheets tab **access_list** in workbook `1_R9bEBjOFQnVMjQgUNjyeZtvbyvy7ZSqtU59c_jddLc`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy column names preserved (`email`, `access_list`). Grain: one row per `work_email` on the current employee snapshot (`is_current_for_employee = TRUE`), including active and terminated employees to match legacy `base_completa_hierarquia` volumetry (~9.9k rows). When multiple primary assignments share the same email, prefer the active row, then highest `person_number`. **Signed-off Tier 1 drift:** one legacy-only row (`only_in_legacy = 1`) is a test user (`is_user_test = true` in `identifier_mapping`) excluded from `employee_snapshots`; expected and acceptable for production. |
