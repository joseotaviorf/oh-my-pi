# Turnover

## Ownership

**Data Owner:**
- pedro.prates@quintoandar.com.br

**Data Steward:**
- kevin.trindade@quintoandar.com.br

## Overview

**Turnover** is QuintoAndar's official indicator for workforce attrition, computed **monthly** on `dw_employee_details.fact_assignment_snapshots`. **Every** turnover or attrition input — leavers, month terminations, new hires, and end-of-month actives — must come from **monthly closing snapshots only**: `is_monthly_snapshot_for_employee = TRUE` (one row per employee per `dt_month_reference`). Never mix in daily rows, `is_current_for_employee`, or hire/termination-day snapshots. The official monthly formula is:

```
Turnover (month) = Monthly Terminations / Average Monthly Headcount
```

Real exits are identified by `termination_type IS NOT NULL`, scoped to effective workers, and the denominator is the **average of start-of-month and end-of-month headcount**, with start-of-month reconstructed from the month-end monthly snapshot (see Calculation). Assemble the calculation from the facts below so the result stays auditable.

**Safety rule:** if any input required by a turnover calculation is unavailable — a missing column, an unresolvable filter, an undefined segment, or an unsupported time scope — explain what is missing and direct the user to the People Insights team. A partial or approximate turnover number is worse than no number.

**Non-standard calculations:** this document defines the official formula. When a user requests a different formula, exclusion, or aggregation, direct them to the People Insights team rather than approximating a custom variant.

## Related Domain Entities

- Employee Details

## Catalog

| Metric | Type |
| :---- | :---- |
| Turnover | OKR |
| New Hire Attrition | Health Metric |
| 6-Month Turnover | Health Metric |
| 12-Month Turnover | Health Metric |

## Known Limitations

PIN went live on **2024-03-01**; before that date, job, cost center, hierarchy, `is_effective_worker`, and the resulting eligible workforce population may be inconsistent because the source system was not yet live.

- Every turnover or attrition calculation must use only records on or after `2024-03-01`. The requested period must start on or after this date.
- The same floor applies to every descriptive statistic or aggregation derived from turnover data, including `MIN`, `MAX`, `AVG`, `SUM`, counts, median, percentiles, rates, distributions, trends, and period comparisons. Never blend pre-go-live records into a result.
- Although individual `dt_employee_hired` and `dt_terminated` values remain reliable before go-live, they are not sufficient to reconstruct the eligible workforce population or calculate a reliable turnover/attrition metric.
- If a question requires any pre-go-live period, explain the PIN source-system limitation and direct the user to **People Insights** or **Enterprise Engineering** instead of approximating the result.

## Glossary and Synonyms

- **Turnover**, **Global Turnover**, **rotatividade** → the official monthly formula (see Calculation)
- **New Hire Attrition**, **NH Attrition**, **3moTO**, **3-Month Turnover** → NH Attrition, `< 90 days` tenure variant (its own formula — see Calculation)
- **6-Month Turnover**, **6moTO** → early-tenure attrition, `< 6 calendar months` variant
- **12-Month Turnover**, **12moTO** → early-tenure attrition, `< 12 calendar months` variant
- **Voluntary turnover / Involuntary turnover** → turnover sliced by `termination_type` (`voluntary` / `involuntary`)
- **Regrettable Turnover**, **RT**, **VRTO** (Voluntary Regrettable Turnover), **RL** (Regrettable Loss) → **not available on TARS**. Apply the Safety Rule if someone asks for it.

## Scope

**Included**: Global (monthly) Turnover; New Hire Attrition (`< 90 days`); early-tenure attrition (`< 6` / `< 12` calendar months); Voluntary/Involuntary segmentation; Layoffs/Reorgs as a distinct, explicitly-requested segment.

**Excluded by default:**

