# `license_to_hire_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.license_to_hire_roster` |
| **Business owner** | TA / People |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Eligibility groups for License to Hire onboarding program. |
| **Business purpose** | Employee roster segmented by eligibility groups for the License to Hire onboarding program. |
| **Business consumer** | Learning |
| **Operational source of truth** | `metric_people.employee_snapshots` (+ `dw_*` joins where applicable). |
| **Delivery channel** | Google Sheets tab **license_to_hire_list** in workbook https://docs.google.com/spreadsheets/d/1UgZVV5FDuFTvmJ-Pc3ejzCTcyr94g8w4M29nuTDjy8s. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Portuguese column names preserved. |
