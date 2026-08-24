# `blitz_regulatory_training_pathway_completions` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.blitz_regulatory_training_pathway_completions` |
| **Business owner** | julia.mesquita@quintoandar.com.br (Learning) |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Employees with 100% completed Degreed pathways eligible for certificate tracking. |
| **Business purpose** | Supplies the certificate base tab with completed pathway records for Learning operations. Migrated from Daily Pipeline notebook `dash_blitz_degreed` view `invite_final` ([DBP-1454](https://quintoandar.atlassian.net/browse/DBP-1454)). |
| **Business consumer** | Learning team and Julia. |
| **Operational source of truth** | `datalake_learning.all_completions`, `datalake_learning.user_identifier_mapping`, `datalake_degreed_clean.pathway_details`, `metric_people.employee_snapshots`, `dw_organization.dim_business_unit`. Enrich/clean Degreed exception — no DW path for pathway completion grain. |
| **Delivery channel** | Google Sheets tab **certificados_base** in workbook [1RNvYAYC2KlpigkQ5Xz9nmjuaoIOf5GHbmUX-AG9M8bE](https://docs.google.com/spreadsheets/d/1RNvYAYC2KlpigkQ5Xz9nmjuaoIOf5GHbmUX-AG9M8bE/edit?gid=1552005319#gid=1552005319). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy column names preserved. Filter: `pct_completed_required = 100`, pathway ID allowlist, `dt_completion >= 2026-04-16`. |
