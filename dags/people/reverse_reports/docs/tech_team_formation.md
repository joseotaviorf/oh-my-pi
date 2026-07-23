# `tech_team_formation` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.tech_team_formation` |
| **Business owner** | People Analytics — Leonardo Oliveira |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Product & Tech team formation roster for L1-scoped active employees on the Full Base 5A sheet. |
| **Business purpose** | Refreshes employee master data on the Product & Tech team formation workbook while preserving team-structure columns maintained in the sheet. Migrated from Daily Pipeline notebook `team_formation_update` ([DBP-1451](https://quintoandar.atlassian.net/browse/DBP-1451)). Interim Google Sheets delivery during the Databricks Exodus cutover. |
| **Business consumer** | Product and Tech leaders. |
| **Operational source of truth** | `metric_people.employee_snapshots` for employee master fields; `datalake_gsheets_people_clean.team_formation_product_tech` for team-structure columns (`Team_1__Primary` through `Team_10`, `Line_Leader`, `Team_Leader`) from sheet `team_formation_tech_active`. |
| **Delivery channel** | Google Sheets tab **Full Base 5A** in workbook [https://docs.google.com/spreadsheets/d/1uyWQMdfjN1AiQ-h5xU6TWKPQO9eiVGPkFck3wHL17AI/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1uyWQMdfjN1AiQ-h5xU6TWKPQO9eiVGPkFck3wHL17AI/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy header names preserved (`Employees name`, `Team_1__Primary`, `Cost Center`, etc.). Grain: one row per active primary assignment in the L1 scope (Paulo Golgher, Larissa Fontaine, Rafael Dantas de Castro) excluding nine legacy cost centers. Current-state filter: `is_current_for_employee = TRUE` + `is_primary_assignment_for_snapshot = TRUE`. `fl_lider` uses legacy values `L` / `CI` from `employee_snapshots.is_manager`. Team-structure join reuses existing `team_formation_product_tech` ingestion (`regexp_extract(assignment_number, '[ec](\\d+)', 1) = person_number`). **Validation sign-off (2026-07-10):** Tier 1 PASS (872 = 872). Tier 2 employee master accepted — DW 2.0 (`employee_snapshots`) treated as source of truth; 19 `fl_lider` drifts and 1 `Admission` drift (`e122175-4`) documented and waived. **Forno run waived** (contributor without Forno access). |
