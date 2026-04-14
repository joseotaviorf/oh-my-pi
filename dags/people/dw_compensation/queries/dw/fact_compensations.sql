/*
 * fact_compensations — grain and design notes
 *
 * Grain: one row per approved salary record × assignment job period × dim_job validity window.
 * A single salary entry can produce multiple rows when the employee's job changes mid-salary
 * or when dim_job receives a new SCD2 version while the salary is still open.
 *
 * Transfer-continuation:
 *   All GLB_TRANSFER continuity logic lives in datalake_people.identifier_mapping.
 *   id_continuous_employment_cycle groups every assignment that belongs to the same
 *   uninterrupted employment spell; it resets only on true rehire.
 *   No transfer logic is reimplemented here.
 *
 * Tenure anchors:
 *   - Company : dt_original_hired from identifier_mapping (respects transfer continuity).
 *   - Position: start of the current job stint within the cycle (gaps-and-islands on id_job).
 *               A→B→A returns a stint from the return date, not the original start.
 *   - Band    : start of the current band stint within the cycle (gaps-and-islands on band
 *               from dim_job). Band can be < position when a job is reclassified to a
 *               different band without the employee changing roles (dim_job SCD2 update).
 *
 * CTE pipeline:
 *   [assignment chain]
 *     assignment_identifier_mapping   — one row per id_assignment with its cycle id
 *     assignment_history_base         — all_assignments deduplicated per (assignment, date range)
 *     assignment_job_groups           — detect job changes within an assignment (gaps-and-islands)
 *     assignment_history              — one row per continuous job period per assignment
 *     assignment_history_with_band    — enrich assignment history with band from dim_job
 *     assignment_job_stint_groups     — detect job change across assignments within same cycle
 *     job_tenure_start                — one row per (person, cycle, job, stint)
 *     assignment_band_stint_groups    — detect band change across assignments within same cycle
 *     band_tenure_start               — one row per (person, cycle, band, stint)
 *
 *   [salary chain]
 *     salary_with_person              — approved salaries joined to identifier_mapping
 *     salary_with_assignment_job      — split salary periods by job changes
 *     salary_with_job_version         — split salary periods by dim_job SCD2 windows
 *     salary_enriched                 — attach event_definition; null adjustments on split rows
 *     salary_consolidation_base       — normalise NULL dt_ended to 4712-12-31
 *     salary_consolidation_groups     — detect consecutive identical salary records (gaps-and-islands)
 *     salary_consolidated             — collapse identical consecutive records into one row
 *     salary_with_reference           — add dt_reference = LEAST(CURRENT_DATE, dt_valid_to)
 */
