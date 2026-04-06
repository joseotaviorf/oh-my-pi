WITH salary_with_person AS (
    SELECT
        sal.id_salary,
        sal.id_person,
        sal.id_assignment,
        sal.id_job,
        sal.id_action,
        sal.id_action_reason,
        sal.id_action_occurrence,
        im.id_period_of_service,
        im.person_number,
        im.assignment_number,
        sal.currency_code,
        sal.salary_amount,
        sal.annual_salary,
        sal.adjustment_amount,
        sal.adjustment_percent,
        sal.compa_ratio,
        sal.range_position,
        sal.is_salary_approved,
        sal.dt_started,
        sal.dt_ended
    FROM
        datalake_pin_compensation_clean.salary AS sal
    INNER JOIN
        datalake_people.identifier_mapping AS im
            ON sal.id_assignment = im.id_assignment
    WHERE
        sal.is_salary_approved = TRUE
        AND sal.dt_started <= CURRENT_DATE
),
assignment_history_base AS (
    SELECT
        id_assignment,
        id_job,
        dt_effective_started,
        dt_effective_ended
    FROM
        datalake_pin_core_clean.all_assignments
    WHERE
        id_job IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                id_assignment,
                dt_effective_started,
                dt_effective_ended
            ORDER BY
                effective_sequence DESC,
                object_version_number DESC
        ) = 1
),
assignment_job_groups AS (
    SELECT
        id_assignment,
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
    SELECT
        id_assignment,
        id_job,
        MIN(dt_effective_started) AS dt_effective_started,
        MAX(dt_effective_ended) AS dt_effective_ended
    FROM
        assignment_job_groups
    GROUP BY
        id_assignment,
        id_job,
        change_group
),
assignment_history_with_band AS (
    SELECT
        ah.id_assignment,
        ah.id_job,
        ah.dt_effective_started,
        ah.dt_effective_ended,
        dj.band
    FROM
        assignment_history AS ah
    INNER JOIN
        dw_compensation.dim_job AS dj
            ON ah.id_job = dj.id_job
            AND dj.dt_valid_from <= ah.dt_effective_started
            AND dj.dt_valid_to > ah.dt_effective_started
    WHERE
        dj.band IS NOT NULL
),
assignment_band_stint_groups AS (
    SELECT
        id_assignment,
        band,
        dt_effective_started,
        dt_effective_ended,
        SUM(
            CASE
                WHEN LAG(dt_effective_ended) OVER (
                    PARTITION BY id_assignment, band
                    ORDER BY dt_effective_started, dt_effective_ended
                ) < DATE_ADD(dt_effective_started, -1)
                    OR LAG(dt_effective_ended) OVER (
                        PARTITION BY id_assignment, band
                        ORDER BY dt_effective_started, dt_effective_ended
                    ) IS NULL
                THEN 1
                ELSE 0
            END
        ) OVER (
            PARTITION BY id_assignment, band
            ORDER BY dt_effective_started, dt_effective_ended
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS stint_group
    FROM
        assignment_history_with_band
),
assignment_band_stints AS (
    SELECT
        id_assignment,
        band,
        MIN(dt_effective_started) AS dt_stint_start,
        MAX(dt_effective_ended) AS dt_stint_ended
    FROM
        assignment_band_stint_groups
    GROUP BY
        id_assignment,
        band,
        stint_group
),
assignment_job_stint_groups AS (
    SELECT
        id_assignment,
        id_job,
        dt_effective_started,
        dt_effective_ended,
        SUM(
            CASE
                WHEN LAG(dt_effective_ended) OVER (
                    PARTITION BY id_assignment, id_job
                    ORDER BY dt_effective_started, dt_effective_ended
                ) < DATE_ADD(dt_effective_started, -1)
                    OR LAG(dt_effective_ended) OVER (
                        PARTITION BY id_assignment, id_job
                        ORDER BY dt_effective_started, dt_effective_ended
                    ) IS NULL
                THEN 1
                ELSE 0
            END
        ) OVER (
            PARTITION BY id_assignment, id_job
            ORDER BY dt_effective_started, dt_effective_ended
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS stint_group
    FROM
        assignment_history
),
assignment_job_stints AS (
    SELECT
        id_assignment,
        id_job,
        MIN(dt_effective_started) AS dt_stint_start,
        MAX(dt_effective_ended) AS dt_stint_ended
    FROM
        assignment_job_stint_groups
    GROUP BY
        id_assignment,
        id_job,
        stint_group
),
terminated_for_transfer AS (
    SELECT
        aa_next.id_period_of_service AS id_period_of_service_next,
        ps_prev.dt_started AS previous_dt_started
    FROM
        datalake_pin_core_clean.all_assignments AS aa
    INNER JOIN
        datalake_pin_core_clean.all_assignments AS aa_next
            ON aa_next.id_person = aa.id_person
            AND aa_next.assignment_sequence = aa.assignment_sequence + 1
    LEFT JOIN
        datalake_pin_core_clean.periods_of_service AS ps_prev
            ON ps_prev.id_period_of_service = aa.id_period_of_service
    WHERE
        aa.assignment_status_type = 'INACTIVE'
        AND aa.action_code = 'GLB_TRANSFER'
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY aa.id_period_of_service
            ORDER BY aa.dt_effective_started ASC
        ) = 1
),
assignment_admission_started AS (
    SELECT
        im.id_assignment,
        COALESCE(tft.previous_dt_started, im.dt_started) AS dt_admission_started
    FROM
        datalake_people.identifier_mapping AS im
    LEFT JOIN
        terminated_for_transfer AS tft
            ON tft.id_period_of_service_next = im.id_period_of_service
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY im.id_assignment ORDER BY im.dt_started) = 1
),
salary_with_assignment_job AS (
    -- Split salary periods by assignment job changes
    SELECT
        sal.id_salary,
        sal.id_person,
        sal.id_assignment,
        sal.id_period_of_service,
        sal.person_number,
        sal.assignment_number,
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
salary_enriched AS (
    SELECT
        sal.id_salary,
        sal.id_person,
        sal.id_assignment,
        sal.id_period_of_service,
        sal.id_job,
        sal.person_number,
        sal.assignment_number,
        sal.currency_code,
        sal.salary_amount,
        sal.annual_salary,
        sal.adjustment_amount,
        sal.adjustment_percent,
        sal.compa_ratio,
        sal.range_position,
        sal.is_salary_approved,
        sal.dt_started,
        sal.dt_ended,
        ed.id_event_definition,
        ed.action_code,
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
        datalake_people.event_definition AS ed
            ON sal.id_action = ed.id_action
            AND sal.id_action_reason = ed.id_reason
    LEFT JOIN
        dw_compensation.dim_job AS dj
            ON sal.id_job = dj.id_job
            AND dj.dt_valid_from <= sal.dt_started
            AND dj.dt_valid_to > sal.dt_started
),
salary_consolidation_base AS (
    SELECT
        id_salary,
        id_person,
        id_assignment,
        id_period_of_service,
        id_job,
        person_number,
        assignment_number,
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
        id_job,
        MAX(person_number) AS person_number,
        MAX(assignment_number) AS assignment_number,
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
        WHEN sal.action_code = 'PROMOTION'
        THEN TRUE
        ELSE FALSE
    END AS is_promotion_movement,
    -- Metrics - Tenure (reference date = LEAST(CURRENT_DATE, dt_valid_to); current stint for band/job)
    DATEDIFF(sal.dt_reference, pos.dt_admission_started) AS days_tenure_in_company,
    DATEDIFF(sal.dt_reference, ajst.dt_stint_start) AS days_tenure_in_position,
    DATEDIFF(sal.dt_reference, abst.dt_stint_start) AS days_tenure_in_band,
    FLOOR(MONTHS_BETWEEN(sal.dt_reference, pos.dt_admission_started)) AS months_tenure_in_company,
    FLOOR(MONTHS_BETWEEN(sal.dt_reference, ajst.dt_stint_start)) AS months_tenure_in_position,
    FLOOR(MONTHS_BETWEEN(sal.dt_reference, abst.dt_stint_start)) AS months_tenure_in_band,
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
    assignment_admission_started AS pos
        ON sal.id_assignment = pos.id_assignment
LEFT JOIN
    dw_compensation.dim_job AS dj_band
        ON sal.sk_job_version = dj_band.sk_job_version
LEFT JOIN
    assignment_job_stints AS ajst
        ON sal.id_assignment = ajst.id_assignment
        AND sal.id_job = ajst.id_job
        AND sal.dt_reference >= ajst.dt_stint_start
        AND sal.dt_reference <= ajst.dt_stint_ended
LEFT JOIN
    assignment_band_stints AS abst
        ON sal.id_assignment = abst.id_assignment
        AND dj_band.band = abst.band
        AND sal.dt_reference >= abst.dt_stint_start
        AND sal.dt_reference <= abst.dt_stint_ended
