# `leiturinha_holder_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.leiturinha_holder_roster` |
| **Business owner** | Benefits |
| **Technical owner** | People Data |
| **Domain** | People |
| **One-line summary** | Active BR plan holders for Leiturinha benefit with CNPJ mapping. |
| **Business purpose** | Benefits roster of active Brazil employees (SP, SC, MG legal entities) with contact and address data for the Leiturinha benefit program. Migrated from Daily Pipeline `reports_dw.py` view `leiturinha_titular`. |
| **Business consumer** | Benefits |
| **Operational source of truth** | `metric_people.employee_snapshots` and `dw_organization.dim_business_unit`. |
| **Delivery channel** | Google Sheets tab **leiturinha_titular**: https://docs.google.com/spreadsheets/d/1QgICpSG4yJa1-zyvnSyTi0S8GPHf6Xg0hg0rgzg5v3Q |
| **Contract notes** | Legacy Portuguese column names preserved. Active employees only (`is_active = TRUE`). Current primary snapshot: `is_current = TRUE` + `is_primary_assignment_for_snapshot = TRUE`. Filter BUs on `consolidated_business_unit_name` (SP, SC, MG — includes Deel under QuintoAndar SP). CNPJ from `dim_business_unit.cnpj`. **Tier-1 validated 2026-06-25:** 2,598 = 2,598 vs legacy `dw_employee.fact_employees`; core columns (`empresa`, `nome`, `cnpj`, `email`) 0 diffs. **Tier-2 (TRIM on `residencia_*`):** 15 symmetric diffs (was 254 without TRIM — legacy whitespace). Upstream address fix merged in [#25191](https://github.com/quintoandar/bi-etl-ejuice/pull/25191) ([DBP-1550](https://quintoandar.atlassian.net/browse/DBP-1550)). Residual diffs: legacy `dim_employee_contact.address` vs `employee_snapshots.address_street` null mapping — Benefits sign-off. |
