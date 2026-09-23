WITH
primary_monthly_snapshots_ranked AS (
    SELECT
        fas.sk_employee,
        fas.dt_month_reference,
        fas.dt_reference,
        fas.assignment_number
    FROM
        dw_employee_details.fact_assignment_snapshots AS fas
    WHERE
        fas.is_monthly_snapshot_for_employee = TRUE
        AND fas.sk_employee <> '-1'
),
cycle_period_months AS (
    -- Bucket the temporal ranges before applying the exact as-of predicate.
    -- The month equality restores an EMR hash key without changing range semantics.
    SELECT
        cp.sk_cycle_period,
        cp.meeting_type,
        cp.is_released,
        cp.dt_valid_from,
        cp.dt_valid_to,
        EXPLODE(
            SEQUENCE(
                CAST(DATE_TRUNC('MONTH', cp.dt_valid_from) AS DATE),
                CAST(
                    DATE_TRUNC(
                        'MONTH',
                        LEAST(
                            cp.dt_valid_to,
                            (
                                SELECT
                                    MAX(dt_reference)
                                FROM
                                    primary_monthly_snapshots_ranked
                            )
                        )
                    ) AS DATE
                ),
                INTERVAL 1 MONTH
            )
        ) AS dt_cycle_month
    FROM
        dw_performance.dim_cycle_period AS cp
    WHERE
        cp.meeting_type IN ('performance_calibration', 'talent_review')
        AND cp.dt_valid_from IS NOT NULL
        AND cp.dt_valid_to IS NOT NULL
        AND cp.dt_valid_from <= (
            SELECT
                MAX(dt_reference)
            FROM
                primary_monthly_snapshots_ranked
        )
        AND cp.dt_valid_to >= (
            SELECT
                MIN(dt_reference)
            FROM
                primary_monthly_snapshots_ranked
        )
)
SELECT
    fas.sk_cost_center_version,
    fas.sk_job_version,
    fas.sk_contact_version,
    fas.sk_documentation_version,
    fas.sk_emergency_contact_version,
    fas.sk_hierarchy_version,
    fas.sk_employee,
    fas.sk_business_unit,
    fas.sk_termination_event_definition,
    fas.sk_hired_date,
    fas.sk_terminated_date,
    fas.sk_reference_date,
    fas.person_number,
    fas.assignment_number,
    emp.name,
    emp.work_email,
    emp.generation,
    emp.highest_education_level,
    ct.personal_email,
    ct.full_phone_number,
    ct.address_state,
    ct.address_city,
    ct.address_country,
    ct.address_street,
    ct.address_number,
    ct.address_complement,
    ct.address_zip_code,
    ct.address_district,
    doc.cpf,
    doc.rg,
    doc.marital_status,
    doc.legal_name,
    dem.ethnicity,
    dem.gender_identity,
    dem.sexual_orientation,
    dem.religion,
    dis.neurodiversity,
    dis.documented_name AS documented_disability_name,
    dem.legal_sex AS registered_sex,
    job.job_name,
    job.job_family,
    job.band,
    job.job_code,
    job.salary_table,
    job.employment_type,
    bu.business_unit_name,
    bu.consolidated_business_unit_name,
    fas.business_unit_country AS country,
    cc.cost_center_code,
    cc.cost_center_name,
    cc.vertical,
    cc.structure,
    cc.team,
    cc.business,
    cc.product,
    cc.brand,
    cc.chapter,
    cc.line,
    cc.owner_l1_name,
    cc.owner_l2_name,
    cc.owner_l3_name,
    cc.headcount_type,
    cc.hrbp_work_email,
    fas.employment_status AS status,
    ev_term.reason_name_ptb AS termination_reason_name,
    ev_term.action_name_ptb AS termination_category,
    fas.termination_type,
    mh.manager_assignment_number,
    man_emp.name AS manager_name,
    man_emp.work_email AS manager_work_email,
    mh.assignment_number_l0,
    mh.assignment_number_l1,
    mh.assignment_number_l2,
    mh.assignment_number_l3,
    mh.assignment_number_l4,
    mh.assignment_number_l5,
    mh.assignment_number_l6,
    mh.assignment_number_l7,
    mh.assignment_number_l8,
    mh.assignment_number_l9,
    mh.name_l0,
    mh.name_l1,
    mh.name_l2,
    mh.name_l3,
    mh.name_l4,
    mh.name_l5,
    mh.name_l6,
    mh.name_l7,
    mh.name_l8,
    mh.name_l9,
    mh.email_l0,
    mh.email_l1,
    mh.email_l2,
    mh.email_l3,
    mh.email_l4,
    mh.email_l5,
    mh.email_l6,
    mh.email_l7,
    mh.email_l8,
    mh.email_l9,
    CONCAT(
        '-',
        '-',
        ARRAY_JOIN(
            ARRAY_DISTINCT(
                FILTER(
                    ARRAY(
                        emp.work_email,
                        cc.hrbp_work_email,
                        mh.email_l0,
                        mh.email_l1,
                        mh.email_l2,
                        mh.email_l3,
                        mh.email_l4,
                        mh.email_l5,
                        mh.email_l6,
                        mh.email_l7,
                        mh.email_l8,
                        mh.email_l9
                    ),
                    x -> x IS NOT NULL
                )
            ),
            '-'
        ),
        '-'
    ) AS access_list,
    CONCAT(
        '-',
        '-',
        ARRAY_JOIN(
            ARRAY_DISTINCT(
                FILTER(
                    ARRAY(
                        cc.hrbp_work_email,
                        mh.email_l0,
                        mh.email_l1,
                        mh.email_l2,
                        mh.email_l3,
                        mh.email_l4,
                        mh.email_l5,
                        mh.email_l6,
                        mh.email_l7,
                        mh.email_l8,
                        mh.email_l9
                    ),
                    x ->
                        x IS NOT NULL
                        AND (emp.work_email IS NULL OR x <> emp.work_email)
                )
            ),
            '-'
        ),
        '-'
    ) AS access_list_no_employee,
    CONCAT(
        '-',
        '-',
        ARRAY_JOIN(
            ARRAY_DISTINCT(
                FILTER(
                    ARRAY(
                        emp.work_email,
                        mh.email_l0,
                        mh.email_l1,
                        mh.email_l2,
                        mh.email_l3,
                        mh.email_l4,
                        mh.email_l5,
                        mh.email_l6,
                        mh.email_l7,
                        mh.email_l8,
                        mh.email_l9
                    ),
                    x ->
                        x IS NOT NULL
                        AND (cc.hrbp_work_email IS NULL OR x <> cc.hrbp_work_email)
                )
            ),
            '-'
        ),
        '-'
    ) AS access_list_no_hrbp,
    CONCAT(
        '-',
        '-',
        ARRAY_JOIN(
            ARRAY_DISTINCT(
                FILTER(
                    ARRAY(
                        mh.email_l0,
                        mh.email_l1,
                        mh.email_l2,
                        mh.email_l3,
                        mh.email_l4,
                        mh.email_l5,
                        mh.email_l6,
                        mh.email_l7,
                        mh.email_l8,
                        mh.email_l9
                    ),
                    x ->
                        x IS NOT NULL
                        AND (emp.work_email IS NULL OR x <> emp.work_email)
                        AND (cc.hrbp_work_email IS NULL OR x <> cc.hrbp_work_email)
                )
            ),
            '-'
        ),
        '-'
    ) AS access_list_no_employee_no_hrbp,
    CASE
        WHEN emp.dt_birth IS NULL THEN CAST(NULL AS STRING)
        WHEN FLOOR(MONTHS_BETWEEN(fas.dt_reference, emp.dt_birth) / 12) < 18 THEN 'under_18'
        WHEN FLOOR(MONTHS_BETWEEN(fas.dt_reference, emp.dt_birth) / 12) < 30 THEN '18_29'
        WHEN FLOOR(MONTHS_BETWEEN(fas.dt_reference, emp.dt_birth) / 12) < 40 THEN '30_39'
        WHEN FLOOR(MONTHS_BETWEEN(fas.dt_reference, emp.dt_birth) / 12) < 50 THEN '40_49'
        WHEN FLOOR(MONTHS_BETWEEN(fas.dt_reference, emp.dt_birth) / 12) < 60 THEN '50_59'
        ELSE '60_plus'
    END AS age_range,
    fc.salary_range,
    fas.employee_tenure_range,
    ev_raise.reason_name_ptb AS last_raise_reason,
    CASE WHEN cp_talent.is_released THEN dtr.potential END AS talent_potential,
    CASE WHEN cp_talent.is_released THEN dtr.criticality END AS talent_criticality,
    CASE WHEN cp_talent.is_released THEN dtr.readiness END AS talent_readiness,
    CASE WHEN cp_talent.is_released THEN dtr.risk_of_loss END AS talent_risk_of_loss,
    CASE WHEN cp_calibration.is_released THEN pcc.performa_score END AS perf_final_range,
    -- 9-box: talent potential (rows) x calibrated Performa band (columns), gated by both cycles' is_released.
    CASE
        WHEN NOT cp_talent.is_released OR NOT cp_calibration.is_released THEN CAST(NULL AS STRING)
        WHEN dtr.potential = 'High' AND pcc.performa_score IN ('Outstanding', 'Above expectations') THEN 'Q1'
        WHEN dtr.potential = 'High' AND pcc.performa_score = 'Meets expectations' THEN 'Q2'
        WHEN dtr.potential = 'High' AND pcc.performa_score IN ('Partially misses expectations', 'Insufficient') THEN 'Q3'
        WHEN dtr.potential = 'Medium' AND pcc.performa_score IN ('Outstanding', 'Above expectations') THEN 'Q4'
        WHEN dtr.potential = 'Medium' AND pcc.performa_score = 'Meets expectations' THEN 'Q5'
        WHEN dtr.potential = 'Medium' AND pcc.performa_score IN ('Partially misses expectations', 'Insufficient') THEN 'Q6'
        WHEN dtr.potential = 'Low' AND pcc.performa_score IN ('Outstanding', 'Above expectations') THEN 'Q7'
        WHEN dtr.potential = 'Low' AND pcc.performa_score = 'Meets expectations' THEN 'Q8'
        WHEN dtr.potential = 'Low' AND pcc.performa_score IN ('Partially misses expectations', 'Insufficient') THEN 'Q9'
        ELSE CAST(NULL AS STRING)
    END AS development_matrix,
    mh.hierarchy_depth,
    FLOOR(
        MONTHS_BETWEEN(fas.dt_reference, emp.dt_birth) / 12
    ) AS age_in_years,
    CASE
        WHEN fc.dt_valid_from IS NULL THEN CAST(NULL AS INT)
        ELSE FLOOR(MONTHS_BETWEEN(fas.dt_reference, fc.dt_valid_from))
    END AS months_since_last_raise,
    fc.amount_salary,
    fc.range_position,
    job.salary_range_mid,
    COALESCE(job.target_plr, job.target_plr_salary_multiplier * fc.amount_salary) AS target_variable_pay,
    fc.amount_adjustment AS last_raise_amount,
    fc.pct_adjustment AS last_raise_pct,
    fas.count_direct_report,
    fas.count_total_report,
    fas.months_employee_tenure,
    fas.days_employee_tenure,
    fas.days_tenure_in_assignment,
    fc.days_tenure_in_band,
    fc.months_tenure_in_band,
    fas.count_indirect_report,
    CASE WHEN cp_calibration.is_released THEN CAST(pcc.calibrated_impact_numeric AS DECIMAL(18, 4)) END AS perf_impact_score,
    CASE WHEN cp_calibration.is_released THEN CAST(pcc.calibrated_behavior_numeric AS DECIMAL(18, 4)) END AS perf_behavior_score,
    CASE WHEN cp_calibration.is_released THEN CAST(pcc.calibrated_leadership_numeric AS DECIMAL(18, 4)) END AS perf_leadership_score,
    CASE WHEN cp_calibration.is_released THEN CAST(pcc.performa_score_numeric AS DECIMAL(18, 4)) END AS perf_composite_score,
    CASE WHEN cp_calibration.is_released THEN CAST(pcc.performa_ipa AS DECIMAL(18, 4)) END AS perf_ipa,
    job.has_clock_in,
    dem.has_self_declared_pwd,
    dem.has_medical_disability_record,
    dem.is_underrepresented_race,
    dem.is_lgbtqia,
    dem.is_woman,
    dem.is_neurodivergent,
    fc.is_eligible_internet_reimbursement,
    fas.is_active,
    fas.is_effective_worker,
    fas.is_reorganization_termination AS is_layoff,
    COALESCE(man_fas.is_active, FALSE) AS manager_is_active,
    fas.is_manager,
    fas.is_leadership_team_member,
    fas.is_executive_team_member,
    fas.has_emergency_contact,
    fas.is_transfer_hire,
    fas.is_transfer_termination,
    fas.is_effectivation_hire,
    fas.is_effectivation_termination,
    fas.is_primary_assignment_for_snapshot,
    fas.is_current_for_employee AS is_current,
    fas.is_current_for_employee,
    fas.dt_month_reference,
    emp.dt_birth,
    fas.dt_assignment_started,
    fas.dt_terminated,
    fas.dt_employee_hired,
    fas.dt_notified_termination,
    fc.dt_valid_from AS dt_last_raise,
    fas.ts_load
