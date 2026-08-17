# `xray_talent_review_edc` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.xray_talent_review_edc` |
| **Business owner** | People Insights |
| **Technical owner** | Enterprise Engineering and People Insights |
| **Domain** | People |
| **One-line summary** | Talent review ratings by cycle for X-Ray AppSheet. |
| **Business purpose** | Feeds Talent Review history into X-Ray / Employee Data Center. Migrated from Daily Pipeline notebook `xray_update` ([DBP-1447](https://quintoandar.atlassian.net/browse/DBP-1447)). |
| **Business consumer** | People (company-wide via AppSheet). |
| **Operational source of truth** | `dw_performance.fact_talent_reviews` joined to `dim_committee_meeting` / `dim_cycle_period` / `dim_talent_rating` for ciclo and ratings; `email_avaliador` resolves the evaluator's manager via `dw_employee_details.dim_management_hierarchy` + `fact_assignment_snapshots` as of the committee meeting date. Org context from `metric_people.employee_snapshots`. Replaces the retired `datalake_people_analytics_sandbox.talent_review_history` (validated at 100% row/value parity). |
| **Delivery channel** | Google Sheets tab **base_tr_edc** in workbook [https://docs.google.com/spreadsheets/d/1EiKVbJVWgjx976a1CUZp8sGSxgGf47XHL-TFPLkxL9A/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1EiKVbJVWgjx976a1CUZp8sGSxgGf47XHL-TFPLkxL9A/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy headers preserved. `ciclo` kept as legacy `YYYY-Qn` / `YYYY-Hn` (UPPER), rebuilt from `dim_cycle_period.reference_period` + meeting year. |

## Notebook usage context (X-Ray / Employee Data Center)

Former Daily Pipeline notebook `xray_update` feeds the company-wide **AppSheet X-Ray / Employee Data Center** (current and historical employee data).

| Field | Value |
| --- | --- |
| **Notebook owner (legacy)** | `leonardo.oliveira@quintoandar.com.br` |
| **AppSheet app** | [EmployeeDataCenter-v2](https://www.appsheet.com/Template/AppDef?appName=EmployeeDataCenter-v2-1001530477&utm_source=share_app_link) |
| **Sheets folder** | [Drive folder with updated workbooks](https://drive.google.com/drive/folders/1pnoLBmwyIxkR2Ta4NQ73PKGOQtm6hVtp) |
