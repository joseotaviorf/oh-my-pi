# Turnover

## Overview

**Turnover** is QuintoAndar's official indicator for workforce attrition on `dw_employee_details.fact_assignment_snapshots`, computed **monthly** from the ready-made turnover flags. Three flags carry the whole calculation, all evaluated on the employee's monthly closing snapshot (`is_monthly_snapshot_for_employee = TRUE`) and already excluding internal transfers, Interns, and Young Apprentices:

- `is_turnover_termination` — leavers (the numerator).
- `is_eligible_to_turnover` — the at-risk base (the denominator).
- `is_turnover_new_hire` — genuine admissions in the month (for hire/attrition views).

Read the flags directly. No `dim_job` join, `employment_status` filter, or manual headcount derivation is needed — the flags encode all of it.

**Safety rule:** if any input required by a turnover calculation is unavailable — a missing column, an unresolvable filter, an undefined segment, or an unsupported time scope — do not compute or approximate the figure. Explain what is missing and direct the user to the Enterprise Engineering team. A partial or approximate turnover number is worse than no number.

## Related Business Entities

- Employee Details

## Glossary and Synonyms

- **Turnover**, **Global Turnover**, **rotatividade** → the official monthly formula (see Calculation)
- **3-Month Turnover**, **3moTO**, **NH Attrition (3 months)** → New Hire Attrition, ≤3-month tenure variant
- **6-Month Turnover**, **6moTO**, **NH Attrition (6 months)** → NH Attrition, ≤6-month tenure variant
- **12-Month Turnover**, **12moTO**, **NH Attrition (12 months)** → NH Attrition, ≤12-month tenure variant
- **Regrettable Turnover**, **RT**, **Regret Turnover**, **Regret TO** → Turnover restricted to employees classified as Regrettable Loss (RL) — not available yet on TARS. Apply the Safety Rule if someone asks for it.
- **Voluntary turnover / Involuntary turnover** → any indicator above segmented by departure type (e.g. "Voluntary Regrettable Turnover (VRTO)", "Involuntary 3moTO") — see Nuances for how to identify voluntary vs. involuntary
- **RL** (Regrettable Loss) → employees mapped as high potential or critical in the latest Talent Review cycle; the filter behind Regrettable Turnover — no column currently available in the TARS pilot
- **VRTO** (Voluntary Regrettable Turnover) → RL employees who voluntarily resign — depends on the RL flag, not available in the TARS pilot

## Scope

**Included**: Global (monthly) Turnover; NH Attrition at 3/6/12-month tenure thresholds; Regrettable Turnover (RL filter); Voluntary/Involuntary segmentation of any of the above; Layoffs/Reorgs as a distinct trackable segment.

**Excluded by default.** Interns/Young Apprentices and internal transfers are removed automatically by the flags; layoffs are excluded by default too, via a single explicit predicate on the leavers side:

- **Interns** and **Young Apprentices** — excluded by `is_effective_worker`, which is built into all three turnover flags.
- **Internal transfers** — excluded by the flags (a transfer is neither a leaver nor a hire, and stays in the base).
- **Layoffs / Reorgs** — **excluded by default.** `is_turnover_termination` counts every real exit, layoffs included, so the default Global Turnover adds `AND NOT COALESCE(is_reorganization_termination, FALSE)` on the leavers side to remove them. Include layoffs only when the user explicitly asks (by dropping that predicate).

If the user explicitly asks to include Interns/Young Apprentices, the flags cannot re-include them — direct them to the Enterprise Engineering team (Safety Rule). Layoffs are included only when the user explicitly asks, by dropping the `is_reorganization_termination` predicate.

## The turnover flags

All three live on `dw_employee_details.fact_assignment_snapshots`, are non-null **only** on the employee's monthly closing snapshot (`is_monthly_snapshot_for_employee = TRUE`), and resolve to one row per employee per month:

