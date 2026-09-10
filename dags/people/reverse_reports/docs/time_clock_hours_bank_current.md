# `time_clock_hours_bank_current` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.time_clock_hours_bank_current` |
| **Business owner** | julia.mesquita@quintoandar.com.br |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Current-month hours-bank balance rows per employee and balance date for the HR time-tracking control dashboard. |
| **Business purpose** | Feeds the Departamento Pessoal time-tracking Looker Studio dashboard with all balance snapshots in the current calendar month. Migrated from Daily Pipeline notebook `dashboard_controle_de_ponto` ([DBP-1845](https://quintoandar.atlassian.net/browse/DBP-1845)). |
| **Business consumer** | Departamento Pessoal (mariana.reberte@quintoandar.com.br). |
| **Operational source of truth** | `dw_time.fact_hours_bank_daily_totals` (OiTchau UI Banco Acumulado via `sum_minutes_running_balance`), `dw_employee_details.dim_employee`, `metric_people.employee_snapshots`, `dw_organization.dim_business_unit`. Gestores isentos exclusion still uses `dw_time.fact_hours_bank_rule_totals` + `dim_hours_bank_rule`. |
| **Delivery channel** | Google Sheets tab **current** in workbook [1HkKsgv9cJdtCdbc1jESL6N50V_o0wB3mKgosc8MO-U0](https://docs.google.com/spreadsheets/d/1HkKsgv9cJdtCdbc1jESL6N50V_o0wB3mKgosc8MO-U0/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy column names preserved. Balance columns store seconds (`sum_minutes_running_balance × 60`) for Looker compatibility. Grain: one row per employee × balance date in the load month (no per-bucket rows; `segment_label` / `group_name` = `total`). Excludes `Gestores_Isentos`. `bank_hours_padronizado` / `fl_mes_padronizado` follow empresa-specific month rules (SP/Classifieds monthly, MLSP bimonthly, MG semiannual). `fl_ultimo_dia_possivel` flags rows on the latest `dt_hours_bank_balanced` in the current-month extract. Super-admin emails appended to `access_list_no_employee`. |
