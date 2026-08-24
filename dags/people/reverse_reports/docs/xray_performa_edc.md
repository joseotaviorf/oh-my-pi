# `xray_performa_edc` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.xray_performa_edc` |
| **Business owner** | People Insights |
| **Technical owner** | Enterprise Engineering and People Insights |
| **Domain** | People |
| **One-line summary** | Performa calibration history joined to current org context for X-Ray AppSheet. |
| **Business purpose** | Feeds Performa cycles into X-Ray / Employee Data Center. Migrated from Daily Pipeline notebook `xray_update` ([DBP-1447](https://quintoandar.atlassian.net/browse/DBP-1447)). |
| **Business consumer** | People (company-wide via AppSheet). |
| **Delivery channel** | Google Sheets tab **base_performa_edc** in workbook [https://docs.google.com/spreadsheets/d/1Ka3EGuF-DSHrHFNQYH3Mh9G9GwogRf4lEsDO1sLjExs/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1Ka3EGuF-DSHrHFNQYH3Mh9G9GwogRf4lEsDO1sLjExs/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Org context (including `banda`) comes from the same-day `reverse_reports.xray_general_info` partition. `banda` sits after `team` so the Performa EDC tab matches the other X-Ray sibling exports. |


## Notebook usage context (X-Ray / Employee Data Center)

Former Daily Pipeline notebook `xray_update` feeds the company-wide **AppSheet X-Ray / Employee Data Center** (current and historical employee data).

| Field | Value |
| --- | --- |
| **Notebook owner (legacy)** | `leonardo.oliveira@quintoandar.com.br` |
| **AppSheet app** | [EmployeeDataCenter-v2](https://www.appsheet.com/Template/AppDef?appName=EmployeeDataCenter-v2-1001530477&utm_source=share_app_link) |
| **Sheets folder** | [Drive folder with updated workbooks](https://drive.google.com/drive/folders/1pnoLBmwyIxkR2Ta4NQ73PKGOQtm6hVtp) |
