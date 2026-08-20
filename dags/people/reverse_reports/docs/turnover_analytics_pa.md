# `turnover_analytics_pa` — reverse export governance

| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.turnover_analytics_pa` |
| **Business owner** | People Insights |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Monthly turnover base (headcount, admissions, exits, exit-survey and exit-interview answers), reduced-PII, for the wider-audience People Analytics workbook. |
| **Business purpose** | People Insights and business leaders monitor monthly headcount, voluntary/involuntary/layoff turnover, and new-hire counts, sliced by org and demographics, without the full-PII talent attributes reserved for HRBPs. Migrated from Daily Pipeline notebook `dash_turnover_v2`, specifically its `base_turnover_v2_pa` view. This is the sibling of `turnover_dashboard`, with `cargo`, `potencial`, `criticidade`, `perf_final`, `escolaridade`, `faixa_etaria`, `faixa_salarial`, `grupo_banda`, `hrbp`, and the `access_list_all_leaders` roll-up removed — see `turnover_dashboard.md` for those. |
| **Business consumer** | People Insights and business leaders with access to the People Analytics workbook (wider audience than the main turnover dashboard, since HRBP/talent-sensitive columns are excluded). |
| **Operational source of truth** | `metric_people.employee_snapshots` (headcount, org, demographics, turnover flags) plus `datalake_pin_questionnaires_clean.{question_response, questionnaire_response, questionnaire_participant, questionnaire_base, questionnaire_translation, question_base, question_translation, question_answer_translation}` and `datalake_pin_core_clean.allocated_task_translation` (exit survey and exit interview answers), and `datalake_gsheets_people_clean.turnover_user_roles` (dashboard access-list roles sheet). Replaces the retired `datalake_people_analytics_sandbox.base_fotografias_email_l` / `base_completa_hierarquia` sandbox tables and the legacy `dw_employee` schema. |
| **Tenure bucket (3moTO)** | The first tenure value `a. menos de 3 meses` matches TARS New Hire Attrition / 3moTO via `days_employee_tenure < 90`. Later buckets still use whole calendar months from `months_employee_tenure`. The in-progress month may show a small 90-day-boundary drift until month-end close. Same rule as `turnover_dashboard`. |
| **Delivery channel** | Google Sheets tab **base_turnover_v2** in workbook [https://docs.google.com/spreadsheets/d/1NXWclDZfgZ61-UGANp7gDT1X_kEnjV-dIwS2f4lkQso](https://docs.google.com/spreadsheets/d/1NXWclDZfgZ61-UGANp7gDT1X_kEnjV-dIwS2f4lkQso). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
