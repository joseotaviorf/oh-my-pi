-- Active employee roster with Performa score and Talent Review pivots for the Talent Review Looker dashboard (base tab).
WITH
talent_review_q1_26 AS (
    SELECT
        tr.person_number,
        MAX(dtr.potential) AS tr_q1_26_potential,
        MAX(dtr.readiness) AS tr_q1_26_readiness,
        MAX(dtr.criticality) AS tr_q1_26_criticality,
        MAX(dtr.risk_of_loss) AS tr_q1_26_risk_of_loss
    FROM
        dw_performance.fact_talent_reviews AS tr
    INNER JOIN
        dw_performance.dim_cycle_period AS dcp
            ON dcp.sk_cycle_period = tr.sk_cycle_period
            AND dcp.cycle_name = 'Talent Review 2026 Q1'
    LEFT JOIN
        dw_performance.dim_talent_rating AS dtr
            ON dtr.sk_talent_rating = tr.sk_talent_rating_from_calibration
    WHERE
        tr.is_latest_for_employee_in_cycle = TRUE
    GROUP BY
        tr.person_number
),
talent_review_q3_25 AS (
    SELECT
        tr.person_number,
        MAX(dtr.potential) AS tr_q3_25_potential,
        MAX(dtr.readiness) AS tr_q3_25_readiness,
        MAX(dtr.criticality) AS tr_q3_25_criticality,
        MAX(dtr.risk_of_loss) AS tr_q3_25_risk_of_loss
    FROM
        dw_performance.fact_talent_reviews AS tr
    INNER JOIN
        dw_performance.dim_cycle_period AS dcp
            ON dcp.sk_cycle_period = tr.sk_cycle_period
            AND dcp.cycle_name = 'Talent Review 2025 H2'
    LEFT JOIN
        dw_performance.dim_talent_rating AS dtr
            ON dtr.sk_talent_rating = tr.sk_talent_rating_from_calibration
    WHERE
        tr.is_latest_for_employee_in_cycle = TRUE
    GROUP BY
        tr.person_number
),
talent_review_q1_25 AS (
    SELECT
        tr.person_number,
        MAX(dtr.potential) AS tr_q1_25_potential,
        MAX(dtr.readiness) AS tr_q1_25_readiness,
        MAX(dtr.criticality) AS tr_q1_25_criticality,
        MAX(dtr.risk_of_loss) AS tr_q1_25_risk_of_loss
    FROM
        dw_performance.fact_talent_reviews AS tr
    INNER JOIN
        dw_performance.dim_cycle_period AS dcp
            ON dcp.sk_cycle_period = tr.sk_cycle_period
            AND dcp.cycle_name = 'Talent Review 2025 H1'
    LEFT JOIN
        dw_performance.dim_talent_rating AS dtr
            ON dtr.sk_talent_rating = tr.sk_talent_rating_from_calibration
    WHERE
        tr.is_latest_for_employee_in_cycle = TRUE
    GROUP BY
        tr.person_number
),
last_raise AS (
    SELECT
        fc.dt_valid_from AS last_raise_date,
        ed.reason_name_ptb AS last_raise_reason,
        fc.sk_employee,
        ROW_NUMBER() OVER (
            PARTITION BY fc.sk_employee
            ORDER BY fc.dt_valid_from DESC
        ) AS ranking_last_raise
    FROM
        dw_compensation.fact_compensations AS fc
    INNER JOIN
        dw_compensation.dim_event_definition AS ed
            ON fc.sk_event_definition = ed.sk_event_definition
    WHERE
        ed.reason_name_ptb IN ('Mérito', 'Promoção')
        AND fc.dt_valid_from <= DATE('{load_start_date}')
),
latest_performa_score AS (
    SELECT
        fpc.person_number,
        fpc.performa_score
    FROM
        dw_performance.fact_performance_calibrations AS fpc
    INNER JOIN
        dw_performance.dim_cycle_period AS dcp
            ON dcp.sk_cycle_period = fpc.sk_cycle_period
            AND dcp.meeting_type = 'performance_calibration'
            AND dcp.is_current = TRUE
)
SELECT
    fact.assignment_number,
    emp.name,
    emp.work_email,
    job.job_name,
    COALESCE(TRY_CAST(job.band AS INT), 1) AS band,
    fc.months_tenure_in_position,
    fc.months_tenure_in_band,
    fc.months_tenure_in_company,
    fc.months_tenure_in_position AS months_tenure_in_position_years,
    fc.months_tenure_in_band AS months_tenure_in_band_years,
    fc.months_tenure_in_company AS months_tenure_in_company_years,
    hier.manager_assignment_number,
    man_emp.name AS manager_name,
    lr.last_raise_date,
    lr.last_raise_reason,
    pr.performa_score,
    cc.team,
    cc.vertical,
    es.country,
    fact.is_manager,
    fs.assignment_number AS hrbp_assignment_number,
    cc.hrbp_name,
    hier.assignment_number_l1,
    hier.name_l1 AS l1_name,
    hier.assignment_number_l2,
    hier.name_l2 AS l2_name,
    hier.assignment_number_l3,
    hier.name_l3 AS l3_name,
    hier.assignment_number_l4,
    hier.name_l4 AS l4_name,
    CASE
        WHEN COALESCE(TRY_CAST(job.band AS INT), 1) >= 6
            AND fc.months_tenure_in_company >= 3
        THEN 'Sim'
        ELSE 'Não'
    END AS elegivel,
    tr_q1_26.tr_q1_26_potential,
    tr_q1_26.tr_q1_26_readiness,
    tr_q1_26.tr_q1_26_criticality,
    tr_q1_26.tr_q1_26_risk_of_loss,
    tr_q3_25.tr_q3_25_potential,
    tr_q3_25.tr_q3_25_readiness,
    tr_q3_25.tr_q3_25_criticality,
    tr_q3_25.tr_q3_25_risk_of_loss,
    tr_q1_25.tr_q1_25_potential,
    tr_q1_25.tr_q1_25_readiness,
    tr_q1_25.tr_q1_25_criticality,
    tr_q1_25.tr_q1_25_risk_of_loss,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    dw_employee_details.fact_assignment_snapshots AS fact
