# `appsheet_vacation_portugal` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.appsheet_vacation_portugal` |
| **Business owner** | leonardo.oliveira@quintoandar.com.br |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Full employee roster exported daily to Google Sheets for the Portugal vacation management AppSheet app (VacationManagement-PT). |
| **Business purpose** | Provides all employees and their manager chains so the AppSheet app can route vacation requests for Portugal employees. Vacation management for PT does not happen in PIN, so the app consumes this sheet directly via AppSheet's native connector. All entities are included because managers of PT employees may belong to other business units. |
| **Business consumer** | People Operations Portugal team via AppSheet app [VacationManagement-PT](https://www.appsheet.com/template/AppDef?appName=VacationManagement-PT-1001530477&appId=434e0fb4-758a-440f-82f0-342ac008f392). |
| **Operational source of truth** | `dw_employee_details.fact_assignment_snapshots`, `dw_employee_details.dim_employee`, `dw_employee_details.dim_management_hierarchy`, `dw_organization.dim_business_unit`. |
| **Delivery channel** | Google Sheets tab **import_completa** in workbook [https://docs.google.com/spreadsheets/d/1rGC0c4Y_pbvq_M2OL0-78KgkMCkFAEhg8ul11b4gNDM/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1rGC0c4Y_pbvq_M2OL0-78KgkMCkFAEhg8ul11b4gNDM/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Grain: one row per employee (primary assignment, current snapshot). Includes active (`status = 'ativo'`) and terminated (`status = 'desligado'`) employees. `salario` column is intentionally empty — preserved from legacy contract. Legacy sheet headers preserved. |
