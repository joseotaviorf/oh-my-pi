# `cost_center_mapping_pin` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.cost_center_mapping_pin` |
| **Business owner** | People Systems |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Cost center mapping with headcount and HRBP for PIN. |
| **Business purpose** | Cost center mapping export with active/inactive status, vertical, Codex L1/L2 owners, HRBP email, and headcount totals for PIN ingestion. Migrated from Daily Pipeline `reports_dw.py` view `base_de_para`. |
| **Business consumer** | People Systems |
| **Operational source of truth** | `dw_organization.dim_cost_center` and `dw_employee_details.fact_assignment_snapshots`. |
| **`l1_cc` / `l2_cc`** | Codex-sourced organizational-unit owners (`dim_cost_center.owner_l1_name` / `owner_l2_name`, `is_current = TRUE`) — added per `DBP-1545` so BPs can filter the sheet by L1/L2 instead of the individual PIN management chain. |
| **Delivery channel** | Google Sheets tab **new_de_para_pin**: https://docs.google.com/spreadsheets/d/1oJG4O_D8Dadz0UthfMJGWAstj-tlQSpdh4vAq3U_xfE |
| **Contract notes** | Legacy Portuguese column names preserved. One row per cost center code after deduplication (active preferred, then latest `ts_created`). |
