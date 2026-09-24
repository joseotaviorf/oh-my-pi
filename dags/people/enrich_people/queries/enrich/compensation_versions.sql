/*
 * compensation_versions — grain and design notes
 *
 * Shared enrich model that owns the salary split + consolidation pipeline. It is the single source
 * of truth for sk_compensation: dw_compensation.fact_compensations reads this table and presents it,
 * and any other consumer (e.g. dw_employee_details.fact_assignment_snapshots) can attach the same
 * sk_compensation via an equality join, so no DW depends on another DW. The sk_compensation formula
 * here is identical to the one fact_compensations used historically, keeping downstream FK semantics.
 *
 * Grain: one row per approved salary record × assignment job period × job validity window.
 * A single salary entry can produce multiple rows when the employee's job changes mid-salary
 * or when job_with_salary_table receives a new SCD2 version while the salary is still open.
 *
 * Transfer-continuation:
 *   All GLB_TRANSFER continuity logic lives in datalake_people.identifier_mapping.
 *   id_continuous_employment_cycle groups every assignment that belongs to the same
 *   uninterrupted employment spell; it resets only on true rehire.
 *   No transfer logic is reimplemented here.
 *
 * Tenure anchors:
 *   - Company : dt_employee_hired from identifier_mapping (respects transfer continuity).
 *   - Position: start of the current job stint within the cycle (gaps-and-islands on id_job).
 *               A→B→A returns a stint from the return date, not the original start.
 *   - Band    : start of the current band stint within the cycle (gaps-and-islands on band
 *               from job_with_salary_table). Band can be < position when a job is reclassified
 *               to a different band without the employee changing roles (job SCD2 update).
 *
 * PLR target source:
 *   target_plr and target_plr_salary_multiplier are read exclusively from person-level
 *   Oracle HCM ICP element entries (datalake_pin_compensation_clean.element_*). A person
 *   without an active ICP entry has NULL targets — there is no fallback to dim_job, since
 *   the ICP migration is complete and the dim_job columns only carry the legacy default
 *   for the job, not whether a specific person should receive it. Two PLR shapes coexist:
 *   "PLR - Salary Multiple" (multiplier of salary, current model) and
 *   "Annual Target - PLR" / "Annual Target - PLR (Dolar)" (fixed annual amount, legacy
 *   model kept for employees on contracts created before the multiplier rollout).
 *
 * CTE pipeline:
 *   [assignment chain]
 *     assignment_identifier_mapping   — one row per id_assignment with its cycle id
 *     assignment_history_base         — all_assignments deduplicated per (assignment, date range)
 *     assignment_job_groups           — detect job changes within an assignment (gaps-and-islands)
 *     assignment_history              — one row per continuous job period per assignment
 *     job_with_salary_table_effective — job SCD2 versions from enrich (sk_job_version aligned with dim_job)
 *     assignment_history_with_band    — enrich assignment history with band from job_with_salary_table
 *     assignment_job_stint_groups     — detect job change across assignments within same cycle
 *     job_tenure_start                — one row per (person, cycle, job, stint)
 *     assignment_band_stint_groups    — detect band change across assignments within same cycle
 *     band_tenure_start               — one row per (person, cycle, band, stint)
 *
 *   [person-level PLR chain]
 *     person_plr_base                 — ICP element entries joined to type/input; intersected validity
 *     person_plr_multiplier_ranked    — row_number by (id_person, dt_valid_from) for multiplier
 *     person_plr_multiplier           — base filtered to "PLR - Salary Multiple" (new model)
 *     person_plr_amount_ranked        — row_number by (id_person, dt_valid_from) for fixed amount
 *     person_plr_amount               — base filtered to "Annual Target - PLR(*)" (legacy fixed amount)
 *
 *   [salary chain]
 *     salary_with_person              — approved salaries joined to identifier_mapping
 *     salary_with_assignment_job      — split salary periods by job changes
 *     salary_with_job_version         — split salary periods by job_with_salary_table SCD2 windows
 *     salary_plr_boundary_salary_starts    — salary sub-period start dates
 *     salary_plr_boundary_multiplier_*    — PLR multiplier validity edges
 *     salary_plr_boundary_amount_*        — PLR fixed-amount validity edges
 *     salary_plr_boundary_union           — all boundary rows combined
 *     salary_plr_period_boundaries        — distinct boundary set per salary sub-period
 *     salary_plr_periods              — rebuild contiguous sub-periods from boundaries
 *     salary_with_plr_target          — attach multiplier and amount PLR via independent joins
 *     salary_enriched                 — attach event_definition; null adjustments on split rows
 *     salary_consolidation_base       — normalise NULL dt_ended to 9999-12-31
 *     salary_consolidation_groups     — detect consecutive identical salary records (gaps-and-islands)
 *     salary_consolidated             — collapse identical consecutive records into one row
 *     salary_with_reference           — add dt_reference = LEAST(DATE('{load_start_date}'), dt_valid_to)
 */