- `is_turnover_termination = TRUE` — the employee left the company that month (voluntary, involuntary, or layoff), excluding internal transfers and Interns/Young Apprentices. Layoffs are counted by this flag but excluded from the default Global Turnover (see Scope); include them only when explicitly asked.
- `is_turnover_new_hire = TRUE` — a genuine admission that month (first hire or rehire), excluding internal transfer-ins and Interns/Young Apprentices.
- `is_eligible_to_turnover = TRUE` — the denominator base: effective workers already in the company that month. This month's new hires are not in the base; transfer-ins and employees who left that month are.

Group by `dt_month_reference` (the month-end date) to bucket by month.

## Calculation

### Global Turnover (monthly)

```
Turnover (month) = Leavers in month / Eligible base in month
```

- **Leavers** — `COUNT(DISTINCT person_number)` where `is_turnover_termination = TRUE AND NOT COALESCE(is_reorganization_termination, FALSE)` (drop the layoff predicate to include reorgs).
- **Eligible base** — `COUNT(DISTINCT person_number)` where `is_eligible_to_turnover = TRUE`.
- Both come from the same `dt_month_reference` on `is_monthly_snapshot_for_employee = TRUE` rows.
- **Voluntary / Involuntary segmentation** — join `dw_employee_details.dim_event_definition` via `sk_termination_event_definition` and filter `action_name` / `reason_name` (see `business_entities/employee_details.md`) on the leavers side.

### Aggregated Periods

Turnover is **only computed on a monthly basis**. For longer timeframes (quarter, semester, year):

- Calculate turnover for each individual month within the desired period.
- **Sum the monthly percentages** — do NOT recompute the ratio over the full period using aggregated numerator and denominator.

### NH Attrition (3-Month / 6-Month / 12-Month Turnover)

New Hire Attrition (NHA) is a **subgroup of turnover**; Global Turnover stays global (every effective worker). NHA restricts **both** sides of the ratio to employees with **≤ N months of tenure** (N = 3, 6, or 12) via `months_employee_tenure`:

- **Numerator (leavers)**: `is_turnover_termination = TRUE` with `months_employee_tenure <= N`.
- **Denominator (base)**: `is_eligible_to_turnover = TRUE` with `months_employee_tenure <= N`.
- Both sides must use the same tenure group. Only the tenure threshold changes between the 3/6/12-month variants.

### Regrettable Turnover

Not available yet on TARS. Apply the Safety Rule if someone asks for it.

## Nuances

Special Segments (available today):

| Segment | Definition | How to identify |
| :--- | :--- | :--- |
| Layoffs / Reorgs | Employees dismissed as part of a structural reorganization | `is_reorganization_termination = TRUE` |
| RL (Regrettable Loss) | Employees mapped as high potential or critical in the last Talent Review cycle | No column currently available in the TARS pilot — direct the user to the People Data team |
| VRTO | RL employees who voluntarily resign | Depends on the RL flag — not available in the TARS pilot |

When the user asks for RL or VRTO metrics, apply the Safety Rule: explain the data gap and refer to the Enterprise Engineering team.