FROM
    primary_monthly_snapshots_ranked AS pms
INNER JOIN
    dw_employee_details.fact_assignment_snapshots AS fas
        ON fas.sk_employee = pms.sk_employee
        AND fas.dt_month_reference = pms.dt_month_reference
        AND fas.dt_reference = pms.dt_reference
        AND fas.assignment_number = pms.assignment_number
LEFT JOIN
    dw_employee_details.dim_employee AS emp
        ON emp.sk_employee = fas.sk_employee
LEFT JOIN
    dw_employee_details.dim_contact AS ct
        ON ct.sk_contact_version = fas.sk_contact_version
LEFT JOIN
    dw_employee_details.dim_documentation AS doc
        ON doc.sk_documentation_version = fas.sk_documentation_version
LEFT JOIN
    dw_employee_details.dim_termination AS ev_term
        ON ev_term.sk_event_definition = fas.sk_termination_event_definition
LEFT JOIN
    dw_employee_details.dim_management_hierarchy AS mh
        ON mh.sk_hierarchy_version = fas.sk_hierarchy_version
LEFT JOIN
    dw_compensation.dim_job AS job
        ON job.sk_job_version = fas.sk_job_version
LEFT JOIN
    dw_organization.dim_business_unit AS bu
        ON bu.sk_business_unit = fas.sk_business_unit