- **Interns** and **Young Apprentices** — `is_effective_worker = FALSE`; excluded on both the leavers and the headcount sides.
- **Internal transfers, expatriate movements, intern/apprentice effectivations, and still-active assignments** — these are not company exits and carry `termination_type = NULL`, so `termination_type IS NOT NULL` already removes them.
- **Layoffs / Reorgs** — excluded by default via `AND NOT COALESCE(is_reorganization_termination, FALSE)` on the leavers side. Include them only when the user explicitly asks (by dropping that predicate).

## The building blocks

All on `dw_employee_details.fact_assignment_snapshots`, and **always** filtered with `is_monthly_snapshot_for_employee = TRUE`:

- `is_monthly_snapshot_for_employee` — **required on every fact read** for turnover/attrition. Selects the official month-closing row (one per employee per `dt_month_reference`); mirrors legacy `base_fotografias`.
- `dt_month_reference` — last calendar day of the snapshot month; use it to pin EOM actives and to bucket monthly counts.
- `termination_type` — `voluntary`, `involuntary`, `pending`, or `NULL`. **Any non-NULL value is a real company exit** and counts in turnover; slice by value for the voluntary/involuntary breakdown. `pending` is a real exit whose closing action is not yet mapped (counted; it later resolves to voluntary/involuntary). `NULL` means "not a company exit" (still active, internal transfer, expatriate movement, or intern/apprentice effectivation). Involuntary exits include the rare case of death.
- `is_effective_worker` — `TRUE` when the assignment is in the official effective workforce for turnover/headcount; `FALSE` for Interns and Young Apprentices.
- `is_reorganization_termination` — `TRUE` only on the terminated snapshots of a layoff/reorganization exit; `FALSE` otherwise.
- `dt_terminated`, `dt_reference`, `dt_employee_hired` — the termination date, the snapshot date, and the company-tenure anchor (read on the monthly closing row).
- `is_active` — `TRUE` while employed on the monthly closing `dt_reference`; the model treats the termination date itself as inactive.
- `is_transfer_hire` — `TRUE` on the incoming assignment of an internal transfer (not a company admission).

## Calculation

### Global Turnover (monthly)

```
Turnover (month) = Monthly Terminations / Average Monthly Headcount
Average Monthly Headcount = (Start-of-month headcount + End-of-month headcount) / 2
Start-of-month headcount = End-of-month actives + Month terminations − Month new hires
```

All components below use **only** `is_monthly_snapshot_for_employee = TRUE` rows.

- **Monthly Terminations (numerator)** — `COUNT(DISTINCT person_number)` on monthly snapshots whose `dt_terminated` falls in the month, with `termination_type IS NOT NULL`, `is_effective_worker = TRUE`, and `NOT COALESCE(is_reorganization_termination, FALSE)` (drop the last predicate to include layoffs).
- **End-of-month actives** — `COUNT(DISTINCT person_number)` on the month's closing monthly snapshot (`dt_month_reference = month_end`) with `is_effective_worker = TRUE` and `is_active = TRUE`. A last-day termination does **not** count here.
- **Month terminations (SOM identity)** — same monthly-snapshot grain as the numerator (`termination_type IS NOT NULL`, `is_effective_worker = TRUE`, `dt_terminated` in the month), **including** reorganization exits. This count feeds start-of-month headcount only; the default numerator still excludes reorgs.
- **Month new hires (SOM identity)** — `COUNT(DISTINCT person_number)` on monthly snapshots with `dt_employee_hired` in the month, `is_effective_worker = TRUE`, and `is_transfer_hire = FALSE` (intern/apprentice effectivations count; internal transfer-ins do not).
- **Start-of-month headcount** — reconstruct from the month-end monthly snapshot: `End-of-month actives + Month terminations − Month new hires`.

### Voluntary / Involuntary

Slice the numerator by `termination_type`: `voluntary` (resignations) and `involuntary` (company-initiated terminations). `pending` exits are counted in the total but not yet attributable to either side.

### Aggregated Periods

Turnover is **computed on a monthly basis**. For a quarter/semester/year, compute each month's percentage and **sum the monthly percentages** to get the period total. The first month included must be March 2024 or later; never use a pre-`2024-03-01` month in the period or in any `MIN`, `MAX`, `AVG`, percentile, distribution, or trend derived from monthly turnover.

