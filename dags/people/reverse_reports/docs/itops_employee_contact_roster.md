# `itops_employee_contact_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.itops_employee_contact_roster` |
| **Business owner** | ITOps |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Employee roster with org hierarchy and contact/address PII for ITOps (PIN_ITOps). |
| **Business purpose** | Base for ITOps with employee identity, org structure, employment status, manager, role, and residential contact data (address, phone, CPF). |
| **Business consumer** | ITOps |
| **Operational source of truth** | `metric_people.employee_snapshots`. |
| **Delivery channel** | Google Sheets tab **(Grupo) PIN_ITOps** in workbook `15cDUEPUHT9FWtWMX5hvgJjRMCIP288FYj1Kvl3hYuwg`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy Portuguese column names preserved. Contains PII — restricted sheet ACLs. One row per person (`is_current_for_employee = TRUE`): for employees with multiple assignments, only the last valid (active-first, then most recent) assignment is sent. |
