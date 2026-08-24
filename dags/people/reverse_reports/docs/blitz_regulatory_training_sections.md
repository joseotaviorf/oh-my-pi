# `blitz_regulatory_training_sections` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.blitz_regulatory_training_sections` |
| **Business owner** | julia.mesquita@quintoandar.com.br (Learning) |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Section-level regulatory training progress for active employees on the Blitz dashboard. |
| **Business purpose** | Feeds the Blitz Looker dashboard (90-day regulatory training compliance) with one row per employee and pathway section. Managed by the Learning team and Julia. Migrated from Daily Pipeline notebook `dash_blitz_degreed` ([DBP-1454](https://quintoandar.atlassian.net/browse/DBP-1454)). |
| **Business consumer** | Learning team and Julia (Google Sheets); organization-wide via [Looker Studio Blitz dashboard](https://lookerstudio.google.com/reporting/931dabee-3d0e-49f9-8b71-8bcde4aacb97/page/Z3NsF/edit). |
| **Operational source of truth** | `datalake_learning.*`, `datalake_degreed_clean.*`, `metric_people.employee_snapshots`, `dw_organization.dim_business_unit`, `dw_time.fact_absence_requests`, `dw_time.dim_absence_type`. Enrich/clean Degreed exception — no DW path for completion grain. |
| **Delivery channel** | Google Sheets tab **blitz_database** in workbook [1JOWWPbAqzXce0uIHM9PJAVgwNsCPmGZedYCE_e2ARCQ](https://docs.google.com/spreadsheets/d/1JOWWPbAqzXce0uIHM9PJAVgwNsCPmGZedYCE_e2ARCQ/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy column names preserved. Active employees only (including those on approved leave). Campaign window 2026-04-16–2026-07-24 with extended-deadline columns (`dias_ganhos`, `data_limite_bruta`, `nova_data_limite`, etc.). Regulatory pathway IDs hardcoded. |
