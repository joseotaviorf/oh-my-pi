# `xray_general_info_ext_recruiters` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.xray_general_info_ext_recruiters` |
| **Business owner** | Talent Acquisition |
| **Technical owner** | People Insights |
| **Domain** | People |
| **One-line summary** | X-Ray General Information roster restricted to bands 9 and below in Corp or Ops, for external recruiters. |
| **Business purpose** | Gives external recruiters a Google Sheets copy of X-Ray General Information. They do not have AppSheet access, so this filtered workbook is the delivery channel ([DBP-2109](https://quintoandar.atlassian.net/browse/DBP-2109)). |
| **Business consumer** | External recruiters (no AppSheet). |
| **Operational source of truth** | Same-day `reverse_reports.xray_general_info` partition (AppSheet infos_gerais contract). Population: `TRY_CAST(banda AS INT) <= 9`, `LOWER(vertical) IN ('corp', 'ops')`, not structure People, and not in Deborah Abi Saber's reporting line (gestor / L1–L7 / self). |
| **Delivery channel** | Google Sheets tab **Sheet1** in workbook [https://docs.google.com/spreadsheets/d/10FzAZ4lqQ2fA7yjXet7xoATBbohGN4jXzwl7itQmLEo/edit?usp=sharing](https://docs.google.com/spreadsheets/d/10FzAZ4lqQ2fA7yjXet7xoATBbohGN4jXzwl7itQmLEo/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Grain is one row per employee (same as `xray_general_info`). Exported headers match the AppSheet General Information tab, including `chapter` after `product`. Rows whose `banda` is not castable to integer are excluded. `structure = People` is out of scope. Anyone whose manager or L1–L7 name matches Abi Saber (spaces stripped) is out of scope, including Deborah herself. `L1`–`L7` and last-movement blanks inherit from the parent (`PAS-595`). `dt_last_update` is load-time metadata from the parent export. |