WITH salary_with_person AS (
    -- Approved salaries enriched with person identifiers and cycle metadata from identifier_mapping.
    -- dt_original_hired is the hire date for the current continuous employment cycle;
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
        im.dt_original_hired,
        sal.currency_code,
        sal.salary_amount,
        sal.annual_salary,
        sal.adjustment_amount,
        sal.adjustment_percent,
        sal.compa_ratio,
        sal.range_position,
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
        AND sal.dt_started <= CURRENT_DATE
        AND im.assignment_number NOT LIKE 'P%'
),
assignment_identifier_mapping AS (
    -- Stable mapping from id_assignment to id_continuous_employment_cycle.
    -- QUALIFY picks the earliest dt_started in case an assignment appears in multiple
    -- identifier_mapping rows (edge case from partial loads).
    SELECT
        id_assignment,
        id_continuous_employment_cycle
    FROM
        datalake_people.identifier_mapping
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY id_assignment
            ORDER BY dt_started ASC
        ) = 1
),
assignment_history_base AS (
    -- Deduplicated assignment history: one row per (assignment, effective date range),
    -- keeping the highest effective_sequence / object_version_number to resolve Oracle
    -- correction rows that share the same date range.
    SELECT
        aa.id_person,
        aa.id_assignment,
        aa.id_job,
        aa.dt_effective_started,
        aa.dt_effective_ended,
        im.id_continuous_employment_cycle
    FROM
        datalake_pin_core_clean.all_assignments AS aa
    LEFT JOIN
        assignment_identifier_mapping AS im
            ON aa.id_assignment = im.id_assignment
    WHERE
        aa.id_job IS NOT NULL
        AND aa.assignment_number NOT LIKE 'P%'
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                aa.id_assignment,
                aa.dt_effective_started,
                aa.dt_effective_ended
            ORDER BY
                aa.effective_sequence DESC,
                aa.object_version_number DESC
        ) = 1
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
assignment_history_with_band AS (
    -- Enrich assignment history with the band from dim_job (SCD2).
    -- Intersect date ranges so that a job reclassification (band change in dim_job without
    -- the employee moving) creates a separate period for each band version.
    -- This means band tenure can be shorter than position tenure when the job is reclassified.
    SELECT
        ah.id_person,
        ah.id_continuous_employment_cycle,
        GREATEST(ah.dt_effective_started, dj.dt_valid_from) AS dt_effective_started,
        LEAST(ah.dt_effective_ended, dj.dt_valid_to) AS dt_effective_ended,
        dj.band
    FROM
        assignment_history AS ah
    INNER JOIN
        dw_compensation.dim_job AS dj
            ON ah.id_job = dj.id_job
            AND dj.dt_valid_from <= ah.dt_effective_ended
            AND dj.dt_valid_to >= ah.dt_effective_started
    WHERE
        dj.band IS NOT NULL
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
                WHEN LAG(dt_effective_ended) OVER (
                    PARTITION BY id_person, id_continuous_employment_cycle, id_job
                    ORDER BY dt_effective_started, dt_effective_ended
                ) < DATE_ADD(dt_effective_started, -1)
                    OR LAG(dt_effective_ended) OVER (
                        PARTITION BY id_person, id_continuous_employment_cycle, id_job
                        ORDER BY dt_effective_started, dt_effective_ended
                    ) IS NULL
                THEN 1
                ELSE 0
            END
        ) OVER (
            PARTITION BY id_person, id_continuous_employment_cycle, id_job
            ORDER BY dt_effective_started, dt_effective_ended
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS stint_group
    FROM
        assignment_history
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
                WHEN LAG(dt_effective_ended) OVER (
                    PARTITION BY id_person, id_continuous_employment_cycle, band
                    ORDER BY dt_effective_started, dt_effective_ended
                ) < DATE_ADD(dt_effective_started, -1)
                    OR LAG(dt_effective_ended) OVER (
                        PARTITION BY id_person, id_continuous_employment_cycle, band
                        ORDER BY dt_effective_started, dt_effective_ended
                    ) IS NULL
                THEN 1
                ELSE 0
            END
        ) OVER (
            PARTITION BY id_person, id_continuous_employment_cycle, band
            ORDER BY dt_effective_started, dt_effective_ended
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS stint_group
    FROM
        assignment_history_with_band
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
        sal.dt_original_hired,
        sal.currency_code,
        sal.salary_amount,
        sal.annual_salary,
        sal.adjustment_amount,
        sal.adjustment_percent,
        sal.compa_ratio,
        sal.range_position,
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
                COALESCE(sal.dt_ended, DATE('4712-12-31')),
                assignment_history.dt_effective_ended
            )
        END AS dt_ended
    FROM
        salary_with_person AS sal
    LEFT JOIN
        assignment_history AS assignment_history
            ON assignment_history.id_assignment = sal.id_assignment
            AND assignment_history.dt_effective_started <= COALESCE(sal.dt_ended, DATE('4712-12-31'))
            AND assignment_history.dt_effective_ended > sal.dt_started
),
salary_with_job_version AS (
    -- Split salary periods by dim_job validity windows to keep current job-version attributes.
    -- Each dim_job SCD2 version carries its own compensation targets (PLR, RVV, SOP),
    -- so a salary open across multiple dim_job versions must be split accordingly.
    SELECT
        sal.id_salary,
        sal.id_person,
        sal.id_assignment,
        sal.id_period_of_service,
        sal.id_continuous_employment_cycle,
        sal.person_number,
        sal.assignment_number,
        sal.dt_original_hired,
        sal.currency_code,
        sal.salary_amount,
        sal.annual_salary,
        sal.adjustment_amount,
        sal.adjustment_percent,
        sal.compa_ratio,
        sal.range_position,
        sal.is_salary_approved,
        sal.id_action,
        sal.id_action_reason,
        sal.id_action_occurrence,
        sal.dt_salary_original_started,
        sal.id_job,
        CASE
            WHEN dj.sk_job_version IS NULL
            THEN sal.dt_started
            ELSE GREATEST(sal.dt_started, dj.dt_valid_from)
        END AS dt_started,
        CASE
            WHEN dj.sk_job_version IS NULL
            THEN sal.dt_ended
            ELSE LEAST(COALESCE(sal.dt_ended, DATE('4712-12-31')), dj.dt_valid_to)
        END AS dt_ended,
        dj.sk_job_version,
        dj.target_plr,
        dj.target_plr_salary_multiplier,
        dj.target_rvv,
        dj.target_sop,
        dj.target_hiring_sop,
        dj.target_exceptional_bonus
    FROM
        salary_with_assignment_job AS sal
    LEFT JOIN
        dw_compensation.dim_job AS dj
            ON sal.id_job = dj.id_job
            AND dj.dt_valid_from <= COALESCE(sal.dt_ended, DATE('4712-12-31'))
            AND dj.dt_valid_to >= sal.dt_started
),
salary_enriched AS (
    -- Attach event_definition for the salary change event.
    -- Adjustment fields are zeroed on rows that were created by a job or dim_job split
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
        sal.dt_original_hired,
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
        sal.compa_ratio,
        sal.range_position,
        sal.is_salary_approved,
        sal.dt_started,
        sal.dt_ended,
        ed.id_event_definition,
        ed.action_code,
        ed.reason_code,
        sal.sk_job_version,
        sal.target_plr,
        sal.target_plr_salary_multiplier,
        sal.target_rvv,
        sal.target_sop,
        sal.target_hiring_sop,
        sal.target_exceptional_bonus
    FROM
        salary_with_job_version AS sal
    LEFT JOIN
        datalake_people.event_definition AS ed
            ON sal.dt_started = sal.dt_salary_original_started
            AND sal.id_action = ed.id_action
            AND sal.id_action_reason = ed.id_reason
),
salary_consolidation_base AS (
    -- Normalise NULL dt_ended to 4712-12-31 (Oracle open-ended sentinel) so that
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
        dt_original_hired,
        currency_code,
        salary_amount,
        annual_salary,
        adjustment_amount,
        adjustment_percent,
        compa_ratio AS range_position,
        range_position AS range_percentile,
        is_salary_approved,
        dt_started,
        COALESCE(dt_ended, DATE('4712-12-31')) AS dt_ended_normalized,
        id_event_definition,
        action_code,
        reason_code,
        sk_job_version,
        target_plr,
        target_plr_salary_multiplier,
        target_rvv,
        target_sop,
        target_hiring_sop,
        target_exceptional_bonus
    FROM
        salary_enriched
),
salary_consolidation_groups AS (
    -- Detect consecutive rows that are identical in every compensation attribute.
    -- Such rows are artefacts of the job/dim_job splits above and should be merged.
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
                    OR NOT (LAG(range_position) OVER (
                        PARTITION BY id_person, id_assignment, id_period_of_service
                        ORDER BY dt_started, dt_ended_normalized
                    ) <=> range_position)
                    OR NOT (LAG(range_percentile) OVER (
                        PARTITION BY id_person, id_assignment, id_period_of_service
                        ORDER BY dt_started, dt_ended_normalized
                    ) <=> range_percentile)
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
        MAX(dt_original_hired) AS dt_original_hired,
        currency_code,
        salary_amount,
        annual_salary,
        adjustment_amount,
        adjustment_percent,
        range_position,
        range_percentile,
        is_salary_approved,
        MIN(dt_started) AS dt_started,
        MAX(dt_ended_normalized) AS dt_ended_normalized,
        id_event_definition,
        MAX(action_code) AS action_code,
        MAX(reason_code) AS reason_code,
        sk_job_version,
        target_plr,
        target_plr_salary_multiplier,
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
        range_position,
        range_percentile,
        is_salary_approved,
        id_event_definition,
        sk_job_version,
        target_plr,
        target_plr_salary_multiplier,
        target_rvv,
        target_sop,
        target_hiring_sop,
        target_exceptional_bonus,
        change_group
),
salary_with_reference AS (
    -- dt_reference is the effective date used to measure tenure for each row.
    -- For open records (dt_ended_normalized = 4712-12-31) it is CURRENT_DATE.
    -- For closed historical records it is the last day of validity (dt_valid_to),
    -- so tenure reflects the employee's state at the end of that salary period.
    SELECT
        sal.*,
        LEAST(
            CURRENT_DATE,
            COALESCE(NULLIF(sal.dt_ended_normalized, DATE('4712-12-31')), CURRENT_DATE)
        ) AS dt_reference
    FROM
        salary_consolidated AS sal
)
SELECT
    -- Priority 0: SKs
    MD5(CONCAT_WS('|',
        CAST(sal.id_salary AS STRING),
        CAST(sal.id_assignment AS STRING),
        COALESCE(CAST(sal.id_job AS STRING), ''),
        CAST(sal.dt_started AS STRING),
        CAST(sal.dt_ended_normalized AS STRING)
    )) AS sk_compensation,
    sal.id_person AS sk_employee,
    sal.id_assignment AS sk_contract,
    sal.sk_job_version AS sk_job_version,
    sal.id_event_definition AS sk_event_definition,
    -- Non-SKs
    sal.person_number,
    sal.assignment_number,
    -- Non-metrics
    sal.currency_code,
    -- Metrics - Salary fields
    sal.salary_amount AS amount_salary,
    sal.annual_salary AS amount_annual_salary,
    CAST(
        sal.annual_salary
        + COALESCE(sal.salary_amount * sal.target_plr_salary_multiplier, 0)
        + COALESCE(sal.target_plr, 0)
    AS DECIMAL(18, 2)) AS amount_total_cash,
    sal.adjustment_amount AS amount_adjustment,
    sal.adjustment_percent AS pct_adjustment,
    -- Metrics - Salary positioning
    sal.range_position,
    sal.range_percentile,
    -- Metrics - Flags
    sal.is_salary_approved,
    CASE
        WHEN sal.reason_code = 'CMP_PROM'
        THEN TRUE
        ELSE FALSE
    END AS is_promotion_movement,
    -- Metrics - Tenure (reference date = LEAST(CURRENT_DATE, dt_valid_to); current stint for band/job)
    DATEDIFF(sal.dt_reference, sal.dt_original_hired) AS days_tenure_in_company,
    DATEDIFF(sal.dt_reference, jts.dt_stint_start) AS days_tenure_in_position,
    DATEDIFF(sal.dt_reference, bts.dt_stint_start) AS days_tenure_in_band,
    FLOOR(MONTHS_BETWEEN(sal.dt_reference, sal.dt_original_hired)) AS months_tenure_in_company,
    FLOOR(MONTHS_BETWEEN(sal.dt_reference, jts.dt_stint_start)) AS months_tenure_in_position,
    FLOOR(MONTHS_BETWEEN(sal.dt_reference, bts.dt_stint_start)) AS months_tenure_in_band,
    -- SCD Type 2 fields
    sal.dt_started AS dt_valid_from,
    CASE
        WHEN sal.dt_ended_normalized >= DATE('4712-12-31')
        THEN DATE('9999-12-31')
        ELSE sal.dt_ended_normalized
    END AS dt_valid_to,
    CASE
        WHEN sal.dt_started <= CURRENT_DATE
            AND (sal.dt_ended_normalized >= DATE('4712-12-31') OR sal.dt_ended_normalized > CURRENT_DATE)
        THEN TRUE
        ELSE FALSE
    END AS is_current,
    -- Timestamp type
    NOW() AS ts_load
FROM
    salary_with_reference AS sal
LEFT JOIN
    dw_compensation.dim_job AS dj_band
        ON sal.sk_job_version = dj_band.sk_job_version
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
        AND dj_band.band = bts.band
        AND sal.id_continuous_employment_cycle = bts.id_continuous_employment_cycle
        AND sal.dt_reference >= bts.dt_stint_start
        AND sal.dt_reference <= bts.dt_stint_ended
