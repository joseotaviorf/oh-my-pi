# Vacation balances Google Sheet export (`reverse_reports`)

People lake → Google Sheets export with the vacation-balance panorama of active employees, for the People/HR Férias e Afastamentos process.

---

## `vacation_balances`

| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.vacation_balances` |
| **Business owner** | Isabela Jorge da Silva (isabela.silva@quintoandar.com.br) |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | One row per active employee × vacation acquisitive period exported to Google Sheets tab `Painel Geral` for the People/HR vacation-management process. |
| **Business purpose** | Provides the general panorama of vacation balances (saldos de férias) for active employees of the MLSP and GRPQA (Brazilian QuintoAndar) companies. Replaces the manual Oracle BI report "Férias a Vencer" with an automated daily export. |
| **Business consumer** | People/HR team (Férias e Afastamentos). |
| **Operational source of truth** | DW 2.0: `dw_time.fact_vacation_balances` for balances; `dw_employee_details`, `dw_organization`, `dw_compensation` for employee, organisation and manager attributes. No external spreadsheet owner — all data sourced from the lake. |
| **Delivery channel** | Google Sheets tab **Painel Geral** in workbook `1Y_EvoW6IG3uHpfvDp2Ur8ikwJk8qNtX978iNK_XVzFs`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Company scope** | `business_unit_name IN ('MLSP','QuintoAndar SP','QuintoAndar MG','QuintoAndar SC')`. GRPQA (legal employer GRPQA LTDA) is approximated by the Brazilian QuintoAndar business units; there is no clean DW join to the legal-employer entity today. |
| **Contract notes** | CPF (requested in the original ticket) is intentionally **excluded** pending privacy sign-off and a restricted-ACL plan for the sheet. Active filter: `dt_terminated IS NULL OR dt_terminated >= CURRENT_DATE()`. Booleans render as Yes/No and dates as `YYYY-MM-DD` (see `load_to_gsheet.py`). |

### Column inventory

| Column (sheet / Delta name) | Description | Lake source |
| --- | --- | --- |
| business_unit | Company / business unit (Filial), raw `business_unit_name`. | `dw_organization.dim_business_unit.business_unit_name` |
| person_number | Employee registration number (Matrícula). | `dw_time.fact_vacation_balances.person_number` |
| assignment_number | Work contract / assignment code (Matrícula externa). | `dw_time.fact_vacation_balances.assignment_number` |
| employee_name | Employee full name. | `dw_employee_details.dim_employee.name` |
| work_email | Employee work email. | `dw_employee_details.dim_employee.work_email` |
| job_name | Job title (Função). | `dw_compensation.dim_job.job_name` |
| cost_center_code | Cost centre code (Centro de Custo). | `dw_organization.dim_cost_center.cost_center_code` |
| cost_center_name | Cost centre name. | `dw_organization.dim_cost_center.cost_center_name` |
| dt_hired | Admission date of the current work relationship (Data de Admissão). | `dw_employee_details.fact_assignment_snapshots.dt_hired` |
| manager_name | Direct manager full name (Nome do Gestor). | `dw_employee_details.dim_employee.name` via `dim_management_hierarchy.manager_assignment_number` |
| manager_email | Direct manager work email (E-mail do Gestor). | `dw_employee_details.dim_employee.work_email` via `dim_management_hierarchy.manager_assignment_number` |
| acquisitive_period_start | Start of the vacation acquisitive period (Período Aquisitivo). | `dw_time.fact_vacation_balances.dt_vacation_period_started` |
| acquisitive_period_end | End of the vacation acquisitive period (Período Aquisitivo). | `dw_time.fact_vacation_balances.dt_vacation_period_ended` |
| concessive_period_deadline | Concessive-period deadline (Período Concessivo), acquisitive end + 365 days. | `dw_time.fact_vacation_balances.dt_vacation_period_expiration` |
| days_balance | Remaining vacation-day balance for the period (Saldo). | `dw_time.fact_vacation_balances.days_balance` |
| vacation_status | Period status: Closed / In progress / Open / Expired (Status). | `dw_time.fact_vacation_balances.vacation_status` |
| year | Partition year (from `{load_start_date}`). Not exported to the sheet. | — |
| month | Partition month (from `{load_start_date}`). Not exported to the sheet. | — |
| day | Partition day (from `{load_start_date}`). Not exported to the sheet. | — |
