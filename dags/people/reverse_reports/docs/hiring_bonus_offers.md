# `hiring_bonus_offers` — reverse export governance

| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.hiring_bonus_offers` |
| **Business owner** | TA (Talent Acquisition) |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Accepted Greenhouse offers with a hiring bonus, for TA/Finance bonus payout processing. |
| **Business purpose** | TA and Finance track candidates with an approved hiring bonus offer to process the bonus payment. Migrated from Daily Pipeline notebook `hiring_bonus.sql` ([DBP-1834](https://quintoandar.atlassian.net/browse/DBP-1834)). |
| **Business consumer** | TA / Finance. |
| **Operational source of truth** | `datalake_greenhouse_v3_clean.{offers, candidates, jobs, departments}` and `datalake_hiring.job_openings` (enrich, `enrich_hiring` DAG). No deprecated sources — the migrated notebook cell already used Greenhouse v3. |
| **Delivery channel** | Google Sheets tab **base_hiring_gh** in workbook [https://docs.google.com/spreadsheets/d/1SNPW37g1l96rSgAJeQ9iAM0NJlDHxfJlGZ3iJZ4ico4/edit?gid=1890076094#gid=1890076094](https://docs.google.com/spreadsheets/d/1SNPW37g1l96rSgAJeQ9iAM0NJlDHxfJlGZ3iJZ4ico4/edit?gid=1890076094#gid=1890076094). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