LEFT JOIN
    dw_organization.dim_cost_center AS cc
        ON cc.sk_cost_center_version = fas.sk_cost_center_version
LEFT JOIN
    dw_employee_details.fact_assignment_snapshots AS man_fas
        ON man_fas.assignment_number = mh.manager_assignment_number
        AND man_fas.dt_reference = fas.dt_reference
LEFT JOIN
    dw_employee_details.dim_employee AS man_emp
        ON man_emp.sk_employee = man_fas.sk_employee
LEFT JOIN
    dw_demographics.dim_employee_demographic AS dem
        ON dem.sk_employee = fas.sk_employee
        AND fas.dt_reference >= dem.dt_valid_from
        AND fas.dt_reference <= dem.dt_valid_to
LEFT JOIN
    dw_demographics.dim_employee_disability AS dis
        ON dis.sk_employee = fas.sk_employee
        AND dis.is_primary = TRUE
        AND fas.dt_reference >= dis.dt_valid_from
        AND fas.dt_reference <= dis.dt_valid_to
LEFT JOIN
    dw_compensation.fact_compensations AS fc
        ON fc.sk_compensation = fas.sk_compensation_version
        AND fas.sk_compensation_version <> '-1'
LEFT JOIN
    dw_compensation.dim_event_definition AS ev_raise
        ON ev_raise.sk_event_definition = fc.sk_event_definition
