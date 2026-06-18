# Vacation schedules Google Sheet export (`reverse_reports`)

People lake → Google Sheets export with approved vacation (and intern recess) schedules, past and future, for the People/HR Férias e Afastamentos process.

---

## `vacation_schedules`

| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.vacation_schedules` |
| **Business owner** | Isabela Jorge da Silva (isabela.silva@quintoandar.com.br) |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | One row per approved vacation/intern-recess request exported to Google Sheets tab `Agendamentos` for the People/HR vacation-management process. |
| **Business purpose** | Provides the history and the future approved vacation schedules (agendamentos de férias aprovados) for active employees of the MLSP and GRPQA (Brazilian QuintoAndar) companies. Replaces the manual Oracle BI report "Férias e Afastamentos" with an automated daily export. |
| **Business consumer** | People/HR team (Férias e Afastamentos). |
| **Operational source of truth** | DW 2.0: `dw_time.fact_absence_requests` and `dw_time.dim_absence_type`; `dw_employee_details`, `dw_organization`, `dw_compensation` for employee, organisation and manager attributes. |
| **Delivery channel** | Google Sheets tab **Agendamentos** in workbook `1Y_EvoW6IG3uHpfvDp2Ur8ikwJk8qNtX978iNK_XVzFs`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Company scope** | `business_unit_name IN ('MLSP','QuintoAndar SP','QuintoAndar MG','QuintoAndar SC')`. GRPQA (legal employer GRPQA LTDA) is approximated by the Brazilian QuintoAndar business units; there is no clean DW join to the legal-employer entity today. |
| **Request scope** | `is_approved = TRUE AND is_withdrawn = FALSE` and absence type in `('Férias','Recesso de Estagiário')`. |
| **Contract notes** | `schedule_status` is derived from the absence window (Concluída / Em andamento / Agendada). Booleans render as Yes/No and dates as `YYYY-MM-DD` (see `load_to_gsheet.py`). |

### Column inventory

| Column (sheet / Delta name) | Description | Lake source |
| --- | --- | --- |
| business_unit | Company / business unit (Empresa), raw `business_unit_name`. | `dw_organization.dim_business_unit.business_unit_name` |
| person_number | Employee registration number (Person Number). | `dw_time.fact_absence_requests.person_number` |
| assignment_number | Work contract / assignment code (Matrícula externa). | `dw_time.fact_absence_requests.assignment_number` |
| employee_name | Employee full name (Nome do Colaborador). | `dw_employee_details.dim_employee.name` |
| work_email | Employee work email (E-mail do Colaborador). | `dw_employee_details.dim_employee.work_email` |
| job_name | Job title (Cargo). | `dw_compensation.dim_job.job_name` |
| absence_type | Absence category (Tipo de Ausência): Férias or Recesso de Estagiário. | `dw_time.dim_absence_type.absence_type` |
| dt_absence_started | Vacation start date (Data de Início). | `dw_time.fact_absence_requests.dt_absence_started` |
| dt_absence_ended | Vacation end date (Data de Fim). | `dw_time.fact_absence_requests.dt_absence_ended` |
| days_requested | Number of vacation days requested (Duração). | `dw_time.fact_absence_requests.days_requested` |
| days_cash_out_requested | Vacation cash-out days requested (Abono pecuniário). | `dw_time.fact_absence_requests.days_cash_out_requested` |
| is_13th_salary_advance | Whether the 13th-salary advance was requested with the vacation (Adiantamento 13º); Yes/No. | `dw_time.fact_absence_requests.is_13th_salary_advance` |
| acquisitive_period_start | Start of the vacation acquisitive period (Período Aquisitivo). | `dw_time.fact_absence_requests.dt_acquisitive_period_started` |
| acquisitive_period_end | End of the vacation acquisitive period (Período Aquisitivo). | `dw_time.fact_absence_requests.dt_acquisitive_period_ended` |
| schedule_status | Derived window status (Status): Concluída (past), Em andamento (ongoing), Agendada (future). | Derived from `dt_absence_started` / `dt_absence_ended` |
| manager_name | Direct manager full name (Nome do Gestor). | `dw_employee_details.dim_employee.name` via `dim_management_hierarchy.manager_assignment_number` |
| manager_email | Direct manager work email (E-mail do Gestor). | `dw_employee_details.dim_employee.work_email` via `dim_management_hierarchy.manager_assignment_number` |
| year | Partition year (from `{load_start_date}`). Not exported to the sheet. | — |
| month | Partition month (from `{load_start_date}`). Not exported to the sheet. | — |
| day | Partition day (from `{load_start_date}`). Not exported to the sheet. | — |
