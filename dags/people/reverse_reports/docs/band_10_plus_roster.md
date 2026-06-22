# `band_10_plus_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.band_10_plus_roster` |
| **Business owner** | Leadership Academy |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Active band 10+ employees exported for Leadership Academy participation tracking. |
| **Business purpose** | Eligibility roster for the Leadership Academy program: active employees at band 10 and above, used to identify and manage who participates in Leadership Academy. Migrated from `people_reports` notebook cell `base_bandas_10`. |
| **Business consumer** | Leadership Academy |
| **Operational source of truth** | `metric_people.employee_snapshots` (+ `dw_*` joins where applicable). |
| **Delivery channel** | Google Sheets workbook **Leadership Academy | Public** (`1L6wdq54Mhze69tXYEFDTcOG2B0GNLFV7NO_hm4Zralg`), tab **base**. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Portuguese column names preserved. |
