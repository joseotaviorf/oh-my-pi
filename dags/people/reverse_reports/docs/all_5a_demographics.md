# `all_5a_demographics` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.all_5a_demographics` |
| **Business owner** | HRBP requester ([PDA-536](https://quintoandar.atlassian.net/browse/PDA-536)) |
| **Technical owner** | People Insights |
| **Domain** | People |
| **One-line summary** | Daily active All 5A employee demographics for the Rituals app. |
| **Business purpose** | Feeds the Rituals app with current active-employee demographics (identity, manager, job family, cost center, structure, residence, L0–L3 hierarchy, legal entity, manager flag) for GQA leaders. Google Sheets is the contract the app reads. Request [PDA-536](https://quintoandar.atlassian.net/browse/PDA-536); delivery [DBP-2019](https://quintoandar.atlassian.net/browse/DBP-2019). |
| **Business consumer** | All GQA leaders (via Rituals). |
| **Operational source of truth** | `metric_people.employee_snapshots`. |
| **Delivery channel** | Google Sheets tab **ALL5A1** in workbook [https://docs.google.com/spreadsheets/d/1I-DQpGOmGYUMJeJojsbFvWeG7YhkjU_g0VzlSFoo3Po/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1I-DQpGOmGYUMJeJojsbFvWeG7YhkjU_g0VzlSFoo3Po/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Grain: one row per active primary assignment, all countries. Headers: `nome`, `email`, `gestor`, `classe_cargo`, `centro_de_custo`, `structure`, `pais`, `residencia_uf`, `residencia_cidade`, `l0_gestor`, `l1_gestor`, `l2_gestor`, `l3_gestor`, `empresa`, `fl_lider` (`l0_gestor` added vs the original CSV). Current-state filter: `is_current` + `is_primary_assignment_for_snapshot` + `status = active`. |
