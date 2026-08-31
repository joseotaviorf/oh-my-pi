# `teva_employee_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.teva_employee_roster` |
| **Business owner** | leonardo.oliveira@quintoandar.com.br (People Analytics) |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Active-employee roster with leadership-chain access list feeding the TEVA questionnaire workbook. |
| **Business purpose** | Feeds TEVA (team-effectiveness survey process): the active-employee roster identifies team leaders (`role`) and drives report access control (`access_list`) in the TEVA questionnaire workbook. Google Sheets because TEVA operates on the workbook itself — the requisition/answer/report tabs live in the same spreadsheet, so the employee roster must live there too. Migrated from Daily Pipeline notebook `ai_teva_update`. |
| **Business consumer** | TEVA questionnaire tooling (People Analytics). |
| **Delivery channel** | Google Sheets tab **lista de funcionários** in workbook [https://docs.google.com/spreadsheets/d/1zIF0bBTNYdW3ryUiySqZ6lNp4z7MTo_Nv8w_4IP0nWQ/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1zIF0bBTNYdW3ryUiySqZ6lNp4z7MTo_Nv8w_4IP0nWQ/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Grain: one row per primary active assignment. Legacy headers preserved (`id_colaborador`, `email`, `nome`, `role`, `hrbp`, `vertical`, `structure`, `empresa`, `pais`, `cargo`, `access_list`). `access_list` = comma-joined L0–L9 leadership emails with legacy CEO fallback (`gbraga@`) — no employee/HRBP emails, matching the notebook contract. Known accepted drift vs legacy `clean_string`: `nome`/`cargo`/`empresa` keep proper case and accents (same drift accepted across prior Daily Pipeline migrations); emails and `id_colaborador` stay lowercased. Accepted corrections vs legacy (Tier 2 validated, 2026-08-29): `pais` shows the real country in Portuguese for 62 Deel/MLSP/LatAm rows the notebook hard-coded to `brasil`; `cargo` carries the DW 2.0 job catalog `" mx"` suffix on 62 Mexico rows; 2 stale `empresa` rows (`Remote` → `QuintoAndar Portugal`) and 1 legacy email with a trailing newline are fixed. Legacy `ORDER BY email` not guaranteed by the export path. |
