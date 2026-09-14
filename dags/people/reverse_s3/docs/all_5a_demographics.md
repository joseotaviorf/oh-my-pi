# `all_5a_demographics` — reverse export governance

| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_s3.all_5a_demographics` |
| **Business owner** | HRBP requester ([PDA-536](https://quintoandar.atlassian.net/browse/PDA-536)) |
| **Technical owner** | People Insights |
| **Domain** | People |
| **One-line summary** | Daily active All 5A employee demographics exported as a single CSV object for the Rituals app. |
| **Business purpose** | Feeds Rituals with the same active-employee demographics roster already scheduled to Google Sheets from `reverse_reports.all_5a_demographics` (identity, manager, job family, salary band, cost center, structure, residence, L0–L7 hierarchy, legal entity, manager flag, access list). Rituals reads this S3 object in addition to the ALL5A1 tab. Request [PDA-536](https://quintoandar.atlassian.net/browse/PDA-536). |
| **Business consumer** | All GQA leaders (via Rituals). |
| **Operational source of truth** | `metric_people.employee_snapshots` (same filter as `reverse_reports.all_5a_demographics`: `is_current`, `is_primary_assignment_for_snapshot`, `status = active`). |
| **Delivery channel** | S3 object **`s3://5a-base44-office/ritualsapp/list_of_employees.csv`** (prod). Canned ACL `bucket-owner-full-control` on write. Forno redirects to `people_bucket` under `reverse_s3_test/ritualsapp/list_of_employees.csv` (no partner ACL). |
| **Grain** | One row per active primary assignment on `metric_people.employee_snapshots`. |
| **Contract notes** | Same business headers as the ALL5A1 sheet: `nome`, `email`, `gestor`, `classe_cargo`, `banda`, `centro_de_custo`, `structure`, `pais`, `residencia_uf`, `residencia_cidade`, `l0_gestor`–`l7_gestor`, `empresa`, `fl_lider`, `access_list`. Lake partition columns are **not** written to the CSV. `banda` is `employee_snapshots.band`. `access_list` is `employee_snapshots.access_list`. CSV written by Spark (`header=true`, comma separator, UTF-8, empty nulls). |
