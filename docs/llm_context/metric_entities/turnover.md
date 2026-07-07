# Turnover

## Overview

**Turnover** is QuintoAndar's official indicator for workforce attrition on `dw_employee_details.fact_assignment_snapshots`, computed **monthly** as leavers over average monthly headcount. The official calculation differs from a naive full-population percentage in three ways: (1) headcount for both ends of the month must come from explicit monthly snapshots — never `is_current`, which reflects today, not the target month; (2) new hires within their first 3/6/12 months are excluded from the main indicator and tracked separately as **NH Attrition**; (3) **Regrettable Turnover** applies a "Regrettable Loss" (RL) filter symmetrically to both numerator and denominator.

**Safety rule:** if any input required by a turnover calculation is unavailable — a missing column, an unresolvable filter, an undefined segment, or an unsupported time scope — do not compute or approximate the figure. Explain what is missing and direct the user to the Enterprise Engineering team. A partial or approximate turnover number is worse than no number.

## Related Business Entities

- Employee Details

## Glossary and Synonyms

- **Turnover**, **Global Turnover**, **rotatividade** → the official monthly formula (see Calculation)
- **3-Month Turnover**, **3moTO**, **NH Attrition (3 months)** → New Hire Attrition, ≤3-month tenure variant
- **6-Month Turnover**, **6moTO**, **NH Attrition (6 months)** → NH Attrition, ≤6-month tenure variant
- **12-Month Turnover**, **12moTO**, **NH Attrition (12 months)** → NH Attrition, ≤12-month tenure variant
- **Regrettable Turnover**, **RT**, **Regret Turnover**, **Regret TO** → Turnover restricted to employees classified as Regrettable Loss (RL) - Not available yet on TARS. Apply the Safety Rule if someone asks for it.
- **Voluntary turnover / Involuntary turnover** → any indicator above segmented by departure type (e.g. "Voluntary Regrettable Turnover (VRTO)", "Involuntary 3moTO") — see Nuances for how to identify voluntary vs. involuntary
- **RL** (Regrettable Loss) → employees mapped as high potential or critical in the latest Talent Review cycle; the filter behind Regrettable Turnover — no column currently available in the TARS pilot
- **VRTO** (Voluntary Regrettable Turnover) → RL employees who voluntarily resign — depends on the RL flag, not available in the TARS pilot

## Scope

**Included**: Global (monthly) Turnover; NH Attrition at 3/6/12-month tenure thresholds; Regrettable Turnover (RL filter); Voluntary/Involuntary segmentation of any of the above; Layoffs/Reorgs as a distinct trackable segment.

**Excluded (by default from all official calculations)**:

- **Interns** (`employee_type = 'INTERN'` or equivalent label in `dim_event_definition`)
- **Young Apprentices** (`employee_type = 'APPRENTICE'` or equivalent)
- **Layoffs** — terminations where `is_reorganization_termination = TRUE`

If the user explicitly asks to include these groups, note that the result will deviate from the official figure.

## Calculation

### Global Turnover (monthly)

```
Turnover (month) = Leavers in month / Average Monthly Headcount
Average Monthly Headcount = (Active at beginning of month + Active at end of month) / 2
```

- **Active at end of month**: a snapshot with `is_monthly_snapshot = TRUE` and `dt_reference` at the last day of the target month — never `is_current`.
- **Active at beginning of month**: `Active at End of Month + Terminations During the Month − New Hires During the Month`.
  - **Terminations During the Month**: employees where `is_terminated = TRUE` and `dt_terminated` falls within the target month.
  - **New Hires During the Month**: employees where `dt_hired` falls within the target month.
- For every side of the ratio, count `COUNT(DISTINCT person_number)` where `is_active = TRUE` and `is_primary_assignment_for_snapshot = TRUE` — without the primary-assignment filter, employees with multiple assignment rows on the same `dt_reference` inflate the count.
- **Leavers** and **Average Monthly Headcount** must always reference the **same target month**.
- Count leavers as employees where `is_terminated = TRUE` and `dt_terminated` falls within the target month.
- **Voluntary / Involuntary segmentation**: apply the Voluntary/Involuntary termination filters already defined in `business_entities/employee_details.md`'s Glossary (via `dim_event_definition.action_name` / `reason_name`) to the leavers side.

