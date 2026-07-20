# `compliance_conflict_of_interest_employee_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.compliance_conflict_of_interest_employee_roster` |
| **Business owner** | gabriel.daud@quintoandar.com.br |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Active employees and employees terminated in the last 6 months (one row per `person_number`) for Compliance conflict-of-interest checks. |
| **Business purpose** | Base for Compliance conflict-of-interest control in supplier registration and homologation (nome, país, CPF, cargo, banda, centro de custo, data e motivo de desligamento). |
| **Business consumer** | Compliance |
| **Operational source of truth** | `metric_people.employee_snapshots`. |
| **Delivery channel** | Google Sheets tab **`_base`** in workbook `1D84RkgMoQ8zSG3Nj-MutCqpMqR1bdWM3x7_fz8CoCgY`. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Portuguese column aliases per DBP-1760. Grain: one row per `person_number` (prefer active over terminated). Population: `status = active` or terminated with `dt_terminated` within the last 6 months relative to `{load_start_date}`. `dt_desligamento` / `motivo_desligamento` are null unless `status = terminated` and `dt_terminated <= {load_start_date}` (hides future departure fields on still-active employees). |
| **PII / LGPD** | Exports `nome`, `cpf`, `dt_desligamento`, `motivo_desligamento` (`personal`). Precedent: same fields already shipped in `wfa_active_employee_roster`, `dp_employee_master`, `compliance_employee_roster`, `performa_employee_base`, and related reverse reports. Necessity: conflict-of-interest checks for supplier homologation (PDA-517 / DBP-1760). |
