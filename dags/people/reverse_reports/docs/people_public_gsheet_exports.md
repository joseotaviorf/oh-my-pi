# People public base Google Sheet exports (`reverse_reports`)

People lake → Google Sheets exports that provide the active-employee base for People Systems (PIN) and related processes.

---

## Exports in this programme

| Table | Governance doc |
| --- | --- |
| public_information | [Section below](#public_information) |

---

## `public_information`

| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.public_information` |
| **Business owner** | People team |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | One row per active employee (no salary band data) exported to Google Sheets tab `base - PIN` for downstream People Systems consumption. |
| **Business purpose** | Provides an up-to-date employee roster (hierarchy, organisation, location, manager chain) for People Systems. The report excludes salary band to allow broader distribution. Migrated from the Daily Pipeline `external_reports` notebook cell `base_public_no_banda` to remove the dependency on the deprecated `datalake_people_analytics_sandbox.base_completa_hierarquia` table. |
| **Business consumer** | TBD — likely People Systems for PIN / Oracle HCM ingestion (inferred from "base - PIN" tab name). |
| **Operational source of truth** | DW 2.0 (`dw_employee_details`, `dw_organization`, `dw_compensation`). No external spreadsheet owner — all data sourced from the lake. |
| **Delivery channel** | Google Sheets tab **base - PIN** in workbook `1lf1CIn8GRvHOnNm0imZ8z01w_NXtjv16zbPqD5GP8-k`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Column names are legacy Portuguese aliases preserved from the original notebook for sheet compatibility. Active filter: `dt_terminated IS NULL OR dt_terminated >= CURRENT_DATE()` (matches original sandbox logic). |

### Column inventory

| Column (sheet / Delta name) | Description | Lake source |
| --- | --- | --- |
| matricula | Employee person number (natural HR identifier). | `dw_employee_details.dim_employee.person_number` |
| empresa | Legal entity / business unit display name with standard remapping (e.g. Classifieds umbrella, Benvi México). | `dw_organization.dim_business_unit.business_unit_name` (CASE remapping) |
| nome | Employee full name, lowercased. | `dw_employee_details.dim_employee.name` |
| email | Employee work email, lowercased. | `dw_employee_details.dim_employee.work_email` |
| status | Fixed value `'ativo'`; the query already filters to active employees only. | Derived from filter on `fact_assignment_snapshots.dt_terminated` |
| gestor | Direct manager full name, lowercased. | `dw_employee_details.dim_employee.name` (joined via `dim_management_hierarchy.manager_assignment_number`) |
| cargo | Job title, lowercased. | `dw_compensation.dim_job.job_name` |
| numero_centro_de_custo | Cost centre code, lowercased. | `dw_organization.dim_cost_center.cost_center_code` |
| centro_de_custo | Formatted cost centre label: `<code> - <name_after_prefix>`, all lowercased. | `dw_organization.dim_cost_center` (cost_center_code + cost_center_name) |
| l1_cc | Cost centre L1 owner name, lowercased; NULL when not set. | `dw_organization.dim_cost_center.owner_l1_name` |
| l2_cc | Cost centre L2 owner name, lowercased; NULL when not set. | `dw_organization.dim_cost_center.owner_l2_name` |
| l3_cc | Cost centre L3 owner name, lowercased; NULL when not set. | `dw_organization.dim_cost_center.owner_l3_name` |
| vertical | CODEX vertical classification, lowercased; NULL when not set. | `dw_organization.dim_cost_center.vertical` |
| structure | CODEX structure classification, lowercased; NULL when not set. | `dw_organization.dim_cost_center.structure` |
| team | CODEX team classification, lowercased; NULL when not set. | `dw_organization.dim_cost_center.team` |
| business | CODEX business classification, lowercased; NULL when not set. | `dw_organization.dim_cost_center.business` |
| product | CODEX product classification, lowercased; NULL when not set. | `dw_organization.dim_cost_center.product` |
| brand | CODEX brand classification, lowercased; NULL when not set. | `dw_organization.dim_cost_center.brand` |
| chapter | CODEX chapter classification, lowercased; NULL when not set. | `dw_organization.dim_cost_center.chapter` |
| line | CODEX line classification, lowercased; NULL when not set. | `dw_organization.dim_cost_center.line` |
| hrbp | HRBP work email for the employee's cost centre, lowercased; NULL when not assigned. | `dw_organization.dim_cost_center.hrbp_work_email` |
| pais | Country inferred from business unit name (argentina / mexico / portugal / brasil); falls back to job country. | `dw_organization.dim_business_unit.business_unit_name` + `dw_compensation.dim_job.country` (CASE) |
| residencia_uf | Employee home state (address), lowercased. | `dw_employee_details.dim_contact.address_state` |
| residencia_cidade | Employee home city (address), lowercased. | `dw_employee_details.dim_contact.address_city` |
| l0_gestor | Hierarchy level 0 (top) manager name, lowercased; defaults to `'gabriel braga vieira'` when absent. | `dw_employee_details.dim_management_hierarchy.name_l0` |
| l1_gestor | Hierarchy level 1 manager name, lowercased. | `dw_employee_details.dim_management_hierarchy.name_l1` |
| l2_gestor | Hierarchy level 2 manager name, lowercased. | `dw_employee_details.dim_management_hierarchy.name_l2` |
| l3_gestor | Hierarchy level 3 manager name, lowercased. | `dw_employee_details.dim_management_hierarchy.name_l3` |
| l4_gestor | Hierarchy level 4 manager name, lowercased. | `dw_employee_details.dim_management_hierarchy.name_l4` |
| l5_gestor | Hierarchy level 5 manager name, lowercased. | `dw_employee_details.dim_management_hierarchy.name_l5` |
| l6_gestor | Hierarchy level 6 manager name, lowercased. | `dw_employee_details.dim_management_hierarchy.name_l6` |
| l7_gestor | Hierarchy level 7 manager name, lowercased. | `dw_employee_details.dim_management_hierarchy.name_l7` |
| l8_gestor | Hierarchy level 8 manager name, lowercased. | `dw_employee_details.dim_management_hierarchy.name_l8` |
| idade_empresa | Employee tenure in the company in full months. | `dw_employee_details.fact_assignment_snapshots.months_tenure_in_company` |
| fl_lider | 1 if the employee is a manager; 0 otherwise. | `dw_employee_details.fact_assignment_snapshots.is_manager` |
| dt_inicio | Date when the current work relationship started. | `dw_employee_details.fact_assignment_snapshots.dt_hired` |
| dt_last_update | Date when the snapshot was last loaded, in Brazil/São Paulo timezone. | `dw_employee_details.fact_assignment_snapshots.ts_load` |
| dt_inicio_person | Earliest hire date across all assignments for this person (first day at the company). | `dw_employee_details.fact_assignment_snapshots.dt_hired` (MIN per person_number) |
| year | Partition year (from `{load_start_date}`). Not exported to the sheet. | — |
| month | Partition month (from `{load_start_date}`). Not exported to the sheet. | — |
| day | Partition day (from `{load_start_date}`). Not exported to the sheet. | — |
