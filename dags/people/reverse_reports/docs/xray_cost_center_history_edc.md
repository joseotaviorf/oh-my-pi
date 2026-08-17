# `xray_cost_center_history_edc` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.xray_cost_center_history_edc` |
| **Business owner** | People Insights |
| **Technical owner** | Enterprise Engineering and People Insights |
| **Domain** | People |
| **One-line summary** | Cost center tenure windows per employee for X-Ray AppSheet. |
| **Business purpose** | Historical cost center changes for X-Ray / Employee Data Center. Migrated from Daily Pipeline notebook `xray_update` ([DBP-1447](https://quintoandar.atlassian.net/browse/DBP-1447)). |
| **Business consumer** | People (company-wide via AppSheet). |
| **Operational source of truth** | `metric_people.employee_snapshots` (monthly primary assignments). |
| **Delivery channel** | Google Sheets tab **historico_ccs** in workbook [https://docs.google.com/spreadsheets/d/1FstByzd87F4D7HhXAYtZww4rOCGx2hiiLrl_ffVjtEA/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1FstByzd87F4D7HhXAYtZww4rOCGx2hiiLrl_ffVjtEA/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Grain: one row per assignment + cost center tenure stint (min/max `dt_month_reference`). Stints use gaps-and-islands over the cost center identifier so a cost center revisited later gets a separate row instead of merging into the same window. |

## Notebook usage context (X-Ray / Employee Data Center)

Former Daily Pipeline notebook `xray_update` feeds the company-wide **AppSheet X-Ray / Employee Data Center** (current and historical employee data).

| Field | Value |
| --- | --- |
| **Notebook owner (legacy)** | `leonardo.oliveira@quintoandar.com.br` |
| **AppSheet app** | [EmployeeDataCenter-v2](https://www.appsheet.com/Template/AppDef?appName=EmployeeDataCenter-v2-1001530477&utm_source=share_app_link) |
| **Sheets folder** | [Drive folder with updated workbooks](https://drive.google.com/drive/folders/1pnoLBmwyIxkR2Ta4NQ73PKGOQtm6hVtp) |
