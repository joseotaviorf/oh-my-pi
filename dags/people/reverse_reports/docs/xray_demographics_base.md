# `xray_demographics_base` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.xray_demographics_base` |
| **Business owner** | People Insights |
| **Technical owner** | Enterprise Engineering and People Insights |
| **Domain** | People |
| **One-line summary** | Monthly DEI headcount aggregates with AppSheet access lists for X-Ray. |
| **Business purpose** | DEI demographics cubes for X-Ray / Employee Data Center. Migrated from Daily Pipeline notebook `xray_update` ([DBP-1447](https://quintoandar.atlassian.net/browse/DBP-1447)). |
| **Business consumer** | People (company-wide via AppSheet). |
| **Operational source of truth** | `metric_people.employee_snapshots`; `dw_organization.dim_business_unit`; super-admin ACL roles temporarily hardcoded as a literal list (was `datalake_people_analytics_sandbox.people_dashboards_super_admins`, a manually curated 9-row list with no equivalent in any governed layer — removed to avoid a sandbox dependency; **TODO:** migrate to a proper clean-layer table). |
| **Delivery channel** | Google Sheets tab **base_demographics** in workbook [https://docs.google.com/spreadsheets/d/1PxwVEi5_S8YbyN8j4jMeHuKnk2wEQajPHcGmLqlvrSg/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1PxwVEi5_S8YbyN8j4jMeHuKnk2wEQajPHcGmLqlvrSg/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Aggregated grain matches notebook dimensions. Label/bucket strings may differ from sandbox until Tier 2 sign-off. |

## Notebook usage context (X-Ray / Employee Data Center)

Former Daily Pipeline notebook `xray_update` feeds the company-wide **AppSheet X-Ray / Employee Data Center** (current and historical employee data).

| Field | Value |
| --- | --- |
| **Notebook owner (legacy)** | `leonardo.oliveira@quintoandar.com.br` |
| **AppSheet app** | [EmployeeDataCenter-v2](https://www.appsheet.com/Template/AppDef?appName=EmployeeDataCenter-v2-1001530477&utm_source=share_app_link) |
| **Sheets folder** | [Drive folder with updated workbooks](https://drive.google.com/drive/folders/1pnoLBmwyIxkR2Ta4NQ73PKGOQtm6hVtp) |