INNER JOIN
    dw_employee_details.dim_employee AS emp
        ON fact.sk_employee = emp.sk_employee
LEFT JOIN
    dw_employee_details.dim_management_hierarchy AS hier
        ON fact.sk_hierarchy_version = hier.sk_hierarchy_version
LEFT JOIN
    dw_compensation.dim_job AS job
        ON fact.sk_job_version = job.sk_job_version
LEFT JOIN
    last_raise AS lr
        ON fact.sk_employee = lr.sk_employee
        AND lr.ranking_last_raise = 1
LEFT JOIN
    latest_performa_score AS pr
        ON fact.person_number = pr.person_number
LEFT JOIN
    dw_organization.dim_cost_center AS cc
        ON fact.sk_cost_center_version = cc.sk_cost_center_version
LEFT JOIN
    talent_review_q1_26 AS tr_q1_26
        ON tr_q1_26.person_number = fact.person_number
LEFT JOIN
    talent_review_q3_25 AS tr_q3_25
        ON tr_q3_25.person_number = fact.person_number
LEFT JOIN
    talent_review_q1_25 AS tr_q1_25
        ON tr_q1_25.person_number = fact.person_number
LEFT JOIN
    dw_compensation.fact_compensations AS fc
        ON fc.sk_compensation = fact.sk_compensation_version
        AND fact.sk_compensation_version <> '-1'
LEFT JOIN
    metric_people.employee_snapshots AS es
        ON fact.sk_employee = es.sk_employee
        AND es.is_current_for_employee = TRUE
        AND es.is_primary_assignment_for_snapshot = TRUE
LEFT JOIN
    dw_employee_details.fact_assignment_snapshots AS fs
        ON cc.sk_business_partner = fs.sk_employee
        AND fs.is_current_for_employee = TRUE
LEFT JOIN
    dw_employee_details.fact_assignment_snapshots AS man_fas
        ON man_fas.assignment_number = hier.manager_assignment_number
        AND man_fas.is_current_for_assignment = TRUE
LEFT JOIN
    dw_employee_details.dim_employee AS man_emp
        ON man_emp.sk_employee = man_fas.sk_employee
WHERE
    fact.is_current_for_employee = TRUE
    AND fact.is_active = TRUE
    AND fact.employment_status = 'Active'
