# `cost_center_mapping_pin` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.cost_center_mapping_pin` |
| **Business owner** | People Systems |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Cost center mapping with headcount and HRBP for PIN. |
| **Business purpose** | Cost center mapping export with active/inactive status, vertical, HRBP email, and headcount totals for PIN ingestion. Migrated from Daily Pipeline `reports_dw.py` view `base_de_para`. |
| **Business consumer** | People Systems |
| **Operational source of truth** | `dw_organization.dim_cost_center` and `dw_employee_details.fact_assignment_snapshots`. |
| **Delivery channel** | Google Sheets tab **new_de_para_pin**: https://docs.google.com/spreadsheets/d/1oJG4O_D8Dadz0UthfMJGWAstj-tlQSpdh4vAq3U_xfE |
| **Contract notes** | Legacy Portuguese column names preserved. One row per cost center code after deduplication (active preferred, then latest `ts_created`). |