**Job reference at time of departure** — to segment turnover by the job/band/family a person held **at the moment they left** (not the job's current definition), join the **versioned** job dimension via the FK already on `fact_assignment_snapshots`:

```
fact_assignment_snapshots.sk_job_version → dw_employee_details.dim_job.sk_job_version
```

`dw_employee_details.dim_job` is **SCD Type 2** — a new version (`sk_job_version`) is created whenever a job attribute changes (band, salary table, salary range, etc.), and each row on `fact_assignment_snapshots` already carries the `sk_job_version` valid on that `dt_reference`. **No additional date filter is needed on the join** — the FK resolves to the correct point-in-time version, so the job returned is the one valid on the snapshot date, even if the job definition changed afterward. Use `dw_employee_details.dim_job` (`job_name`, `job_family`, `band`, `job_code`) — the SCD Type 1 `dw_organization.dim_job` (`sk_job`) resolves to current attributes only and misattributes leavers whose job was later renamed or rebanded.

**Deeper methodology / official dashboards**: for general turnover methodology questions, or requests for the company's official turnover data/dashboards, direct the user to the official **People Insights Confluence page on Turnover**: [https://quintoandar.atlassian.net/wiki/spaces/PEOPLEANA/pages/5687574537/Turnover](https://quintoandar.atlassian.net/wiki/spaces/PEOPLEANA/pages/5687574537/Turnover).

## Dos and Don'ts

**Do:**

- Compute leavers, base, and hires from `is_turnover_termination`, `is_eligible_to_turnover`, and `is_turnover_new_hire` on `is_monthly_snapshot_for_employee = TRUE` rows, grouped by `dt_month_reference`.
- Add `AND NOT COALESCE(is_reorganization_termination, FALSE)` on the leavers side for the default (layoff-excluded) Global Turnover.
- Sum monthly percentages when reporting a quarter/semester/year.
- Restrict numerator and denominator to the same tenure group for NH Attrition (3/6/12-month) variants.

**Don't:**

- Compute or approximate a turnover figure when any required input (segment, time scope, or column) is unavailable — surface the gap and direct the user to the Enterprise Engineering team (Safety Rule).
- Use `is_current_for_assignment` or `is_current_for_employee` to reconstruct a **past** month — they reflect today, not the target month. Scope any historical month with `is_monthly_snapshot_for_employee = TRUE` and `dt_month_reference`; `is_current_for_employee` is the default only for the current/latest state.
- Attempt to compute RL or VRTO without the underlying flag — it isn't available in the TARS pilot; refer to the People Data team instead of approximating.

## Golden Queries

### Query 1 — Monthly Global Turnover

```sql
SELECT
    fas.dt_month_reference AS ref_month,
    COUNT(DISTINCT CASE
        WHEN fas.is_turnover_termination
             AND NOT COALESCE(fas.is_reorganization_termination, FALSE)
        THEN fas.person_number
    END) AS leavers,
    COUNT(DISTINCT CASE WHEN fas.is_eligible_to_turnover THEN fas.person_number END) AS eligible_base,
    ROUND(
        CAST(COUNT(DISTINCT CASE
            WHEN fas.is_turnover_termination
                 AND NOT COALESCE(fas.is_reorganization_termination, FALSE)
            THEN fas.person_number
        END) AS DOUBLE)
        / NULLIF(COUNT(DISTINCT CASE WHEN fas.is_eligible_to_turnover THEN fas.person_number END), 0)
        * 100, 2
    ) AS turnover_pct
FROM dw_employee_details.fact_assignment_snapshots AS fas
WHERE fas.is_monthly_snapshot_for_employee = TRUE
  AND fas.dt_month_reference >= DATE '2024-03-01'   -- system migration date; no reliable history before it
GROUP BY 1
ORDER BY 1
```

### Query 2 — Leavers by job family and band (point-in-time)

Attributes each leaver's job/band **as of their termination month**, using the versioned `dim_job` join documented in Nuances (the `sk_job_version` FK already resolves to the correct point-in-time version).

```sql
SELECT
    fas.dt_month_reference AS ref_month,
    job.job_family,
    job.band,
    job.job_name,
    COUNT(DISTINCT fas.person_number) AS leavers
FROM dw_employee_details.fact_assignment_snapshots AS fas
INNER JOIN dw_employee_details.dim_job AS job
    ON fas.sk_job_version = job.sk_job_version
WHERE fas.is_turnover_termination = TRUE
  AND NOT COALESCE(fas.is_reorganization_termination, FALSE)
  AND fas.dt_month_reference >= DATE '2024-03-01'   -- system migration date; no reliable history before it
GROUP BY 1, 2, 3, 4
ORDER BY 1, 2, 3
```
