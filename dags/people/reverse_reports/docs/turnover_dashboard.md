# `turnover_dashboard` — reverse export governance

| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.turnover_dashboard` |
| **Business owner** | People Insights |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Monthly turnover base (headcount, admissions, exits, exit-survey and exit-interview answers) with full-PII talent attributes for the main People turnover dashboard. |
| **Business purpose** | People Insights and business leaders monitor monthly headcount, voluntary/involuntary/layoff turnover, and new-hire counts, sliced by org, demographics, and talent attributes (job title, potential/criticality, performance, education, salary band, HRBP). Migrated from Daily Pipeline notebook `dash_turnover_v2`, specifically its `base_turnover_v2` view. See also `turnover_analytics_pa.md` for the sibling, reduced-PII export feeding the wider-audience People Analytics workbook. |
| **Business consumer** | People Insights, HRBPs, org leadership (via the People turnover dashboard). |
| **Operational source of truth** | `metric_people.employee_snapshots` (headcount, org, demographics, talent, turnover flags) plus `datalake_pin_questionnaires_clean.{question_response, questionnaire_response, questionnaire_participant, questionnaire_base, questionnaire_translation, question_base, question_translation, question_answer_translation}` and `datalake_pin_core_clean.allocated_task_translation` (exit survey and exit interview answers), `datalake_pin_core_clean.foundation_lookup_value` (education-level PT-BR canonicalization), and `datalake_gsheets_people_clean.turnover_user_roles` (dashboard access-list roles sheet). Replaces the retired `datalake_people_analytics_sandbox.base_fotografias_email_l` / `base_completa_hierarquia` sandbox tables and the legacy `dw_employee` schema. |
| **Delivery channel** | Google Sheets tab **base_turnover_v2** in workbook [https://docs.google.com/spreadsheets/d/1d4zHTWcfKlp56euTnCtEMjWrhynJGQJWTfgK_dnmTr4](https://docs.google.com/spreadsheets/d/1d4zHTWcfKlp56euTnCtEMjWrhynJGQJWTfgK_dnmTr4). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