WITH salary_with_person AS (
    -- Approved salaries enriched with person identifiers and cycle metadata from identifier_mapping.
    -- dt_employee_hired is the hire date for the current continuous employment cycle;
    -- it is used directly as the company tenure anchor in the final SELECT.
    SELECT
        sal.id_salary,
        sal.id_person,
        sal.id_assignment,
        sal.id_job,
        sal.id_action,
        sal.id_action_reason,
        sal.id_action_occurrence,
        im.id_period_of_service,
        im.id_continuous_employment_cycle,
        im.person_number,
        im.assignment_number,
        im.dt_employee_hired,
        sal.currency_code,
        sal.salary_amount,
        sal.annual_salary,
        sal.adjustment_amount,
        sal.adjustment_percent,
        sal.is_salary_approved,
        sal.dt_started,
        sal.dt_started AS dt_salary_original_started,
        sal.dt_ended
    FROM
        datalake_pin_compensation_clean.salary AS sal
    INNER JOIN
        datalake_people.identifier_mapping AS im
            ON sal.id_assignment = im.id_assignment
    WHERE
        sal.is_salary_approved = TRUE
        AND sal.dt_started <= DATE('{load_start_date}')
        AND (sal.dt_ended = DATE('9999-12-31') OR sal.dt_started <= sal.dt_ended)
        AND im.assignment_number NOT LIKE 'P%'
),
assignment_identifier_mapping_ranked AS (
    -- Stable mapping from id_assignment to id_continuous_employment_cycle.
    -- Picks the earliest dt_started in case an assignment appears in multiple
    -- identifier_mapping rows (edge case from partial loads).
    SELECT
        id_assignment,
        id_continuous_employment_cycle,
        ROW_NUMBER() OVER (
            PARTITION BY id_assignment
            ORDER BY dt_started ASC
        ) AS rn
    FROM
        datalake_people.identifier_mapping
),
assignment_identifier_mapping AS (
    SELECT
        id_assignment,
        id_continuous_employment_cycle
    FROM
        assignment_identifier_mapping_ranked
    WHERE
        rn = 1
),
assignment_history_base_ranked AS (
    -- Deduplicated assignment history: one row per (assignment, effective date range),
    -- keeping the highest effective_sequence / object_version_number to resolve Oracle
    -- correction rows that share the same date range.
    SELECT
        aa.id_person,
        aa.id_assignment,
        aa.id_job,
        aa.dt_effective_started,
        aa.dt_effective_ended,
        im.id_continuous_employment_cycle,
        ROW_NUMBER() OVER (
            PARTITION BY
                aa.id_assignment,
                aa.dt_effective_started,
                aa.dt_effective_ended
            ORDER BY
                aa.effective_sequence DESC,
                aa.object_version_number DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.all_assignments AS aa
    LEFT JOIN
        assignment_identifier_mapping AS im
            ON aa.id_assignment = im.id_assignment
    WHERE
        aa.id_job IS NOT NULL
        AND aa.assignment_number NOT LIKE 'P%'
),
assignment_history_base AS (
    SELECT
        id_person,
        id_assignment,
        id_job,
        dt_effective_started,
        dt_effective_ended,
        id_continuous_employment_cycle
    FROM
        assignment_history_base_ranked
    WHERE
        rn = 1
),
assignment_job_groups AS (
    -- Detect job changes within a single assignment using gaps-and-islands.
    -- A new group starts when id_job changes or there is a date gap.
    SELECT
        id_person,
        id_assignment,
        id_continuous_employment_cycle,
        id_job,
        dt_effective_started,
        dt_effective_ended,
        SUM(
            CASE
                WHEN LAG(id_job) OVER (
                    PARTITION BY id_assignment
                    ORDER BY dt_effective_started, dt_effective_ended
                ) <> id_job
                    OR LAG(id_job) OVER (
                        PARTITION BY id_assignment
                        ORDER BY dt_effective_started, dt_effective_ended
                    ) IS NULL
                    OR LAG(dt_effective_ended) OVER (
                        PARTITION BY id_assignment
                        ORDER BY dt_effective_started, dt_effective_ended
                    ) < dt_effective_started
                THEN 1
                ELSE 0
            END
        ) OVER (
            PARTITION BY id_assignment
            ORDER BY dt_effective_started, dt_effective_ended
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS change_group
    FROM
        assignment_history_base
),
assignment_history AS (
    -- Collapse consecutive rows with the same job into one period per assignment.
    -- Used both for salary splitting (salary_with_assignment_job) and tenure stints.
    SELECT
        id_person,
        id_assignment,
        id_continuous_employment_cycle,
        id_job,
        MIN(dt_effective_started) AS dt_effective_started,
        MAX(dt_effective_ended) AS dt_effective_ended
    FROM
        assignment_job_groups
    GROUP BY
        id_person,
        id_assignment,
        id_continuous_employment_cycle,
        id_job,
        change_group
),
job_with_salary_table_effective AS (
    -- Job SCD2 versions from enrich. sk_job_version uses the same MD5(id_job, dt_valid_from)
    -- formula as dw_compensation.dim_job so downstream FK semantics stay unchanged.
    SELECT
        MD5(CONCAT_WS('|',
            CAST(id_job AS STRING),
            CAST(dt_valid_from AS STRING)
        )) AS sk_job_version,
        id_job,
        band,
        salary_range_mid,
        target_rvv,
        target_sop,
        target_hiring_sop,
        target_exceptional_bonus,
        dt_valid_from,
        COALESCE(dt_valid_to, DATE('9999-12-31')) AS dt_valid_to
    FROM
        datalake_people.job_with_salary_table
    WHERE
        dt_valid_from <= DATE('{load_start_date}')
),
assignment_history_with_band AS (
    -- Enrich assignment history with the band from job_with_salary_table (SCD2).
    -- Intersect date ranges so that a job reclassification (band change without the employee
    -- moving) creates a separate period for each band version.
    -- This means band tenure can be shorter than position tenure when the job is reclassified.
    SELECT
        ah.id_person,
        ah.id_continuous_employment_cycle,
        GREATEST(ah.dt_effective_started, jst.dt_valid_from) AS dt_effective_started,
        LEAST(ah.dt_effective_ended, jst.dt_valid_to) AS dt_effective_ended,
        jst.band
    FROM
        assignment_history AS ah
    INNER JOIN
        job_with_salary_table_effective AS jst
            ON ah.id_job = jst.id_job
            AND jst.dt_valid_from <= ah.dt_effective_ended
            AND jst.dt_valid_to >= ah.dt_effective_started
    WHERE
        jst.band IS NOT NULL
),
assignment_job_max_end AS (
    -- Running MAX of dt_effective_ended across all preceding rows within the same
    -- (person, cycle, job) partition.  Using MAX instead of LAG is necessary because
    -- concurrent assignments can produce overlapping periods for the same job; LAG
    -- only sees the immediately preceding row and may miss a longer period that still
    -- covers the current row's start date (causing a false stint break).
    SELECT
        id_person,
        id_continuous_employment_cycle,
        id_job,
        dt_effective_started,
        dt_effective_ended,
        MAX(dt_effective_ended) OVER (
            PARTITION BY id_person, id_continuous_employment_cycle, id_job
            ORDER BY dt_effective_started, dt_effective_ended
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS max_prev_ended
    FROM
        assignment_history
),
assignment_job_stint_groups AS (
    -- Detect job stints across assignments within the same employment cycle.
    -- Partitioning by id_continuous_employment_cycle ensures stints span GLB_TRANSFER
    -- continuations (same cycle id) and reset on true rehire (new cycle id).
    -- A new stint starts when there is a date gap > 1 day (A→B→A creates two stints for A).
    SELECT
        id_person,
        id_continuous_employment_cycle,
        id_job,
        dt_effective_started,
        dt_effective_ended,
        SUM(
            CASE
                WHEN max_prev_ended IS NULL
                    OR max_prev_ended < DATE_ADD(dt_effective_started, -1)
                THEN 1
                ELSE 0
            END
        ) OVER (
            PARTITION BY id_person, id_continuous_employment_cycle, id_job
            ORDER BY dt_effective_started, dt_effective_ended
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS stint_group
    FROM
        assignment_job_max_end
),
job_tenure_start AS (
    -- One row per (person, cycle, job, stint).
    -- dt_stint_start / dt_stint_ended bound the salary join in the final SELECT.
    SELECT
        id_person,
        id_continuous_employment_cycle,
        id_job,
        MIN(dt_effective_started) AS dt_stint_start,
        MAX(dt_effective_ended) AS dt_stint_ended
    FROM
        assignment_job_stint_groups
    GROUP BY
        id_person,
        id_continuous_employment_cycle,
        id_job,
        stint_group
),
assignment_band_max_end AS (
    -- Running MAX of dt_effective_ended for overlapping-interval merging (same rationale
    -- as assignment_job_max_end — concurrent assignments produce overlapping band periods).
    SELECT
        id_person,
        id_continuous_employment_cycle,
        band,
        dt_effective_started,
        dt_effective_ended,
        MAX(dt_effective_ended) OVER (
            PARTITION BY id_person, id_continuous_employment_cycle, band
            ORDER BY dt_effective_started, dt_effective_ended
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS max_prev_ended
    FROM
        assignment_history_with_band
),
assignment_band_stint_groups AS (
    -- Same gaps-and-islands logic as job stints, applied to band across the cycle.
    SELECT
        id_person,
        id_continuous_employment_cycle,
        band,
        dt_effective_started,
        dt_effective_ended,
        SUM(
            CASE
                WHEN max_prev_ended IS NULL
                    OR max_prev_ended < DATE_ADD(dt_effective_started, -1)
                THEN 1
                ELSE 0
            END
        ) OVER (
            PARTITION BY id_person, id_continuous_employment_cycle, band
            ORDER BY dt_effective_started, dt_effective_ended
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS stint_group
    FROM
        assignment_band_max_end
),
band_tenure_start AS (
    SELECT
        id_person,
        id_continuous_employment_cycle,
        band,
        MIN(dt_effective_started) AS dt_stint_start,
        MAX(dt_effective_ended) AS dt_stint_ended
    FROM
        assignment_band_stint_groups
    GROUP BY
        id_person,
        id_continuous_employment_cycle,
        band,
        stint_group
),
person_plr_base AS (
    -- Person-level PLR target from Oracle HCM ICP (Individual Compensation Plans).
    -- Filters by element_name to keep only PLR-related entries and by input_value_name = 'Amount'
    -- to keep the numeric value (other input values like Periodicity and Full-Time Equivalent
    -- carry orthogonal metadata, not the target value itself).
    -- Validity = intersection of element_entry and element_entry_value effective dating;
    -- Oracle's open-ended sentinel 4712-12-31 is normalised to 9999-12-31.
    SELECT
        ee.id_person,
        et.element_name,
        et.input_currency_code AS currency_code,
        CAST(eev.screen_entry_value AS DECIMAL(18, 4)) AS plr_value,
        GREATEST(ee.dt_effective_started, eev.dt_effective_started) AS dt_valid_from,
        CASE
            WHEN LEAST(ee.dt_effective_ended, eev.dt_effective_ended) >= DATE('9999-12-31')
            THEN DATE('9999-12-31')
            ELSE LEAST(ee.dt_effective_ended, eev.dt_effective_ended)
        END AS dt_valid_to,
        eev.ts_updated
    FROM
        datalake_pin_compensation_clean.element_entry AS ee
    INNER JOIN
        datalake_pin_compensation_clean.element_type AS et
            ON ee.id_element_type = et.id_element_type
            AND et.element_name IN (
                'PLR - Salary Multiple',
                'Annual Target - PLR',
                'Annual Target - PLR (Dolar)'
            )
    INNER JOIN
        datalake_pin_compensation_clean.element_entry_value AS eev
            ON ee.id_element_entry = eev.id_element_entry
            AND eev.dt_effective_started <= ee.dt_effective_ended
            AND eev.dt_effective_ended >= ee.dt_effective_started
    INNER JOIN
        datalake_pin_compensation_clean.element_input_value AS eiv
            ON eev.id_input_value = eiv.id_input_value
            AND eiv.input_value_name = 'Amount'
),
person_plr_multiplier_ranked AS (
    -- Rank PLR multiplier entries by (id_person, dt_valid_from) keeping the latest update.
    -- Subquery + WHERE row_num = 1 for EMR Spark 3.5 dual-runtime compatibility.
    SELECT
        id_person,
        dt_valid_from,
        dt_valid_to,
        plr_value AS target_plr_salary_multiplier,
        ROW_NUMBER() OVER (
            PARTITION BY id_person, dt_valid_from
            ORDER BY ts_updated DESC
        ) AS row_num
    FROM
        person_plr_base
    WHERE
        element_name = 'PLR - Salary Multiple'
),
person_plr_multiplier AS (
    -- Salary-multiplier PLR target (new model). Defensive de-dup by (id_person, dt_valid_from)
    -- keeping the latest update; overlapping entries with different element_name would be a
    -- data error in PIN and should be corrected at the source by People Systems.
    SELECT
        id_person,
        dt_valid_from,
        dt_valid_to,
        target_plr_salary_multiplier
    FROM
        person_plr_multiplier_ranked
    WHERE
        row_num = 1
),
person_plr_amount_ranked AS (
    -- Rank PLR fixed-amount entries by (id_person, dt_valid_from) keeping the latest update.
    -- Subquery + WHERE row_num = 1 for EMR Spark 3.5 dual-runtime compatibility.
    SELECT
        id_person,
        currency_code,
        dt_valid_from,
        dt_valid_to,
        plr_value AS target_plr,
        ROW_NUMBER() OVER (
            PARTITION BY id_person, dt_valid_from
            ORDER BY ts_updated DESC
        ) AS row_num
    FROM
        person_plr_base
    WHERE
        element_name IN ('Annual Target - PLR', 'Annual Target - PLR (Dolar)')
),
person_plr_amount AS (
    -- Fixed-amount PLR target (legacy model). currency_code follows the element_type
    -- input_currency_code (BRL/EUR/MXN/ARS for "Annual Target - PLR"; USD for "Annual Target - PLR (Dolar)").
    -- Currency mismatch against the salary currency is not reconciled here.
    SELECT
        id_person,
        currency_code,
        dt_valid_from,
        dt_valid_to,
        target_plr
    FROM
        person_plr_amount_ranked
    WHERE
        row_num = 1
),
salary_with_assignment_job AS (
    -- Split salary periods by assignment job changes.
    -- When an employee changes job mid-salary, the salary row is split so each sub-period
    -- carries the correct id_job. COALESCE falls back to sal.id_job when no assignment
    -- history row overlaps (salary predates assignment history or pending assignment).
    SELECT
        sal.id_salary,
        sal.id_person,
        sal.id_assignment,
        sal.id_period_of_service,
        sal.id_continuous_employment_cycle,
        sal.person_number,
        sal.assignment_number,
        sal.dt_employee_hired,
        sal.currency_code,
        sal.salary_amount,
        sal.annual_salary,
        sal.adjustment_amount,
        sal.adjustment_percent,
        sal.is_salary_approved,
        sal.id_action,
        sal.id_action_reason,
        sal.id_action_occurrence,
        sal.dt_salary_original_started,
        COALESCE(assignment_history.id_job, sal.id_job) AS id_job,
        CASE
            WHEN assignment_history.id_job IS NULL
            THEN sal.dt_started
            ELSE GREATEST(sal.dt_started, assignment_history.dt_effective_started)
        END AS dt_started,
        CASE
            WHEN assignment_history.id_job IS NULL
            THEN sal.dt_ended
            ELSE LEAST(
                sal.dt_ended,
                assignment_history.dt_effective_ended
            )
        END AS dt_ended
    FROM
        salary_with_person AS sal
    LEFT JOIN
        assignment_history AS assignment_history
            ON assignment_history.id_assignment = sal.id_assignment
            AND assignment_history.dt_effective_started <= sal.dt_ended
            AND assignment_history.dt_effective_ended > sal.dt_started
),
salary_with_job_version AS (
    -- Split salary periods by job_with_salary_table validity windows to keep current job-version
    -- attributes. Each job SCD2 version carries its own compensation targets (RVV, SOP, hiring
    -- SOP, exceptional bonus), so a salary open across multiple job versions must be split
    -- accordingly. PLR targets come from person-level ICP entries in salary_with_plr_target.
    SELECT
        sal.id_salary,
        sal.id_person,
        sal.id_assignment,
        sal.id_period_of_service,
        sal.id_continuous_employment_cycle,
        sal.person_number,
        sal.assignment_number,
        sal.dt_employee_hired,
        sal.currency_code,
        sal.salary_amount,
        sal.annual_salary,
        sal.adjustment_amount,
        sal.adjustment_percent,
        sal.is_salary_approved,
        sal.id_action,
        sal.id_action_reason,
        sal.id_action_occurrence,
        sal.dt_salary_original_started,
        sal.id_job,
        CASE
            WHEN jst.sk_job_version IS NULL
            THEN sal.dt_started
            ELSE GREATEST(sal.dt_started, jst.dt_valid_from)
        END AS dt_started,
        CASE
            WHEN jst.sk_job_version IS NULL
            THEN sal.dt_ended
            ELSE LEAST(sal.dt_ended, jst.dt_valid_to)
        END AS dt_ended,
        jst.sk_job_version,
        jst.target_rvv,
        jst.target_sop,
        jst.target_hiring_sop,
        jst.target_exceptional_bonus
    FROM
        salary_with_assignment_job AS sal
    LEFT JOIN
        job_with_salary_table_effective AS jst
            ON sal.id_job = jst.id_job
            AND jst.dt_valid_from <= sal.dt_ended
            AND jst.dt_valid_to >= sal.dt_started
),
salary_plr_boundary_salary_starts AS (
    SELECT
        id_salary,
        id_assignment,
        dt_started AS salary_period_start,
        dt_started AS dt_boundary
    FROM
        salary_with_job_version
),
salary_plr_boundary_multiplier_starts AS (
    SELECT
        sal.id_salary,
        sal.id_assignment,
        sal.dt_started AS salary_period_start,
        plr_mult.dt_valid_from AS dt_boundary
    FROM
        salary_with_job_version AS sal
    INNER JOIN
        person_plr_multiplier AS plr_mult
            ON sal.id_person = plr_mult.id_person
            AND plr_mult.dt_valid_from > sal.dt_started
            AND plr_mult.dt_valid_from <= sal.dt_ended
),
salary_plr_boundary_multiplier_ends AS (
    SELECT
        sal.id_salary,
        sal.id_assignment,
        sal.dt_started AS salary_period_start,
        DATE_ADD(plr_mult.dt_valid_to, 1) AS dt_boundary
    FROM
        salary_with_job_version AS sal
    INNER JOIN
        person_plr_multiplier AS plr_mult
            ON sal.id_person = plr_mult.id_person
            AND plr_mult.dt_valid_to >= sal.dt_started
            AND plr_mult.dt_valid_to < sal.dt_ended
),
salary_plr_boundary_amount_starts AS (
    SELECT
        sal.id_salary,
        sal.id_assignment,
        sal.dt_started AS salary_period_start,
        plr_amt.dt_valid_from AS dt_boundary
    FROM
        salary_with_job_version AS sal
    INNER JOIN
        person_plr_amount AS plr_amt
            ON sal.id_person = plr_amt.id_person
            AND plr_amt.dt_valid_from > sal.dt_started
            AND plr_amt.dt_valid_from <= sal.dt_ended
),
salary_plr_boundary_amount_ends AS (
    SELECT
        sal.id_salary,
        sal.id_assignment,
        sal.dt_started AS salary_period_start,
        DATE_ADD(plr_amt.dt_valid_to, 1) AS dt_boundary
    FROM
        salary_with_job_version AS sal
    INNER JOIN
        person_plr_amount AS plr_amt
            ON sal.id_person = plr_amt.id_person
            AND plr_amt.dt_valid_to >= sal.dt_started
            AND plr_amt.dt_valid_to < sal.dt_ended
),
salary_plr_boundary_union AS (
    SELECT
        id_salary,
        id_assignment,
        salary_period_start,
        dt_boundary
    FROM
        salary_plr_boundary_salary_starts
    UNION ALL
    SELECT
        id_salary,
        id_assignment,
        salary_period_start,
        dt_boundary
    FROM
        salary_plr_boundary_multiplier_starts
    UNION ALL
    SELECT
        id_salary,
        id_assignment,
        salary_period_start,
        dt_boundary
    FROM
        salary_plr_boundary_multiplier_ends
    UNION ALL
    SELECT
        id_salary,
        id_assignment,
        salary_period_start,
        dt_boundary
    FROM
        salary_plr_boundary_amount_starts
    UNION ALL
    SELECT
        id_salary,
        id_assignment,
        salary_period_start,
        dt_boundary
    FROM
        salary_plr_boundary_amount_ends
),
salary_plr_period_boundaries AS (
    -- Collect every date boundary where a salary sub-period may start or end: the salary
    -- window itself plus each overlapping PLR validity edge from multiplier and amount
    -- timelines independently. Unlike assignment_history and job_with_salary_table (gapless
    -- SCD2), PLR ICP entries can leave uncovered gaps inside a salary window — e.g. a hire
    -- with salary from Jan but PLR ICP starting in Mar. Rebuilding periods from boundaries
    -- keeps those pre-PLR days as separate rows with NULL targets.
    SELECT DISTINCT
        id_salary,
        id_assignment,
        salary_period_start,
        dt_boundary
    FROM
        salary_plr_boundary_union
),
salary_plr_periods AS (
    SELECT
        b.id_salary,
        b.id_assignment,
        b.salary_period_start,
        b.dt_boundary AS dt_started,
        COALESCE(
            DATE_ADD(
                LEAD(b.dt_boundary) OVER (
                    PARTITION BY b.id_salary, b.id_assignment, b.salary_period_start
                    ORDER BY b.dt_boundary
                ),
                -1
            ),
            sal.dt_ended
        ) AS dt_ended
    FROM
        salary_plr_period_boundaries AS b
    INNER JOIN
        salary_with_job_version AS sal
            ON b.id_salary = sal.id_salary
            AND b.id_assignment = sal.id_assignment
            AND b.salary_period_start = sal.dt_started
),
salary_with_plr_target AS (
    -- Attach person-level PLR targets via independent joins on multiplier and amount timelines.
    -- Each shape is mutually exclusive by design at the source; sub-periods with no overlapping
    -- ICP entry keep target_plr / target_plr_salary_multiplier as NULL. salary_consolidation_*
    -- downstream merges consecutive rows that share the same compensation attributes.
    SELECT
        sal.id_salary,
        sal.id_person,
        sal.id_assignment,
        sal.id_period_of_service,
        sal.id_continuous_employment_cycle,
        sal.person_number,
        sal.assignment_number,
        sal.dt_employee_hired,
        sal.currency_code,
        sal.salary_amount,
        sal.annual_salary,
        sal.adjustment_amount,
        sal.adjustment_percent,
        sal.is_salary_approved,
        sal.id_action,
        sal.id_action_reason,
        sal.id_action_occurrence,
        sal.dt_salary_original_started,
        sal.id_job,
        sal.sk_job_version,
        per.dt_started,
        CASE
            WHEN per.dt_ended >= DATE('9999-12-31')
            THEN NULL
            ELSE per.dt_ended
        END AS dt_ended,
        plr_mult.target_plr_salary_multiplier,
        plr_amt.target_plr,
        plr_amt.currency_code AS target_plr_currency_code,
        sal.target_rvv,
        sal.target_sop,
        sal.target_hiring_sop,
        sal.target_exceptional_bonus
    FROM
        salary_plr_periods AS per
    INNER JOIN
        salary_with_job_version AS sal
            ON per.id_salary = sal.id_salary
            AND per.id_assignment = sal.id_assignment
            AND per.salary_period_start = sal.dt_started
    LEFT JOIN
        person_plr_multiplier AS plr_mult
            ON sal.id_person = plr_mult.id_person
            AND plr_mult.dt_valid_from <= per.dt_ended
            AND plr_mult.dt_valid_to >= per.dt_started
    LEFT JOIN
        person_plr_amount AS plr_amt
            ON sal.id_person = plr_amt.id_person
            AND plr_amt.dt_valid_from <= per.dt_ended
            AND plr_amt.dt_valid_to >= per.dt_started
),
salary_enriched AS (
    -- Attach event_definition for the salary change event.
    -- Adjustment fields are zeroed on rows that were created by a job, job-version or PLR split
    -- (dt_started != dt_salary_original_started) since the adjustment belongs only
    -- to the originating row where the actual salary change occurred.
    SELECT
        sal.id_salary,
        sal.id_person,
        sal.id_assignment,
        sal.id_period_of_service,
        sal.id_continuous_employment_cycle,
        sal.id_job,
        sal.person_number,
        sal.assignment_number,
        sal.dt_employee_hired,
        sal.currency_code,
        sal.salary_amount,
        sal.annual_salary,
        CASE
            WHEN sal.dt_started = sal.dt_salary_original_started
            THEN sal.adjustment_amount
            ELSE NULL
        END AS adjustment_amount,
        CASE
            WHEN sal.dt_started = sal.dt_salary_original_started
            THEN sal.adjustment_percent
            ELSE NULL
        END AS adjustment_percent,
        sal.is_salary_approved,
        sal.dt_started,
        sal.dt_ended,
        ed.id_event_definition,
        ed.action_code,
        ed.reason_code,
        sal.sk_job_version,
        sal.target_plr,
        sal.target_plr_salary_multiplier,
        sal.target_plr_currency_code,
        sal.target_rvv,
        sal.target_sop,
        sal.target_hiring_sop,
        sal.target_exceptional_bonus
    FROM
        salary_with_plr_target AS sal
    LEFT JOIN
        datalake_people.event_definition AS ed
            ON sal.dt_started = sal.dt_salary_original_started
            AND sal.id_action = ed.id_action
            AND sal.id_action_reason = ed.id_reason
),
salary_consolidation_base AS (
    -- Normalise NULL dt_ended to 9999-12-31 (People open-ended sentinel) so that
    -- the gaps-and-islands in salary_consolidation_groups can compare dates uniformly.
    SELECT
        id_salary,
        id_person,
        id_assignment,
        id_period_of_service,
        id_continuous_employment_cycle,
        id_job,
        person_number,
        assignment_number,
        dt_employee_hired,
        currency_code,
        salary_amount,
        annual_salary,
        adjustment_amount,
        adjustment_percent,
        is_salary_approved,
        dt_started,
        COALESCE(dt_ended, DATE('9999-12-31')) AS dt_ended_normalized,
        id_event_definition,
        action_code,
        reason_code,
        sk_job_version,
        target_plr,
        target_plr_salary_multiplier,
        target_plr_currency_code,
        target_rvv,
        target_sop,
        target_hiring_sop,
        target_exceptional_bonus
    FROM
        salary_enriched
    WHERE
        dt_started <= COALESCE(dt_ended, DATE('9999-12-31'))
),
salary_consolidation_groups AS (
    -- Detect consecutive rows that are identical in every compensation attribute.
    -- Such rows are artefacts of the job/job-version splits above and should be merged.
    -- A new group starts when any attribute changes or there is a date gap.
    -- The <=> operator handles NULL-safe equality (NULL <=> NULL is TRUE).
    SELECT
        *,
        SUM(
            CASE
                WHEN LAG(id_person) OVER (
                    PARTITION BY id_person, id_assignment, id_period_of_service
                    ORDER BY dt_started, dt_ended_normalized
                ) IS NULL
                    OR NOT (LAG(id_job) OVER (
                        PARTITION BY id_person, id_assignment, id_period_of_service
                        ORDER BY dt_started, dt_ended_normalized
                    ) <=> id_job)
                    OR NOT (LAG(currency_code) OVER (
                        PARTITION BY id_person, id_assignment, id_period_of_service
                        ORDER BY dt_started, dt_ended_normalized
                    ) <=> currency_code)
                    OR NOT (LAG(salary_amount) OVER (
                        PARTITION BY id_person, id_assignment, id_period_of_service
                        ORDER BY dt_started, dt_ended_normalized
                    ) <=> salary_amount)
                    OR NOT (LAG(annual_salary) OVER (
                        PARTITION BY id_person, id_assignment, id_period_of_service
                        ORDER BY dt_started, dt_ended_normalized
                    ) <=> annual_salary)
                    OR NOT (LAG(adjustment_amount) OVER (
                        PARTITION BY id_person, id_assignment, id_period_of_service
                        ORDER BY dt_started, dt_ended_normalized
                    ) <=> adjustment_amount)
                    OR NOT (LAG(adjustment_percent) OVER (
                        PARTITION BY id_person, id_assignment, id_period_of_service
                        ORDER BY dt_started, dt_ended_normalized
                    ) <=> adjustment_percent)
                    OR NOT (LAG(is_salary_approved) OVER (
                        PARTITION BY id_person, id_assignment, id_period_of_service
                        ORDER BY dt_started, dt_ended_normalized
                    ) <=> is_salary_approved)
                    OR NOT (LAG(id_event_definition) OVER (
                        PARTITION BY id_person, id_assignment, id_period_of_service
                        ORDER BY dt_started, dt_ended_normalized
                    ) <=> id_event_definition)
                    OR NOT (LAG(sk_job_version) OVER (
                        PARTITION BY id_person, id_assignment, id_period_of_service
                        ORDER BY dt_started, dt_ended_normalized
                    ) <=> sk_job_version)
                    OR NOT (LAG(target_plr) OVER (
                        PARTITION BY id_person, id_assignment, id_period_of_service
                        ORDER BY dt_started, dt_ended_normalized
                    ) <=> target_plr)
                    OR NOT (LAG(target_plr_salary_multiplier) OVER (
                        PARTITION BY id_person, id_assignment, id_period_of_service
                        ORDER BY dt_started, dt_ended_normalized
                    ) <=> target_plr_salary_multiplier)
                    OR NOT (LAG(target_plr_currency_code) OVER (
                        PARTITION BY id_person, id_assignment, id_period_of_service
                        ORDER BY dt_started, dt_ended_normalized
                    ) <=> target_plr_currency_code)
                    OR NOT (LAG(target_rvv) OVER (
                        PARTITION BY id_person, id_assignment, id_period_of_service
                        ORDER BY dt_started, dt_ended_normalized
                    ) <=> target_rvv)
                    OR NOT (LAG(target_sop) OVER (
                        PARTITION BY id_person, id_assignment, id_period_of_service
                        ORDER BY dt_started, dt_ended_normalized
                    ) <=> target_sop)
                    OR NOT (LAG(target_hiring_sop) OVER (
                        PARTITION BY id_person, id_assignment, id_period_of_service
                        ORDER BY dt_started, dt_ended_normalized
                    ) <=> target_hiring_sop)
                    OR NOT (LAG(target_exceptional_bonus) OVER (
                        PARTITION BY id_person, id_assignment, id_period_of_service
                        ORDER BY dt_started, dt_ended_normalized
                    ) <=> target_exceptional_bonus)
                    OR LAG(dt_ended_normalized) OVER (
                        PARTITION BY id_person, id_assignment, id_period_of_service
                        ORDER BY dt_started, dt_ended_normalized
                    ) < DATE_ADD(dt_started, -1)
                THEN 1
                ELSE 0
            END
        ) OVER (
            PARTITION BY id_person, id_assignment, id_period_of_service
            ORDER BY dt_started, dt_ended_normalized
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS change_group
    FROM
        salary_consolidation_base
),
salary_consolidated AS (
    SELECT
        MIN(id_salary) AS id_salary,
        id_person,
        id_assignment,
        id_period_of_service,
        id_continuous_employment_cycle,
        id_job,
        MAX(person_number) AS person_number,
        MAX(assignment_number) AS assignment_number,
        MAX(dt_employee_hired) AS dt_employee_hired,
        currency_code,
        salary_amount,
        annual_salary,
        adjustment_amount,
        adjustment_percent,
        is_salary_approved,
        MIN(dt_started) AS dt_started,
        MAX(dt_ended_normalized) AS dt_ended_normalized,
        id_event_definition,
        MAX(action_code) AS action_code,
        MAX(reason_code) AS reason_code,
        sk_job_version,
        target_plr,
        target_plr_salary_multiplier,
        target_plr_currency_code,
        target_rvv,
        target_sop,
        target_hiring_sop,
        target_exceptional_bonus
    FROM
        salary_consolidation_groups
    GROUP BY
        id_person,
        id_assignment,
        id_period_of_service,
        id_continuous_employment_cycle,
        id_job,
        currency_code,
        salary_amount,
        annual_salary,
        adjustment_amount,
        adjustment_percent,
        is_salary_approved,
        id_event_definition,
        sk_job_version,
        target_plr,
        target_plr_salary_multiplier,
        target_plr_currency_code,
        target_rvv,
        target_sop,
        target_hiring_sop,
        target_exceptional_bonus,
        change_group
),
salary_with_reference AS (
    -- dt_reference is the effective date used to measure tenure for each row.
    -- For open records (dt_ended_normalized = 9999-12-31) it is DATE('{load_start_date}').
    -- For closed historical records it is the last day of validity (dt_valid_to),
    -- so tenure reflects the employee's state at the end of that salary period.
    SELECT
        sal.*,
        LEAST(
            DATE('{load_start_date}'),
            COALESCE(NULLIF(sal.dt_ended_normalized, DATE('9999-12-31')), DATE('{load_start_date}'))
        ) AS dt_reference
    FROM
        salary_consolidated AS sal
)
SELECT
    -- Surrogate key — identical formula to the legacy dw_compensation.fact_compensations.sk_compensation,
    -- so it can be used as an equality-join FK from any consumer (e.g. fact_assignment_snapshots).
    MD5(CONCAT_WS('|',
        CAST(sal.id_salary AS STRING),
        CAST(sal.id_assignment AS STRING),
        COALESCE(CAST(sal.id_job AS STRING), ''),
        CAST(sal.dt_started AS STRING),
        CAST(sal.dt_ended_normalized AS STRING)
    )) AS sk_compensation,
    -- Identifiers / foreign keys (raw; downstream facts rename to sk_employee/sk_contract/etc.)
    sal.id_salary,
    sal.id_person,
    sal.id_assignment,
    sal.id_job,
    sal.id_period_of_service,
    sal.id_continuous_employment_cycle,
    sal.person_number,
    sal.assignment_number,
    sal.sk_job_version,
    sal.id_event_definition,
    sal.action_code,
    sal.reason_code,
    -- Compensation attributes (raw values; presentation columns are derived downstream)
    sal.currency_code,
    sal.salary_amount,
    sal.annual_salary,
    sal.adjustment_amount,
    sal.adjustment_percent,
    CASE
        WHEN sal.salary_amount IS NULL
            OR jst_band.salary_range_mid IS NULL
            OR jst_band.salary_range_mid <= 0
        THEN CAST(NULL AS DECIMAL(10, 3))
        ELSE CAST(
            CAST(sal.salary_amount AS DECIMAL(18, 4))
            / CAST(jst_band.salary_range_mid AS DECIMAL(18, 4)) AS DECIMAL(10, 3)
        )
    END AS salary_midpoint_ratio,
    sal.is_salary_approved,
    sal.target_plr,
    sal.target_plr_salary_multiplier,
    sal.target_plr_currency_code,
    sal.target_rvv,
    sal.target_sop,
    sal.target_hiring_sop,
    sal.target_exceptional_bonus,
    jst_band.band,
    -- Tenure anchors: stint start dates. Consumers compute DATEDIFF/MONTHS_BETWEEN against dt_reference,
    -- so the heavy stint detection (gaps-and-islands) lives here once.
    sal.dt_employee_hired,
    jts.dt_stint_start AS dt_stint_start_position,
    bts.dt_stint_start AS dt_stint_start_band,
    sal.dt_reference,
    -- SCD Type 2 validity window: one row per consolidated compensation period.
    sal.dt_started AS dt_valid_from,
    CASE
        WHEN sal.dt_ended_normalized >= DATE('9999-12-31')
        THEN DATE('9999-12-31')
        ELSE sal.dt_ended_normalized
    END AS dt_valid_to,
    CASE
        WHEN sal.dt_started <= DATE('{load_start_date}')
            AND (sal.dt_ended_normalized >= DATE('9999-12-31') OR sal.dt_ended_normalized > DATE('{load_start_date}'))
        THEN TRUE
        ELSE FALSE
    END AS is_current,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    salary_with_reference AS sal
LEFT JOIN
    job_with_salary_table_effective AS jst_band
        ON sal.sk_job_version = jst_band.sk_job_version
LEFT JOIN
    job_tenure_start AS jts
        ON sal.id_person = jts.id_person
        AND sal.id_job = jts.id_job
        AND sal.id_continuous_employment_cycle = jts.id_continuous_employment_cycle
        AND sal.dt_reference >= jts.dt_stint_start
        AND sal.dt_reference <= jts.dt_stint_ended
LEFT JOIN
    band_tenure_start AS bts
        ON sal.id_person = bts.id_person
        AND jst_band.band = bts.band
        AND sal.id_continuous_employment_cycle = bts.id_continuous_employment_cycle
        AND sal.dt_reference >= bts.dt_stint_start
        AND sal.dt_reference <= bts.dt_stint_ended