### New Hire Attrition (`< 90 days`)

NH Attrition uses its own formula:

```
NH Attrition (month) = T90 / (T90 + A90)
```

- **T90** — eligible terminations in the month (same eligibility as turnover) with company tenure `< 90 days` at termination: `date_diff('day', dt_employee_hired, dt_terminated) < 90`.
- **A90** — employees active at month end (`dt_reference = month_end`, primary, effective, `is_active = TRUE`) with company tenure `< 90 days` at month end: `date_diff('day', dt_employee_hired, month_end) < 90`.
- The denominator is exactly `T90 + A90`. A month-end termination belongs only to `T90`, never also to `A90`.

### Early-tenure Attrition (`< 6` / `< 12` calendar months)

Same shape as NH Attrition, but the cohort uses **calendar-month anniversaries** (not day counts):

- `< 6 months`: reference date `< date_add('month', 6, dt_employee_hired)`.
- `< 12 months`: reference date `< date_add('month', 12, dt_employee_hired)`.

Use `dt_terminated` as the reference for the numerator and `month_end` for the active denominator. The official cohort boundary is the calendar-month anniversary of `dt_employee_hired`.

### Regrettable Turnover / VRTO

Not available on TARS. Apply the Safety Rule.

## Nuances

**Job reference at time of departure** — to segment leavers by the job/band/family held **when they left**, join the versioned job dimension via the FK already on the fact:

```
fact_assignment_snapshots.sk_job_version → dw_employee_details.dim_job.sk_job_version
```

`dw_employee_details.dim_job` is SCD Type 2, and each fact row already carries the `sk_job_version` valid on its `dt_reference`, so **no date filter is needed** on the join — it resolves to the point-in-time job even if the job was later renamed or rebanded. Use `dw_employee_details.dim_job` (`job_name`, `job_family`, `band`, `job_code`); the SCD Type 1 `dw_organization.dim_job` resolves to current attributes only.

**Detail labels** — `dw_employee_details.dim_termination` (joined via `sk_termination_event_definition`) provides the action and reason labels for exit-cause detail. Classify voluntary/involuntary with `termination_type`, not with the label columns.

**History start** — every turnover/attrition metric and descriptive statistic must start on or after the PIN go-live date `2024-03-01`; see Known Limitations.

