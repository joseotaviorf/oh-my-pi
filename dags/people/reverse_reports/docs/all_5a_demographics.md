# `all_5a_demographics` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.all_5a_demographics` |
| **Business owner** | HRBP requester ([PDA-536](https://quintoandar.atlassian.net/browse/PDA-536)) |
| **Technical owner** | People Insights |
| **Domain** | People |
| **One-line summary** | Daily active All 5A employee demographics for the Rituals app. |
| **Business purpose** | Feeds the Rituals app with current active-employee demographics (identity, manager, job family, salary band, cost center, structure, residence, L0–L7 hierarchy, legal entity, manager flag, access list) for GQA leaders. Google Sheets remains a delivery contract; the same roster is also written to S3 by `reverse_s3.all_5a_demographics`. Request [PDA-536](https://quintoandar.atlassian.net/browse/PDA-536); delivery [DBP-2019](https://quintoandar.atlassian.net/browse/DBP-2019). |
| **Business consumer** | All GQA leaders (via Rituals). |
| **Operational source of truth** | `metric_people.employee_snapshots`. |
| **Delivery channel** | Google Sheets tab **ALL5A1** in workbook [https://docs.google.com/spreadsheets/d/1I-DQpGOmGYUMJeJojsbFvWeG7YhkjU_g0VzlSFoo3Po/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1I-DQpGOmGYUMJeJojsbFvWeG7YhkjU_g0VzlSFoo3Po/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. Parallel CSV: `s3://5a-base44-office/ritualsapp/list_of_employees.csv` via `bietlejuice.reverse_s3`. |
| **Contract notes** | Grain: one row per active primary assignment, all countries. Headers: `nome`, `email`, `gestor`, `classe_cargo`, `banda`, `centro_de_custo`, `structure`, `pais`, `residencia_uf`, `residencia_cidade`, `l0_gestor`–`l7_gestor`, `empresa`, `fl_lider`, `access_list`. `banda` is `employee_snapshots.band`. `access_list` is `employee_snapshots.access_list` (employee + HRBP + L0–L9 work emails). Current-state filter: `is_current` + `is_primary_assignment_for_snapshot` + `status = active`. Partition columns `year`/`month`/`day` are not sent to Google Sheets. |
