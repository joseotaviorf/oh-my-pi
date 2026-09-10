# Workforce Allocation DW

## Purpose

`dw_workforce_allocation.fact_workforce_allocations` supports workforce allocation analysis for TARS and authorized People planning consumers.

## Grain

The table is a Slowly Changing Dimension Type 2 fact: one row per allocation per validity interval over which its FTE share is constant. Intervals of the same allocation never overlap, and the interval still in force carries `dt_valid_to = 9999-12-31` and `is_current = TRUE`. Inactive allocation states remain available for historical analysis, while application-generated sample records are excluded.

## Sources

- The Allocation Tool exports versioned snapshots and deltas. `datalake_allocation_tool_clean.allocations` is the append-only log with one row per allocation version and the single place where those envelopes are parsed.
- `datalake_people.allocation_history` turns that log into SCD2 validity intervals and resolves the canonical People employee key.
- Employee identifiers are resolved when the source employee identifier matches `person_number`. Unresolved identifiers retain `sk_employee = -1` for reconciliation.

## FTE calculation

`allocation_fte` equals `1 / N`, where `N` is the number of distinct active tags the employee holds in that group. `N` changes whenever *another* tag in the same group starts or ends, so the employee/group timeline is cut at every such boundary and each active allocation is split along those cuts. That keeps `allocation_fte` constant within a row without materializing a per-day snapshot. Inactive allocations carry an FTE of zero and keep their original interval.

The share is scoped to the group, so it is **not additive across groups**: an employee allocated to two groups contributes 1.0 FTE in each. Aggregate by group, tag, chapter or vertical; do not read a cross-group total as headcount.

## Classification hierarchy

Workforce allocations are organized in three levels:

| Level | Column | Example |
| --- | --- | --- |
| Macro group (Line) | `line_name` | For Rent |
| Team | `group_name` | Billing & Payments |
| Project | `tag_name` | IPO-readiness |

FTE is computed within the team (`id_group`): an employee with two project tags in the same team contributes `1/N` in that team.

Project tag names may repeat across teams (for example, `Mora XP`). For a project view that rolls up every team carrying the same tag, aggregate `allocation_fte` by `tag_name` and filter or group by `line_name` when needed.

## Recommended usage

- Point-in-time: `WHERE <reference date> BETWEEN dt_valid_from AND dt_valid_to`.
- Current state: `WHERE is_current`.
- Filter `is_active = TRUE` for active allocations.
- Team view: aggregate `allocation_fte` by `line_name`, `group_name`, or organizational attributes.
- Project view: aggregate `allocation_fte` by `tag_name` across teams.
- Use `sk_employee` to join the People employee dimension; investigate rows with `sk_employee = -1`.
- Do **not** count rows as allocations: one allocation spans several rows when its FTE share changed. Use `COUNT(DISTINCT id_allocation)`.

## Backfill

`allocations` is loaded incrementally over the run's load window. Seeding the history requires one backfill run with `load_start_date` set to the first raw partition; after that the daily window is enough.

## Contract

This dataset is maintained under a dedicated DW contract and People access policy. The DW fact stores identifiers and organizational allocation attributes, not employee names or contact information.