**Deeper methodology / official dashboards** — direct the user to the People Insights Confluence page on Turnover: [https://quintoandar.atlassian.net/wiki/spaces/PEOPLEANA/pages/5687574537/Turnover](https://quintoandar.atlassian.net/wiki/spaces/PEOPLEANA/pages/5687574537/Turnover).

## Dos and Don'ts

**Presentation:**

- Report turnover and attrition percentages with exactly **2 decimal places** (e.g. `12.34%`). Golden queries use `ROUND(..., 2)` — match that precision in any derived rate.
- **Cast to `DOUBLE` before dividing, not after.** Trino's decimal division does not expand scale (`x / y` scale is `max(xs, ys)`, it never grows), so a numerator built from a literal like `100.0` (scale 1) keeps that scale through every subsequent division — the result silently rounds to 1 decimal place before any outer `ROUND(..., 2)` runs, defeating the 2-decimal-place rule above. Wrap operands with `CAST(... AS DOUBLE)` at **each** division site in the expression tree (not just the outermost one) so the arithmetic runs in floating point throughout.

**Do:**

- Filter **every** `fact_assignment_snapshots` read with `is_monthly_snapshot_for_employee = TRUE` — leavers, SOM terminations, new hires, EOM actives, and attrition cohorts alike.
- Compute the numerator from monthly snapshots with `dt_terminated` in the month, `termination_type IS NOT NULL`, `is_effective_worker = TRUE`, and `NOT is_reorganization_termination`.
- Reconstruct start-of-month headcount as `end-of-month actives + month terminations − month new hires`, then take `(SOM + EOM) / 2` as the denominator.
- Sum monthly percentages when reporting a quarter/semester/year.
- Use `T90 / (T90 + A90)` for New Hire Attrition, and calendar-month anniversaries for the 6/12-month variants — still on monthly snapshots only.
- Slice by `termination_type` for voluntary vs. involuntary.

**Don't:**

- Compute or approximate a turnover figure when any required input is unavailable — surface the gap (Safety Rule).
- Use daily snapshots, `is_current_for_employee`, hire-day rows (`dt_reference = dt_employee_hired`), or termination-day rows (`dt_reference = dt_terminated`) instead of `is_monthly_snapshot_for_employee = TRUE`.
- Use average headcount as the New Hire / early-tenure attrition denominator — those use `T + A` in the same tenure cohort.
- Infer voluntary/involuntary from action/reason labels — use `termination_type`.
- Attempt RL / VRTO — not available on TARS; refer to the People Insights team.
- Include records before **2024-03-01** (PIN go-live) in any turnover/attrition metric or descriptive statistic, including `MIN`, `MAX`, `AVG`, counts, percentiles, rates, distributions, or trends; see Known Limitations.

## Golden Queries

### Query 1 — Global 2025 Year Turnover

Computes each month of 2025 and sums the monthly percentages for the annual total, per the Aggregated Periods rule.

```sql
WITH months AS (
    SELECT month_start
    FROM UNNEST(
        sequence(DATE '2025-01-01', DATE '2025-12-01', INTERVAL '1' MONTH)
    ) AS t (month_start)
),
month_bounds AS (
    SELECT
        month_start,
        date_add('day', -1, date_add('month', 1, month_start)) AS month_end
    FROM months
),
leavers AS (
    SELECT
        date_trunc('month', fas.dt_terminated) AS month_start,
        COUNT(DISTINCT fas.person_number) AS leavers
    FROM dw_employee_details.fact_assignment_snapshots AS fas
    WHERE fas.is_monthly_snapshot_for_employee = TRUE
      AND fas.termination_type IS NOT NULL
      AND fas.is_effective_worker = TRUE
      AND NOT COALESCE(fas.is_reorganization_termination, FALSE)
      AND fas.dt_terminated BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'
    GROUP BY 1
),
month_terminations AS (
    SELECT
        date_trunc('month', fas.dt_terminated) AS month_start,
        COUNT(DISTINCT fas.person_number) AS terminations
    FROM dw_employee_details.fact_assignment_snapshots AS fas
    WHERE fas.is_monthly_snapshot_for_employee = TRUE
      AND fas.termination_type IS NOT NULL
      AND fas.is_effective_worker = TRUE
      AND fas.dt_terminated BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'
    GROUP BY 1
),
month_new_hires AS (
    SELECT
        date_trunc('month', fas.dt_employee_hired) AS month_start,
        COUNT(DISTINCT fas.person_number) AS new_hires
    FROM dw_employee_details.fact_assignment_snapshots AS fas
    WHERE fas.is_monthly_snapshot_for_employee = TRUE
      AND fas.is_effective_worker = TRUE
      AND COALESCE(fas.is_transfer_hire, FALSE) = FALSE
      AND fas.dt_employee_hired BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'
    GROUP BY 1
),
ending_headcount AS (
    SELECT
        mb.month_start,
        COUNT(DISTINCT fas.person_number) AS hc_eom
    FROM month_bounds AS mb
    LEFT JOIN dw_employee_details.fact_assignment_snapshots AS fas
        ON fas.is_monthly_snapshot_for_employee = TRUE
        AND fas.dt_month_reference = mb.month_end
        AND fas.is_effective_worker = TRUE
        AND fas.is_active = TRUE
    GROUP BY 1
),
monthly_turnover AS (
    SELECT
        mb.month_start AS ref_month,
        COALESCE(l.leavers, 0) AS leavers,
        COALESCE(e.hc_eom, 0) AS hc_eom,
        COALESCE(e.hc_eom, 0) + COALESCE(t.terminations, 0) - COALESCE(h.new_hires, 0) AS hc_som,
        100.0 * CAST(COALESCE(l.leavers, 0) AS DOUBLE) / NULLIF(
            CAST(
                (COALESCE(e.hc_eom, 0) + COALESCE(t.terminations, 0) - COALESCE(h.new_hires, 0))
                + COALESCE(e.hc_eom, 0)
            AS DOUBLE) / 2.0,
            0
        ) AS turnover_pct
    FROM month_bounds AS mb
    LEFT JOIN leavers AS l
        ON l.month_start = mb.month_start
    LEFT JOIN month_terminations AS t
        ON t.month_start = mb.month_start
    LEFT JOIN month_new_hires AS h
        ON h.month_start = mb.month_start
    LEFT JOIN ending_headcount AS e
        ON e.month_start = mb.month_start
)
SELECT
    2025 AS ref_year,
    SUM(leavers) AS leavers,
    ROUND(SUM(turnover_pct), 2) AS turnover_pct
FROM monthly_turnover
```

### Query 2 — Voluntary Turnover for a Specific L1 Manager in 2026-01

Scopes leavers and headcount to the manager's org via `dim_management_hierarchy.name_l1`, restricted to `termination_type = 'voluntary'`.

```sql
WITH month_bounds AS (
    SELECT DATE '2026-01-01' AS month_start, DATE '2026-01-31' AS month_end
),
leavers AS (
    SELECT COUNT(DISTINCT fas.person_number) AS leavers
    FROM dw_employee_details.fact_assignment_snapshots AS fas
    INNER JOIN dw_employee_details.dim_management_hierarchy AS hier
        ON fas.sk_hierarchy_version = hier.sk_hierarchy_version
    CROSS JOIN month_bounds AS mb
    WHERE fas.is_monthly_snapshot_for_employee = TRUE
      AND fas.termination_type = 'voluntary'
      AND fas.is_effective_worker = TRUE
      AND NOT COALESCE(fas.is_reorganization_termination, FALSE)
      AND fas.dt_terminated BETWEEN mb.month_start AND mb.month_end
      AND hier.name_l1 = '<manager_name>'
),
month_terminations AS (
    SELECT COUNT(DISTINCT fas.person_number) AS terminations
    FROM dw_employee_details.fact_assignment_snapshots AS fas
    INNER JOIN dw_employee_details.dim_management_hierarchy AS hier
        ON fas.sk_hierarchy_version = hier.sk_hierarchy_version
    CROSS JOIN month_bounds AS mb
    WHERE fas.is_monthly_snapshot_for_employee = TRUE
      AND fas.termination_type IS NOT NULL
      AND fas.is_effective_worker = TRUE
      AND fas.dt_terminated BETWEEN mb.month_start AND mb.month_end
      AND hier.name_l1 = '<manager_name>'
),
month_new_hires AS (
    SELECT COUNT(DISTINCT fas.person_number) AS new_hires
    FROM dw_employee_details.fact_assignment_snapshots AS fas
    INNER JOIN dw_employee_details.dim_management_hierarchy AS hier
        ON fas.sk_hierarchy_version = hier.sk_hierarchy_version
    CROSS JOIN month_bounds AS mb
    WHERE fas.is_monthly_snapshot_for_employee = TRUE
      AND fas.is_effective_worker = TRUE
      AND COALESCE(fas.is_transfer_hire, FALSE) = FALSE
      AND fas.dt_employee_hired BETWEEN mb.month_start AND mb.month_end
      AND hier.name_l1 = '<manager_name>'
),
ending_headcount AS (
    SELECT COUNT(DISTINCT fas.person_number) AS hc_eom
    FROM dw_employee_details.fact_assignment_snapshots AS fas
    INNER JOIN dw_employee_details.dim_management_hierarchy AS hier
        ON fas.sk_hierarchy_version = hier.sk_hierarchy_version
    CROSS JOIN month_bounds AS mb
    WHERE fas.is_monthly_snapshot_for_employee = TRUE
      AND fas.dt_month_reference = mb.month_end
      AND fas.is_effective_worker = TRUE
      AND fas.is_active = TRUE
      AND hier.name_l1 = '<manager_name>'
)
SELECT
    l.leavers AS voluntary_leavers,
    e.hc_eom + t.terminations - h.new_hires AS hc_som,
    e.hc_eom,
    ROUND(
        100.0 * CAST(l.leavers AS DOUBLE) / NULLIF(
            CAST(e.hc_eom + t.terminations - h.new_hires + e.hc_eom AS DOUBLE) / 2.0,
            0
        ),
        2
    ) AS voluntary_turnover_pct
FROM leavers AS l
CROSS JOIN month_terminations AS t
CROSS JOIN month_new_hires AS h
CROSS JOIN ending_headcount AS e
```

> **Tip:** Replace `<manager_name>` with the manager's name as it appears in `dim_management_hierarchy.name_l1`.

### Query 3 — New Hire Attrition for 2026-01

Single-month `T90 / (T90 + A90)`.

```sql
WITH month_bounds AS (
    SELECT DATE '2026-01-01' AS month_start, DATE '2026-01-31' AS month_end
),
terminations_90 AS (
    SELECT COUNT(DISTINCT fas.person_number) AS t90
    FROM dw_employee_details.fact_assignment_snapshots AS fas
    CROSS JOIN month_bounds AS mb
    WHERE fas.is_monthly_snapshot_for_employee = TRUE
      AND fas.termination_type IS NOT NULL
      AND fas.is_effective_worker = TRUE
      AND NOT COALESCE(fas.is_reorganization_termination, FALSE)
      AND fas.dt_terminated BETWEEN mb.month_start AND mb.month_end
      AND date_diff('day', fas.dt_employee_hired, fas.dt_terminated) < 90
),
active_90_eom AS (
    SELECT COUNT(DISTINCT fas.person_number) AS a90
    FROM dw_employee_details.fact_assignment_snapshots AS fas
    CROSS JOIN month_bounds AS mb
    WHERE fas.is_monthly_snapshot_for_employee = TRUE
      AND fas.dt_month_reference = mb.month_end
      AND fas.is_active = TRUE
      AND fas.is_effective_worker = TRUE
      AND date_diff('day', fas.dt_employee_hired, mb.month_end) < 90
)
SELECT
    t.t90 AS terminations_90,
    a.a90 AS active_90_eom,
    t.t90 + a.a90 AS denominator,
    ROUND(100.0 * CAST(t.t90 AS DOUBLE) / NULLIF(t.t90 + a.a90, 0), 2) AS nh_attrition_pct
FROM terminations_90 AS t
CROSS JOIN active_90_eom AS a
```

For the **6-month** and **12-month** variants, replace the tenure predicates with the calendar-month anniversary: numerator `fas.dt_terminated < date_add('month', 6, fas.dt_employee_hired)` and denominator `mb.month_end < date_add('month', 6, fas.dt_employee_hired)` (and `12` for the twelve-month variant).

### Query 4 — Leavers by Band

Attributes each leaver's band **as of their termination month** via the versioned `dim_job` FK (see Nuances).

```sql
SELECT
    job.band,
    COUNT(DISTINCT fas.person_number) AS leavers
FROM dw_employee_details.fact_assignment_snapshots AS fas
INNER JOIN dw_employee_details.dim_job AS job
    ON fas.sk_job_version = job.sk_job_version
WHERE fas.is_monthly_snapshot_for_employee = TRUE
  AND fas.termination_type IS NOT NULL
  AND fas.is_effective_worker = TRUE
  AND NOT COALESCE(fas.is_reorganization_termination, FALSE)
  AND fas.dt_terminated >= date_add('month', -12, current_date)
GROUP BY 1
ORDER BY 2 DESC
```

> **Tip:** The default window is the trailing 12 months; adjust the `dt_terminated` predicate to the period the user asks for.

