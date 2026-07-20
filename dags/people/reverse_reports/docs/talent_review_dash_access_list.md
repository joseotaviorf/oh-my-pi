# `talent_review_dash_access_list` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.talent_review_dash_access_list` |
| **Business owner** | Kevin Trindade |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Current employee access-list rows used to segregate Talent Review Looker dashboard access. |
| **Business purpose** | Feeds the Talent Review Looker Studio dashboard access controls (PDS / `base_analytics` tab). Kept on Google Sheets while the TR dashboard remains Looker-backed; this is an Exodus notebook migration. Migrated from Daily Pipeline notebook `dash_talent_review` ([DBP-1756](https://quintoandar.atlassian.net/browse/DBP-1756)). |
| **Business consumer** | Performance team (focal: Victor Martins). |
| **Operational source of truth** | `metric_people.employee_snapshots` (`access_list_no_employee_no_hrbp`, hierarchy names L1–L6, HRBP email, manager name). |
| **Delivery channel** | Google Sheets tab **base_analytics** in workbook [https://docs.google.com/spreadsheets/d/1-ZcEzJ1Q_bF51iweAFS7rHkgqr9WPdjic_9B6hd0T4k/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1-ZcEzJ1Q_bF51iweAFS7rHkgqr9WPdjic_9B6hd0T4k/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Looker headers preserved (`Número de Pessoa`, `gestor_pin`, etc.). `column_mapping_mode: name` required for accented / spaced headers. Person number cast to string (legacy `force_int_to_str`). Hierarchy L1–L6 are **names** (not emails); HRBP is email. |
