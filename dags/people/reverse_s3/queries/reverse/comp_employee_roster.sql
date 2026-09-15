-- Active-employee roster for external Comp S3 (Parquet). Subset of talent_review_performa_base;
-- omits display names and calculated fields derivable from assignment_number keys.
WITH
talent_review_q1_26_ranked AS (
    SELECT
        tr.person_number,
        dtr.potential AS tr_q1_26_potential,
        dtr.readiness AS tr_q1_26_readiness,
        dtr.criticality AS tr_q1_26_criticality,
        dtr.risk_of_loss AS tr_q1_26_risk_of_loss,
        ROW_NUMBER() OVER (
            PARTITION BY tr.person_number
            ORDER BY tr.sk_committee_meeting_date DESC
        ) AS rn
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
),
talent_review_q1_26 AS (
    SELECT
        person_number,
        tr_q1_26_potential,
        tr_q1_26_readiness,
        tr_q1_26_criticality,
        tr_q1_26_risk_of_loss
    FROM
        talent_review_q1_26_ranked
    WHERE
        rn = 1
),
talent_review_q3_25_ranked AS (
    SELECT
        tr.person_number,
        dtr.potential AS tr_q3_25_potential,
        dtr.readiness AS tr_q3_25_readiness,
        dtr.criticality AS tr_q3_25_criticality,
        dtr.risk_of_loss AS tr_q3_25_risk_of_loss,
        ROW_NUMBER() OVER (
            PARTITION BY tr.person_number
            ORDER BY tr.sk_committee_meeting_date DESC
        ) AS rn
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
),
talent_review_q3_25 AS (
    SELECT
        person_number,
        tr_q3_25_potential,
        tr_q3_25_readiness,
        tr_q3_25_criticality,
        tr_q3_25_risk_of_loss
    FROM
        talent_review_q3_25_ranked
    WHERE
        rn = 1
),
talent_review_q1_25_ranked AS (
    SELECT
        tr.person_number,
        dtr.potential AS tr_q1_25_potential,
        dtr.readiness AS tr_q1_25_readiness,
        dtr.criticality AS tr_q1_25_criticality,
        dtr.risk_of_loss AS tr_q1_25_risk_of_loss,
        ROW_NUMBER() OVER (
            PARTITION BY tr.person_number
            ORDER BY tr.sk_committee_meeting_date DESC
        ) AS rn
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
),
talent_review_q1_25 AS (
    SELECT
        person_number,
        tr_q1_25_potential,
        tr_q1_25_readiness,
        tr_q1_25_criticality,
        tr_q1_25_risk_of_loss
    FROM
        talent_review_q1_25_ranked
    WHERE
        rn = 1
),
last_raise_ranked AS (
    SELECT
        fc.dt_valid_from AS last_raise_date,
        ed.reason_name_ptb AS last_raise_reason,
        fc.sk_employee,
        ROW_NUMBER() OVER (
            PARTITION BY fc.sk_employee
            ORDER BY fc.dt_valid_from DESC
        ) AS rn
    FROM
        dw_compensation.fact_compensations AS fc
    INNER JOIN
        dw_compensation.dim_event_definition AS ed
            ON fc.sk_event_definition = ed.sk_event_definition
    WHERE
        ed.reason_name_ptb IN ('Mérito', 'Promoção')
        AND fc.dt_valid_from <= DATE('{load_start_date}')
),
last_raise AS (
    SELECT
        last_raise_date,
        last_raise_reason,
        sk_employee
    FROM
        last_raise_ranked
    WHERE
        rn = 1
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
    es.assignment_number,
    es.name,
    es.work_email,
    es.job_name,
    COALESCE(TRY_CAST(es.band AS INT), 1) AS band,
    fc.months_tenure_in_position,
    fc.months_tenure_in_band,
    fc.months_tenure_in_company,
    es.manager_assignment_number,
    lr.last_raise_date,
    lr.last_raise_reason,
    pr.performa_score,
    es.team,
    es.vertical,
    es.country,
    es.is_manager,
    hrbp_fas.assignment_number AS hrbp_assignment_number,
    es.assignment_number_l1,
    es.assignment_number_l2,
    es.assignment_number_l3,
    es.assignment_number_l4,
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
    metric_people.employee_snapshots AS es
LEFT JOIN
    last_raise AS lr
        ON es.sk_employee = lr.sk_employee
LEFT JOIN
    latest_performa_score AS pr
        ON es.person_number = pr.person_number
LEFT JOIN
    talent_review_q1_26 AS tr_q1_26
        ON tr_q1_26.person_number = es.person_number
LEFT JOIN
    talent_review_q3_25 AS tr_q3_25
        ON tr_q3_25.person_number = es.person_number
LEFT JOIN
    talent_review_q1_25 AS tr_q1_25
        ON tr_q1_25.person_number = es.person_number
LEFT JOIN
    dw_compensation.fact_compensations AS fc
        ON fc.sk_employee = es.sk_employee
        AND fc.is_current = TRUE
LEFT JOIN
    dw_organization.dim_cost_center AS cc
        ON cc.sk_cost_center_version = es.sk_cost_center_version
LEFT JOIN
    dw_employee_details.fact_assignment_snapshots AS hrbp_fas
        ON cc.sk_business_partner = hrbp_fas.sk_employee
        AND hrbp_fas.is_current_for_employee = TRUE
WHERE
    es.is_current_for_employee = TRUE
    AND es.is_primary_assignment_for_snapshot = TRUE
    AND es.is_active = TRUE
    AND LOWER(es.status) = 'active'
