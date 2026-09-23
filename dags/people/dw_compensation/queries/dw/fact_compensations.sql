/*
 * fact_compensations — grain and design notes
 *
 * Thin presentation layer over the shared enrich model datalake_people.compensation_versions,
 * which owns the salary split + consolidation pipeline and computes sk_compensation. This fact
 * renames the surrogate keys, derives the business columns (salary_range, total cash, flags,
 * tenure metrics) and exposes the SCD2 validity window. sk_compensation is passed through from
 * enrich unchanged, so it stays identical to the key other facts (e.g. fact_assignment_snapshots)
 * join on — no DW depends on another DW.
 *
 * Grain: one row per approved salary record × assignment job period × job validity window
 * (unchanged — inherited from compensation_versions). See that model for the full CTE pipeline
 * (transfer-continuation, tenure anchors, PLR target sourcing, consolidation).
 */
SELECT
    -- Priority 0: SKs
    cv.sk_compensation,
    cv.id_person AS sk_employee,
    cv.id_assignment AS sk_contract,
    cv.sk_job_version AS sk_job_version,
    cv.id_event_definition AS sk_event_definition,
    -- Non-SKs
    cv.person_number,
    cv.assignment_number,
    -- Non-metrics
    cv.currency_code,
    cv.target_plr_currency_code AS plr_target_currency_code,
    CASE
        WHEN cv.salary_amount IS NULL OR cv.currency_code IS NULL OR cv.currency_code <> 'BRL'
            THEN '-1'
        WHEN cv.salary_amount < 3000
            THEN 'Below R$3,000'
        WHEN cv.salary_amount < 5000
            THEN 'R$3,000 - R$4,999'
        WHEN cv.salary_amount < 8000
            THEN 'R$5,000 - R$7,999'
        WHEN cv.salary_amount < 12000
            THEN 'R$8,000 - R$11,999'
        WHEN cv.salary_amount < 20000
            THEN 'R$12,000 - R$19,999'
        ELSE
            'R$20,000+'
    END AS salary_range,
    -- Metrics - Salary fields
    cv.salary_amount AS amount_salary,
    cv.annual_salary AS amount_annual_salary,
    CAST(
        cv.annual_salary
        + COALESCE(cv.salary_amount * cv.target_plr_salary_multiplier, 0)
        + COALESCE(cv.target_plr, 0)
    AS DECIMAL(18, 2)) AS amount_total_cash,
    cv.adjustment_amount AS amount_adjustment,
    cv.adjustment_percent AS pct_adjustment,
    -- Metrics - Salary positioning
    cv.salary_midpoint_ratio,
    -- Metrics - Flags
    cv.is_salary_approved,
    CASE
        WHEN cv.reason_code = 'CMP_PROM'
        THEN TRUE
        ELSE FALSE
    END AS is_promotion_movement,
    CASE
        WHEN cv.currency_code = 'BRL' AND cv.salary_amount IS NOT NULL
            THEN cv.salary_amount < 10000
    END AS is_eligible_internet_reimbursement,
    -- Metrics - Tenure (reference date = LEAST(CURRENT_DATE, dt_valid_to); current stint for band/job)
    DATEDIFF(cv.dt_reference, cv.dt_employee_hired) AS days_tenure_in_company,
    DATEDIFF(cv.dt_reference, cv.dt_stint_start_position) AS days_tenure_in_position,
    DATEDIFF(cv.dt_reference, cv.dt_stint_start_band) AS days_tenure_in_band,
    FLOOR(MONTHS_BETWEEN(cv.dt_reference, cv.dt_employee_hired)) AS months_tenure_in_company,
    FLOOR(MONTHS_BETWEEN(cv.dt_reference, cv.dt_stint_start_position)) AS months_tenure_in_position,
    FLOOR(MONTHS_BETWEEN(cv.dt_reference, cv.dt_stint_start_band)) AS months_tenure_in_band,
    -- SCD Type 2 fields
    cv.dt_valid_from,
    cv.dt_valid_to,
    cv.is_current,
    -- Timestamp type
    NOW() AS ts_load
FROM
    datalake_people.compensation_versions AS cv
