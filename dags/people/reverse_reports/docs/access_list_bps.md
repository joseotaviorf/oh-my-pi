# `access_list_bps` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.access_list_bps` |
| **Business owner** | pedro.prates@quintoandar.com.br (Enterprise Engineering) |
| **Technical owner** | pedro.prates@quintoandar.com.br (Enterprise Engineering) |
| **Domain** | People |
| **One-line summary** | Base per-employee HRBP/leadership access list, for other reverse reports to reference. |
| **Business purpose** | Base access-control report maintained by Enterprise Engineering: exposes, per employee, which HRBP and leadership-chain emails are allowed to see that employee's row. Other reverse reports/sheets read this table (or its sheet) to drive their own row-level access control, instead of each one recomputing the HRBP/leadership chain independently. Replaces `access_list_dp`. |
| **Business consumer** | Enterprise Engineering (internal use; feeds other reverse reports). |
| **Operational source of truth** | `metric_people.employee_snapshots` (`access_list_no_employee` = HRBP plus leadership chain L0–L9, excluding the employee email). |
| **Delivery channel** | Google Sheets tab **access_list_bps** in workbook [https://docs.google.com/spreadsheets/d/1Wi7zrUxlhdNCX4SgBvylURm1uD0V-daDMPziuEUnjrE/](https://docs.google.com/spreadsheets/d/1Wi7zrUxlhdNCX4SgBvylURm1uD0V-daDMPziuEUnjrE/). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Grain: one row per `email` on the current employee snapshot (`is_current_for_employee = TRUE`), including active and terminated employees. When multiple assignments share the same email, prefer the active row, then highest `person_number`; `assignment_number` reflects that winning row. `access_list` is a single string with all access emails concatenated (HRBP + leadership chain L0–L9, employee excluded). |
