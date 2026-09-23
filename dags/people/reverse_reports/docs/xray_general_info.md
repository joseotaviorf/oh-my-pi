# `xray_general_info` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.xray_general_info` |
| **Business owner** | People Insights |
| **Technical owner** | Enterprise Engineering and People Insights |
| **Domain** | People |
| **One-line summary** | Current employee roster (org, tenure, talent, access list) for the X-Ray AppSheet. |
| **Business purpose** | Feeds the AppSheet X-Ray / Employee Data Center so the company can view current employee data. Migrated from Daily Pipeline notebook `xray_update` ([DBP-1447](https://quintoandar.atlassian.net/browse/DBP-1447)). |
| **Business consumer** | People (company-wide via AppSheet). |
| **Delivery channel** | Google Sheets tab **infos_gerais** in workbook [https://docs.google.com/spreadsheets/d/1srO0ZeUk-nhoTwX8d0tj7aY0g71qtHBOjR4Ysp7QaTs/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1srO0ZeUk-nhoTwX8d0tj7aY0g71qtHBOjR4Ysp7QaTs/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | `access_list` always includes `gbraga@quintoandar.com.br` (legacy X-Ray L0 ACL, confirmed with People Insights), then hierarchy L0–L7, HRBP, and the employee email, de-duplicated. Emails come from `identifier_mapping` (spaces and CR/LF already stripped there). Other `xray_*` EDC tabs inherit this list from `xray_general_info`. `L1`–`L7` are NULL when the level name matches the employee (`PAS-595`); sibling EDC tabs inherit those cleaned names. Grain is one row per `is_current_for_employee`. Current-cost-center HRBP fallback joins `dim_cost_center` on `(id_organization, cost_center_code)` with `is_current = TRUE`. `chapter` comes from `metric_people.employee_snapshots.chapter` (CODEX; `'-1'` → NULL) and sits after `product`; PwD org overlay does not rewrite it. Last compensation movement (`pct_ultimo_movimento`, `tipo_ultimo_movimento`, `dt_ultimo_movimento`) is blanked when `dt_ultimo_movimento` is before `dt_inicio`. `tempo_na_banda_em_meses` is populated for all **active** employees from `metric_people.employee_snapshots.months_tenure_in_band` (sourced from `dw_compensation.fact_compensations`); dismissed rows stay NULL. `pos_faixa` is lake `range_position` (percent of midpoint, e.g. 98.18) divided by 100 so the export is a ratio (e.g. 0.9818). People on cost center **906x1x** (inclusão / PwD pool; matched on `cost_center_code`, not the accented display name) or young apprentices on **907x1x** keep their own cost center; `vertical`, `structure`, and `team` are taken from the first manager up the chain who is not PwD (active laudo, self-declared, or medical flags) and not on 906x1x. Pending or inactive disability rows do not count as PwD for this walk. |


## Notebook usage context (X-Ray / Employee Data Center)

Former Daily Pipeline notebook `xray_update` feeds the company-wide **AppSheet X-Ray / Employee Data Center** (current and historical employee data).

| Field | Value |
| --- | --- |
| **Notebook owner (legacy)** | `leonardo.oliveira@quintoandar.com.br` |
| **AppSheet app** | [EmployeeDataCenter-v2](https://www.appsheet.com/Template/AppDef?appName=EmployeeDataCenter-v2-1001530477&utm_source=share_app_link) |
| **Sheets folder** | [Drive folder with updated workbooks](https://drive.google.com/drive/folders/1pnoLBmwyIxkR2Ta4NQ73PKGOQtm6hVtp) |
