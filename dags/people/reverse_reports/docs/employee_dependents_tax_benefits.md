# `employee_dependents_tax_benefits` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.employee_dependents_tax_benefits` |
| **Business owner** | Personal Department (DP) — IRRF and family allowance (salário-família) |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Daily one-row-per-employee-dependent export of IRRF and family-allowance dependents. |
| **Business purpose** | Supply DP with current PIN dependents for Brazilian income-tax (IRRF) and family-allowance processing. |
| **Business consumer** | Personal Department (DP) |
| **Operational source of truth** | `datalake_pin_core_clean.contact_relationship` joined to `metric_people.employee_snapshots` on `sk_employee`, dependent `person_name` / `national_identifiers` / `person`, and `foundation_lookup_value` (`QA_CONTATO_EMERGENCIA` for relationship degree, `QA_DEPENDENTE_IRRF`, `QA_SALARIO_FAMILIA`). |
| **Delivery channel** | Google Sheets tab **dependentes** in workbook `19wejhwGjx6YCFg3At5Jfnw-90TpMOkyTr5Cl3bhsIzw`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Snake_case headers via `column_mapping_mode: name`. Grain: one current relationship per employee and dependent. Population: relationships whose IRRF or family-allowance type resolves to a dependent value in the PTB lookup (disabled codes included, "not a dependent" codes excluded), for active employees and employees terminated in the 12 months before `{load_start_date}`. |
| **PII / LGPD** | Exports employee and dependent name/CPF, employee email, dependent birth date (`personal`). Precedent: `dp_employee_master` and related DP reverse reports. Necessity: statutory tax and family-allowance administration (DBP-2083). |