### Aggregated Periods

Turnover is **only computed on a monthly basis**. For longer timeframes (quarter, semester, year):

- Calculate turnover for each individual month within the desired period.
- **Sum the monthly percentages** — do NOT recompute the ratio over the full period using aggregated numerator and denominator.

### NH Attrition (3-Month / 6-Month / 12-Month Turnover)

Employees with **≤ N months of tenure** (N = 3, 6, or 12) at the moment the indicator is built are **excluded from Global Turnover** and tracked separately:

- **Numerator (leavers)**: terminated employees whose `months_tenure_in_company ≤ N` at termination date.
- **Denominator (reference base)**: employees (active or terminated) with `months_tenure_in_company ≤ N` at the snapshot date used for the calculation.
- Both sides must be restricted to the same tenure group — do not mix `< N`-month employees in the denominator with all-tenure leavers in the numerator.
- Only the tenure threshold changes between the 3/6/12-month variants.

### Regrettable Turnover
- Not available yet on TARS. Apply the Safety Rule if someone asks for it.
  
### Canonical Filter

Apply on `dw_employee_details.fact_assignment_snapshots`:

```sql
is_active = TRUE
AND is_primary_assignment_for_snapshot = TRUE
AND is_monthly_snapshot = TRUE   -- headcount sides only; not applied to the leavers side
```

**Warning**: substituting `is_current` for an explicit `dt_reference` on either side of Average Monthly Headcount silently swaps the target month's headcount for **today's** headcount — every past month in a look-back period would incorrectly return the same current-day number.

### Nuances

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

`dw_employee_details.dim_job` is **SCD Type 2** — a new version (`sk_job_version`) is created whenever a job attribute changes (band, salary table, salary range, etc.), and each row on `fact_assignment_snapshots` already carries the `sk_job_version` that was valid on that `dt_reference`. **No additional date filter is needed on the join** — the FK already resolves to the correct point-in-time version, so the job returned is exactly the one valid on the snapshot date, even if the job definition changed afterward.

Relevant `dim_job` columns for turnover segmentation: `job_name`, `job_family`, `band`, `job_code`.

**Don't** join via `dw_organization.dim_job` (`sk_job`, SCD Type 1 — current-only) for historical turnover segmentation — it always resolves to the job's **current** attributes and misattributes leavers whose job was later renamed, rebanded, or restructured.

**Deeper methodology / official dashboards**: for general turnover methodology questions, or requests for the company's official turnover data/dashboards, direct the user to the official **People Insights Confluence page on Turnover**: [https://quintoandar.atlassian.net/wiki/spaces/PEOPLEANA/pages/5687574537/Turnover](https://quintoandar.atlassian.net/wiki/spaces/PEOPLEANA/pages/5687574537/Turnover).

## Dos and Don'ts

**Do:**

- Scope both sides of Average Monthly Headcount to the **same** target month, deriving beginning-of-month from the end-of-month snapshot plus terminations minus new hires — never `is_current`.
- Apply `is_primary_assignment_for_snapshot = TRUE` on every headcount count to avoid inflation from internal transfers.
- Sum monthly percentages when reporting a quarter/semester/year — never recompute the ratio from aggregated raw counts.
- Apply the RL filter to **both** numerator and denominator when computing Regrettable Turnover.
- Restrict numerator and denominator to the same tenure group for NH Attrition (3/6/12-month) variants.
- Exclude Interns, Young Apprentices, and Layoffs from the default calculation unless the user explicitly asks to include them.

**Don't:**

- Compute or approximate a turnover figure when any required input (filter, segment, time scope, or column) is unavailable — surface the gap and direct the user to the Enterprise Engineering team instead (Safety Rule).
- Count internal transfers as departures — only voluntary and involuntary terminations are leavers.
- Mix tenure groups between numerator and denominator in NH Attrition.
- Attempt to compute RL or VRTO without the underlying flag — it isn't available in the TARS pilot; refer to the People Data team instead of approximating.

