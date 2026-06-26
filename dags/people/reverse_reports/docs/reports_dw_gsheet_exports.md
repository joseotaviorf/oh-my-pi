# People reports_dw Google Sheet exports (`reverse_reports`)

People lake → Google Sheets exports migrated from the legacy Daily Pipeline **`reports_dw.py`** notebook. Parent epic: [DBP-1310](https://quintoandar.atlassian.net/browse/DBP-1310) (Exodus). Story: [DBP-1333](https://quintoandar.atlassian.net/browse/DBP-1333).

---

## Shared source pattern (`employee_snapshots`)

Employee roster exports in this batch source **`metric_people.employee_snapshots`**. Current-state filter:

```sql
es.is_current = TRUE
AND es.is_primary_assignment_for_snapshot = TRUE
```

Do not use `es.dt_month_reference = CURRENT_DATE()` — the column is month-end, not today's date.

`cost_center_mapping_pin` is the exception: it aggregates headcount per cost center from `dw_organization.dim_cost_center` and `dw_employee_details.fact_assignment_snapshots`.

`pin_current_employee_snapshot` adds `dw_*` joins for `currency_code` (`moeda`) and manager `person_number` (`gestor_person_number`).

`leiturinha_holder_roster` adds `is_active = TRUE` and filters on `consolidated_business_unit_name` (SP, SC, MG).

---

## Exports in this batch

| Table | Tab | Governance doc |
| --- | --- | --- |
| cost_center_mapping_pin | new_de_para_pin | [cost_center_mapping_pin.md](cost_center_mapping_pin.md) |
| pin_current_employee_snapshot | foto_atual_pin | [pin_current_employee_snapshot.md](pin_current_employee_snapshot.md) |
| pin_cost_center_roster | centro_de_custo_pin | [pin_cost_center_roster.md](pin_cost_center_roster.md) |
| leiturinha_holder_roster | leiturinha_titular | [leiturinha_holder_roster.md](leiturinha_holder_roster.md) |
| pin_systems_employee_roster | base_pin | [pin_systems_employee_roster.md](pin_systems_employee_roster.md) |
| pin_systems_employee_roster_shared | base_pin | [pin_systems_employee_roster_shared.md](pin_systems_employee_roster_shared.md) |
