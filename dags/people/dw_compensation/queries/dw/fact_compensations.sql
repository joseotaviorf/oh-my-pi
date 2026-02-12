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
        datalake_employee_registration.identifier_mapping AS im
            ON sal.id_assignment = im.id_assignment
    WHERE
        sal.is_salary_approved = TRUE
        AND sal.dt_started <= CURRENT_DATE
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
        dim_job.sk_job_version,
        dim_job.target_plr,
        dim_job.target_plr_salary_multiplier,
        dim_job.target_rvv,
        dim_job.target_sop,
        dim_job.target_hiring_sop,
        dim_job.target_exceptional_bonus,
        CASE
            WHEN ed.action_code = 'PROMOTION'
            THEN TRUE
            ELSE FALSE
        END AS is_promotion_movement
    FROM
        salary_with_person AS sal
    LEFT JOIN
        datalake_people_core.event_definition AS ed
            ON sal.id_action = ed.id_action
            AND sal.id_action_reason = ed.id_reason
    LEFT JOIN
        dw_compensation.dim_job AS dim_job
            ON sal.id_job = dim_job.id_job
            AND dim_job.dt_valid_from <= sal.dt_started
            AND (dim_job.dt_valid_to IS NULL OR dim_job.dt_valid_to > sal.dt_started)
)
SELECT
    -- Priority 0: SKs
    MD5(CONCAT_WS('|',
        CAST(sal.id_salary AS STRING),
        CAST(sal.dt_started AS STRING)
    )) AS sk_compensation,
    sal.id_person AS sk_employee,
    sal.id_period_of_service AS sk_assignment,
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
    sal.compa_ratio,
    sal.range_position,
    -- Metrics - Flags
    sal.is_salary_approved,
    sal.is_promotion_movement,
    -- SCD Type 2 fields
    sal.dt_started AS dt_valid_from,
    CASE
        WHEN sal.dt_ended IS NULL OR sal.dt_ended >= DATE('4712-12-31')
        THEN NULL
        ELSE sal.dt_ended
    END AS dt_valid_to,
    CASE
        WHEN sal.dt_started <= CURRENT_DATE
            AND (sal.dt_ended IS NULL OR sal.dt_ended >= DATE('4712-12-31') OR sal.dt_ended > CURRENT_DATE)
        THEN TRUE
        ELSE FALSE
    END AS is_current,
    -- Timestamp type
    NOW() AS ts_load
FROM
    salary_enriched AS sal