LEFT JOIN
    cycle_period_months AS cp_calibration
        ON cp_calibration.meeting_type = 'performance_calibration'
        AND cp_calibration.dt_cycle_month = CAST(
            DATE_TRUNC('MONTH', fas.dt_reference) AS DATE
        )
        AND fas.dt_reference BETWEEN cp_calibration.dt_valid_from AND cp_calibration.dt_valid_to
LEFT JOIN
    dw_performance.fact_performance_calibrations AS pcc
        ON pcc.person_number = fas.person_number
        AND pcc.sk_cycle_period = cp_calibration.sk_cycle_period
LEFT JOIN
    cycle_period_months AS cp_talent
        ON cp_talent.meeting_type = 'talent_review'
        AND cp_talent.dt_cycle_month = CAST(
            DATE_TRUNC('MONTH', fas.dt_reference) AS DATE
        )
        AND fas.dt_reference BETWEEN cp_talent.dt_valid_from AND cp_talent.dt_valid_to
LEFT JOIN
    dw_performance.fact_talent_reviews AS ftr
        ON ftr.person_number = fas.person_number
        AND ftr.sk_cycle_period = cp_talent.sk_cycle_period
        AND ftr.is_latest_for_employee_in_cycle = TRUE
LEFT JOIN
    dw_performance.dim_talent_rating AS dtr
        ON dtr.sk_talent_rating = ftr.sk_talent_rating_from_calibration