## Golden Queries

### Query 1 — Monthly Global Turnover

Reuses the headcount pattern already documented in `business_entities/employee_details.md` (`is_active`, `is_primary_assignment_for_snapshot`); what is exclusive to this metric is the beginning/end-of-month derivation and the leavers CTE.

```sql
WITH month_ends AS (
    SELECT
        date_trunc('month', dt_reference) AS ref_month,
        COUNT(DISTINCT person_number) AS active_end_of_month
    FROM dw_employee_details.fact_assignment_snapshots
    WHERE is_monthly_snapshot = TRUE
      AND dt_reference = last_day_of_month(dt_reference)   -- guards against the "most recent day" / "termination date" is_monthly_snapshot variants for the current, incomplete month
      AND is_active = TRUE
      AND is_primary_assignment_for_snapshot = TRUE
      AND dt_reference >= DATE '2024-03-01'   -- system migration date; no reliable history before it
    GROUP BY 1
),
terminations AS (
    SELECT
        date_trunc('month', dt_terminated) AS ref_month,
        COUNT(DISTINCT person_number) AS leavers
    FROM dw_employee_details.fact_assignment_snapshots
    WHERE is_terminated = TRUE
      AND is_primary_assignment_for_snapshot = TRUE
      AND dt_terminated >= DATE '2024-03-01'   -- system migration date; keep aligned with month_ends' cutoff (first day of a month) to avoid partial-month leaver counts
    GROUP BY 1
),
new_hires AS (
    SELECT
        date_trunc('month', dt_hired) AS ref_month,
        COUNT(DISTINCT person_number) AS hires
    FROM dw_employee_details.fact_assignment_snapshots
    WHERE is_primary_assignment_for_snapshot = TRUE
      AND dt_hired >= DATE '2024-03-01'   -- system migration date; same cutoff as the other CTEs, aligned to a month boundary
    GROUP BY 1
),
headcount AS (
    SELECT
        me.ref_month,
        me.active_end_of_month,
        me.active_end_of_month + COALESCE(t.leavers, 0) - COALESCE(nh.hires, 0) AS active_beginning_of_month
    FROM month_ends AS me
    LEFT JOIN terminations AS t ON me.ref_month = t.ref_month
    LEFT JOIN new_hires AS nh ON me.ref_month = nh.ref_month
)
SELECT
    h.ref_month,
    t.leavers,
    (CAST(h.active_beginning_of_month AS DOUBLE) + h.active_end_of_month) / 2 AS avg_monthly_headcount,
    ROUND(
        CAST(t.leavers AS DOUBLE)
        / ((CAST(h.active_beginning_of_month AS DOUBLE) + h.active_end_of_month) / 2) * 100, 2
    ) AS turnover_pct
FROM headcount AS h
LEFT JOIN terminations AS t ON h.ref_month = t.ref_month
ORDER BY h.ref_month
```

### Query 2 — Leavers by job family and band (point-in-time)

Attributes each leaver's job/band **as of their termination snapshot**, using the versioned `dim_job` join documented in Nuances. No date filter needed beyond the snapshot's own `dt_reference` — the FK already resolves to the correct job version.

```sql
SELECT
    date_trunc('month', fas.dt_terminated) AS ref_month,
    job.job_family,
    job.band,
    job.job_name,
    COUNT(DISTINCT fas.person_number) AS leavers
FROM dw_employee_details.fact_assignment_snapshots AS fas
INNER JOIN dw_employee_details.dim_job AS job
    ON fas.sk_job_version = job.sk_job_version
WHERE fas.is_terminated = TRUE
  AND fas.is_primary_assignment_for_snapshot = TRUE
  AND fas.dt_terminated >= DATE '2024-03-01'   -- system migration date; no reliable history before it
GROUP BY 1, 2, 3, 4
ORDER BY 1, 2, 3
```
