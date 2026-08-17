# `xray_legacy_performa` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.xray_legacy_performa` |
| **Business owner** | People Insights |
| **Technical owner** | Enterprise Engineering and People Insights |
| **Domain** | People |
| **One-line summary** | Legacy Performa HOW/WHAT scores for X-Ray AppSheet. |
| **Business purpose** | Historical pre-modern Performa cycles for X-Ray / Employee Data Center. Migrated from Daily Pipeline notebook `xray_update` ([DBP-1447](https://quintoandar.atlassian.net/browse/DBP-1447)). |
| **Business consumer** | People (company-wide via AppSheet). |
| **Operational source of truth** | `datalake_gsheets_people_clean.legacy_performance_review` (exception — no DW path for legacy HOW/WHAT scores); org context from `metric_people.employee_snapshots`. |
| **Delivery channel** | Google Sheets tab **legacy_performa** in workbook [https://docs.google.com/spreadsheets/d/1Ka3EGuF-DSHrHFNQYH3Mh9G9GwogRf4lEsDO1sLjExs/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1Ka3EGuF-DSHrHFNQYH3Mh9G9GwogRf4lEsDO1sLjExs/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Portuguese score column aliases preserved. |

## Notebook usage context (X-Ray / Employee Data Center)

Former Daily Pipeline notebook `xray_update` feeds the company-wide **AppSheet X-Ray / Employee Data Center** (current and historical employee data).

| Field | Value |
| --- | --- |
| **Notebook owner (legacy)** | `leonardo.oliveira@quintoandar.com.br` |
| **AppSheet app** | [EmployeeDataCenter-v2](https://www.appsheet.com/Template/AppDef?appName=EmployeeDataCenter-v2-1001530477&utm_source=share_app_link) |
| **Sheets folder** | [Drive folder with updated workbooks](https://drive.google.com/drive/folders/1pnoLBmwyIxkR2Ta4NQ73PKGOQtm6hVtp) |
