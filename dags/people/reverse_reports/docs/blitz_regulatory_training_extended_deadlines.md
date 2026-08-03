# `blitz_regulatory_training_extended_deadlines` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.blitz_regulatory_training_extended_deadlines` |
| **Business owner** | julia.mesquita@quintoandar.com.br (Learning) |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Active employees who gained extended days to complete Blitz regulatory training pathways. |
| **Business purpose** | Roster of employees with extended campaign deadlines (`dias_ganhos > 0`) for the Blitz regulatory training program. One row per employee and primary pathway. Managed by the Learning team. |
| **Business consumer** | Learning team and Julia (Google Sheets). |
| **Operational source of truth** | `datalake_learning.*`, `datalake_degreed_clean.*`, `metric_people.employee_snapshots`, `dw_time.fact_absence_requests`. Enrich/clean Degreed exception — no DW path for completion grain. |
| **Delivery channel** | Google Sheets tab **automacao** in workbook [18eCVoI2krrzU9oS2x7BPpHfaVZN4MAVXIUGUeJLe9I4](https://docs.google.com/spreadsheets/d/18eCVoI2krrzU9oS2x7BPpHfaVZN4MAVXIUGUeJLe9I4/edit?gid=1942009244). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Active employees only. Campaign window 2026-04-16–2026-07-24. Includes only rows with `dias_ganhos > 0` (absence or new-hire grace). `data_final_ajustada` applies weekend adjustment to the raw extended deadline. Regulatory pathway IDs hardcoded. |
