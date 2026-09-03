# `employee_equipment_roster` — reverse export governance

| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.employee_equipment_roster` |
| **Business owner** | Pedro Prates (pedro.prates@quintoandar.com.br) |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | QuintoAndar machine report: which notebook is linked to each employee, current and historical. |
| **Business purpose** | Machine report for Enterprise Efficiency. Answers which notebook each employee holds today and which ones they held before. |
| **Business consumer** | Enterprise Efficiency. |
| **Operational source of truth** | `dw_employee_details` (`fact_assignment_snapshots`, `dim_employee`, `dim_documentation`, `dim_contact`, `dim_management_hierarchy`) for the employee side. **Exception:** the machine side reads `datalake_plugify_clean.device_inventory` because `dw_equipment.dim_equipment` strips `tax_id` (CPF) at the DW layer. CPF is the only deterministic key to a person — without it the association rate drops from 94.5% to 93.1% and 55 allocated machines resolve to the wrong employee. |
| **Delivery channel** | Google Sheets tab **base** in workbook [https://docs.google.com/spreadsheets/d/1LeEvPtDFySpqhsMnzz8PwlQtJJ3r3cEAo618TwDszfw/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1LeEvPtDFySpqhsMnzz8PwlQtJJ3r3cEAo618TwDszfw/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | One row per hostname × association period. `is_current = TRUE` marks the machine linked to the employee on the load reference date; `dt_valid_to = 9999-12-31` on those rows. A period closes either when the hostname changes hands or when it leaves the Plugify inventory (device returned). History starts at the earliest Plugify snapshot (2026-05-19), so `dt_valid_from` on the oldest periods is a first-observed date, not the real allocation date. Only hostnames resolved to a person are exported — machines in stock and third-party holders (contractors, PJ) are absent by design. `matched_by` records which key resolved the person, in waterfall order: `tax_id`, `work_email`, `personal_email`, `corporate_email_field`, `employee_name`. Monitors never carry a hostname, so the report covers notebooks only. Around 29 rows resolve to a person who has a CPF registered in PIN but no assignment row yet (likely pending admissions): they keep the machine columns and `email`, and carry NULL in `assignment_number`, `employment_status`, and the hierarchy columns. |

### Column inventory

| Column (sheet / Delta name) | Description | Lake source |
| --- | --- | --- |
| person_number | Employee person number (natural HR identifier). | `dw_employee_details.dim_documentation.person_number` (resolved via the match waterfall) |
| assignment_number | Current assignment number of the employee. | `dw_employee_details.fact_assignment_snapshots.assignment_number` |
| employee_name | Employee display name. | `dw_employee_details.dim_employee.name` |
| email | Employee work email. | `dw_employee_details.dim_employee.work_email` |
| employment_status | Employment status on the current assignment (e.g. `Active`). | `dw_employee_details.fact_assignment_snapshots.employment_status` |
| employee_tenure_range | Tenure band of the employee (e.g. `1-2 years`). | `dw_employee_details.fact_assignment_snapshots.employee_tenure_range` |
| dt_employee_hired | Date the current work relationship started. | `dw_employee_details.fact_assignment_snapshots.dt_employee_hired` |
| dt_terminated | Termination date; NULL while the employee is active. | `dw_employee_details.fact_assignment_snapshots.dt_terminated` |
| hierarchy_level | Management level label of the employee's assignment (e.g. `L4`). | `dw_employee_details.dim_management_hierarchy.hierarchy_level` |
| hierarchy_depth | Numeric depth of the assignment in the management chain. | `dw_employee_details.dim_management_hierarchy.hierarchy_depth` |
| manager_assignment_number | Assignment number of the direct manager. | `dw_employee_details.dim_management_hierarchy.manager_assignment_number` |
| manager_name | Direct manager display name. | `dw_employee_details.dim_employee.name` (joined via `manager_assignment_number`) |
| manager_email | Direct manager work email. | `dw_employee_details.dim_employee.work_email` (joined via `manager_assignment_number`) |
| assignment_number_l1 | Assignment number of the L1 leader. | `dw_employee_details.dim_management_hierarchy.assignment_number_l1` |
| name_l1 | L1 leader display name. | `dw_employee_details.dim_management_hierarchy.name_l1` |
| email_l1 | L1 leader work email. | `dw_employee_details.dim_management_hierarchy.email_l1` |
| hostname | Machine hostname, normalised to uppercase without spaces (Plugify records it as `BRSPPM- LQXM7Q0R9W`). | `datalake_plugify_clean.device_inventory.hostname` |
| id_serial | Manufacturer serial number of the machine. | `datalake_plugify_clean.device_inventory.serial` |
| brand | Manufacturer inferred from the model string (`Apple`, `Dell`, `Lenovo`, `HP`); NULL when no pattern matches. Plugify has no brand column. | Derived from `datalake_plugify_clean.device_inventory.model` |
| model_family | Model name without the specification tail, cut at the first comma (e.g. `MacBook Pro 14`). | Derived from `datalake_plugify_clean.device_inventory.model` |
| model | Full leasing model description, with the literal apostrophes Plugify wraps it in removed. | `datalake_plugify_clean.device_inventory.model` |
| sku | Plugify catalogue SKU of the leased configuration (e.g. `CB-001230`). | `datalake_plugify_clean.device_inventory.sku` |
| processor | Processor of the machine (e.g. `Apple M3 Pro`). | `datalake_plugify_clean.device_inventory.processor` |
| memory_gb | Installed RAM in gigabytes. | `datalake_plugify_clean.device_inventory.memory_gb` |
| operating_system | Operating system reported by the machine agent. | `datalake_plugify_clean.device_inventory.operating_system` |
| operating_system_version | Operating system version reported by the machine agent. | `datalake_plugify_clean.device_inventory.operating_system_version` |
| device_owner | Legal owner of the device (`Plugify` for leased fleet). | `datalake_plugify_clean.device_inventory.device_owner` |
| tracked_by | Tracking method active on the device (e.g. `IP`, `Geolocalizado`, `Não Rastreado`). | `datalake_plugify_clean.device_inventory.tracked_by` |
| location | Physical location reported by Plugify. | `datalake_plugify_clean.device_inventory.location` |
| stock_subheading | Allocation state in Plugify (`Com Cliente` for machines with a holder). | `datalake_plugify_clean.device_inventory.stock_subheading` |
| document_country | Country of the holder document on the leasing contract (e.g. `BR`). | `datalake_plugify_clean.device_inventory.document_country` |
| contract_number | Leasing contract number covering the device. | `datalake_plugify_clean.device_inventory.contract_number` |
| term_contract_months | Leasing term length in months. | `datalake_plugify_clean.device_inventory.term_contract_months` |
| rent_price | Monthly leasing price of the device in BRL. | `datalake_plugify_clean.device_inventory.rent_price` |
| dt_contract_signed | Date the leasing contract was signed. | `datalake_plugify_clean.device_inventory.dt_contract_signed` |
| dt_contract_started | Date the leasing contract started. | `datalake_plugify_clean.device_inventory.dt_contract_started` |
| dt_contract_ended | Date the leasing contract ends. | `datalake_plugify_clean.device_inventory.dt_contract_ended` |
| dt_term_started | Date the leasing term of this device started. | `datalake_plugify_clean.device_inventory.dt_term_started` |
| dt_term_ended | Date the leasing term of this device ends. | `datalake_plugify_clean.device_inventory.dt_term_ended` |
| dt_last_contacted | Date the machine last reported to Plugify. | `datalake_plugify_clean.device_inventory.dt_last_contacted` |
| dt_last_updated | Date the Plugify record was last edited. | `datalake_plugify_clean.device_inventory.dt_last_updated` |
| cost_center_code_plugify | Cost centre code as registered in Plugify, kept for auditing against the People DW; NULL when Plugify has no value (coverage is around 22%). | `datalake_plugify_clean.device_inventory.employee_cost_center_code` |
| matched_by | Key that resolved the machine to the employee, in waterfall order: `tax_id`, `work_email`, `personal_email`, `corporate_email_field`, `employee_name`. | Derived from the match waterfall |
| count_days_observed | Number of daily Plugify snapshots in which this hostname was linked to this employee. | Derived from `datalake_plugify_clean.device_inventory` snapshots |
| dt_valid_from | First snapshot date on which this hostname was linked to this employee. | Derived from `datalake_plugify_clean.device_inventory` snapshots |
| dt_valid_to | Last snapshot date of the association; `9999-12-31` while it is current. | Derived from `datalake_plugify_clean.device_inventory` snapshots |
| is_current | `TRUE` when the association holds on the load reference date. | Derived from `datalake_plugify_clean.device_inventory` snapshots |
| year | Partition year (from `{load_start_date}`). Not exported to the sheet. | — |
| month | Partition month (from `{load_start_date}`). Not exported to the sheet. | — |
| day | Partition day (from `{load_start_date}`). Not exported to the sheet. | — |
