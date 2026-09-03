# Workforce Allocation

## Ownership

**Data Owner:**
- isabella.araujo@quintoandar.com.br

**Data Steward:**
- isabella.araujo@quintoandar.com.br

---

## Overview

- **Objective:** Describe how the workforce is allocated across organizational groups, tags, and teams over time.
- **Asset status / lifecycle:** Historical allocation states are reconstructed from source snapshots and deltas and published as a daily-reference-date DW fact.
- **Typical actions / events:** An allocation can be created, updated, deactivated, or removed from a group or tag.
- **Common metrics:** Allocated FTE, active allocations, FTE by group or tag, and historical team allocation.
- **Source systems:** Workforce allocation exports ingested through the People data platform.
- **Related entities:** For employee identity and organizational context, see [`employee_details.md`](employee_details.md) and [`people_public.md`](people_public.md).

**Access:** `dw_workforce_allocation` is a restricted People dataset. It contains employee and organizational allocation identifiers and must be used only by authorized People consumers. The fact does not contain employee names, email addresses, or contact data.

**Grain:** One row per allocation, employee, group, and tag validity interval. Intervals are split when the allocation state or its equal-share FTE changes; both active and inactive historical states are retained. Source-generated sample records are excluded.

## Related Metric Entities

No official metric entity is currently defined for this domain.

---

## Glossary and Synonyms

| Term | Meaning | Notes |
|------|---------|-------|
| **Workforce allocation** | Assignment of an employee's capacity to an organizational group and tag | Use `fact_workforce_allocations` |
| **Alocação de pessoas** | Workforce allocation | Portuguese business term |
| **Alocação em times** | Allocation across organizational teams | Use `group_name`, `tag_name`, or `team` |
| **Allocated FTE** | Fraction of one employee allocated to a tag | Use `allocation_fte` |
| **Reference date / data de referência** | Date the allocation state is read at | Filter `<date> BETWEEN dt_valid_from AND dt_valid_to` |
| **Allocation group / grupo** | Higher-level allocation grouping | Use `id_group` and `group_name` |
| **Allocation tag / tag** | Tag within an allocation group | Use `id_tag` and `tag_name` |

---

## Tables

| You need… | Schema / table |
|-----------|----------------|
| Historical workforce allocation by employee, group, tag, and point in time | `dw_workforce_allocation.fact_workforce_allocations` — **neither** (workforce allocation) |
| Active allocated FTE by group or tag | `dw_workforce_allocation.fact_workforce_allocations` — **neither** (workforce allocation); filter `is_active = TRUE` |
| Organizational team attributes for an employee | `dw_workforce_allocation.fact_workforce_allocations` — **neither** (workforce allocation); use `chapter`, `vertical`, and `team` |
| Employee identity or broader workforce history | `dw_employee_details.fact_assignment_snapshots` — **neither** (workforce history); see [`employee_details.md`](employee_details.md) |

---

## Key Metrics

Use this entity for exploratory allocation metrics. No official metric entity overrides these definitions.

- **Allocated FTE:** `SUM(allocation_fte)` grouped by the requested allocation dimensions.
- **Active allocation count:** `COUNT(DISTINCT id_allocation)` where `is_active = TRUE`.
- **Active allocated employees:** `COUNT(DISTINCT person_number)` where `is_active = TRUE`.
- **Historical allocation state:** Filter `<date> BETWEEN dt_valid_from AND dt_valid_to`; do not use only the latest load timestamp.

## Relationships with Other Entities

- **Workforce Allocation → Employee Details:** `person_number` identifies the employee business key; use `sk_employee` as the preferred DW join key when compatible.
- **Workforce Allocation → People Public:** `person_number` can be used to connect allocation records to the public active-workforce model when the consumer has access.
- **Allocation history:** the table is SCD2; `dt_valid_from` and `dt_valid_to` bound each state, and `is_current` marks the state in force.

## Dos and Don'ts

**Do:**

- Filter `<date> BETWEEN dt_valid_from AND dt_valid_to` for point-in-time analysis, and `is_current` for the current state.
- Filter `is_active = TRUE` when calculating current allocated FTE or active allocation counts.
- Aggregate `allocation_fte` by `group_name`, `tag_name`, `chapter`, `vertical`, or `team`.
- Treat `sk_employee = -1` as an unresolved employee mapping and report it as a data-quality condition.

**Don't:**

- Count rows as FTE; use `allocation_fte`.
- Assume every employee has one allocation or one tag.
- Mix active and inactive rows when reporting current allocation.
- Join on names or propagate employee PII from restricted People dimensions.
- Infer a current state from `ts_load`; use `is_current` and `is_active`.
- Count rows as allocations: one allocation spans several rows when its FTE share changed. Use `COUNT(DISTINCT id_allocation)`.

## Golden Queries

This query calculates active allocated FTE by workforce group for a selected reference date.

```sql
SELECT
    group_name,
    SUM(allocation_fte) AS allocated_fte
FROM dw_workforce_allocation.fact_workforce_allocations
WHERE DATE '2026-08-28' BETWEEN dt_valid_from AND dt_valid_to
    AND is_active = TRUE
GROUP BY group_name
ORDER BY allocated_fte DESC, group_name
```

## DataHub catalog

- **Data Product:** Published from this Markdown by the repository DataHub metadata workflow.
- **Dataset:** `dw_workforce_allocation.fact_workforce_allocations`
