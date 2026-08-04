# `performa_talent_pin_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.performa_talent_pin_roster` |
| **Business owner** | People Team (Performa & Talent) |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Full employee roster with hierarchy and demographics for the Performa & Talent PIN dashboard. |
| **Business purpose** | Base for the Performa & Talent Looker Studio dashboard (PIN acquired employees). Migrated from `people_reports` notebook view `dash_performa_talent`. |
| **Business consumer** | Performa & Talent dashboard — https://lookerstudio.google.com/u/0/reporting/f9cf50e1-0a6b-4ad2-9f85-47a83c5084c3/page/p_b7ebtsxzrd/edit |
| **Operational source of truth** | `metric_people.employee_snapshots` (+ `dw_organization.dim_business_unit` for `empresa`). |
| **Delivery channel** | Google Sheets tab **api_PIN_adquiridas** in workbook https://docs.google.com/spreadsheets/d/1DR7EX8X8eufXEB8leXCWLRiEorJV0v7wJB5FSTkiuas. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Portuguese column names preserved. Grain: one row per employee on the current snapshot (`is_current_for_employee = TRUE`), including active and terminated. Tier-2 validation (2026-08-03): zero-diff columns include `nome`, `email`, `status`, `genero`, `cpf`, `dt_last_update`, `marca_produto_dedicado`. Remaining diffs are DW 2.0 org/job taxonomy drift (`team`, `centro_de_custo`, `cargo`) and NULL `employment_type` on some terminated rows — documented in `.cursor/temp/DBP-1824/.../validation_report.md`. |
