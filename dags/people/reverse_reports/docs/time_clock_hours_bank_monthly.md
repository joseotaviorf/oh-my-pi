# `time_clock_hours_bank_monthly` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.time_clock_hours_bank_monthly` |
| **Business owner** | julia.mesquita@quintoandar.com.br |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Monthly hours-bank balances per employee for the HR time-tracking control dashboard. |
| **Business purpose** | Feeds the Departamento Pessoal time-tracking Looker Studio dashboard with one row per employee per month (deduplicated month-end balance). Migrated from Daily Pipeline notebook `dashboard_controle_de_ponto` ([DBP-1844](https://quintoandar.atlassian.net/browse/DBP-1844)). |
| **Business consumer** | Departamento Pessoal (mariana.reberte@quintoandar.com.br). |
| **Operational source of truth** | `dw_time.fact_hours_bank_daily_totals` (OiTchau UI Banco Acumulado via `sum_minutes_running_balance`), `dw_employee_details.dim_employee`, `metric_people.employee_snapshots`, `dw_organization.dim_business_unit`. Gestores isentos exclusion still uses `dw_time.fact_hours_bank_rule_totals` + `dim_hours_bank_rule`. |
| **Delivery channel** | Google Sheets tab **horas_extras** in workbook [1HkKsgv9cJdtCdbc1jESL6N50V_o0wB3mKgosc8MO-U0](https://docs.google.com/spreadsheets/d/1HkKsgv9cJdtCdbc1jESL6N50V_o0wB3mKgosc8MO-U0/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy column names preserved. Balance columns (`bank_hours`, `bank_hours_padronizado`) store seconds (`sum_minutes_running_balance × 60`) for Looker compatibility. `segment_label` / `group_name` are fixed to `total` (UI-aligned daily grain, no per-bucket rows). Excludes `Gestores_Isentos`. Grain: one row per `person_number` × calendar month (`ROW_NUMBER` on closed balance). `bank_hours_padronizado` / `fl_mes_padronizado` follow empresa-specific month rules (SP/Classifieds monthly, MLSP bimonthly, MG semiannual). Super-admin emails appended to `access_list_no_employee`. |
