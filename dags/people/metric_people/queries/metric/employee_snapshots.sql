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
    job.country,
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
    mh.manager_assignment_number,
    mh.name_l1 AS manager_name,
    mh.email_l1 AS manager_work_email,
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
    fas.tenure_range,
    ev_raise.reason_name_ptb AS last_raise_reason,
    CAST(NULL AS STRING) AS talent_potential,
    CAST(NULL AS STRING) AS talent_criticality,
    CAST(NULL AS STRING) AS talent_readiness,
    CAST(NULL AS STRING) AS talent_risk_of_loss,
    CAST(NULL AS STRING) AS perf_final_range,
    CAST(NULL AS STRING) AS development_matrix,
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
    fas.months_tenure_in_company,
    fas.days_tenure_in_company,
    fas.days_tenure_in_assignment,
    fc.days_tenure_in_band,
    fc.months_tenure_in_band,
    fas.count_indirect_report,
    CAST(NULL AS DECIMAL(18, 4)) AS perf_impact_score,
    CAST(NULL AS DECIMAL(18, 4)) AS perf_behavior_score,
    CAST(NULL AS DECIMAL(18, 4)) AS perf_leadership_score,
    CAST(NULL AS DECIMAL(18, 4)) AS perf_composite_score,
    CAST(NULL AS DECIMAL(18, 4)) AS perf_ipa,
    job.has_clock_in,
    dem.has_self_declared_pwd,
    dem.has_medical_disability_record,
    dem.is_underrepresented_race,
    dem.is_lgbtqia,
    dem.is_woman,
    dem.is_neurodivergent,
    fc.is_eligible_internet_reimbursement,
    fas.is_active,
    fas.is_reorganization_termination AS is_layoff,
    COALESCE(man_fas.is_active, FALSE) AS manager_is_active,
    fas.is_manager,
    fas.is_leadership_team_member,
    fas.is_executive_team_member,
    fas.has_emergency_contact,
    fas.is_internal_transfer,
    fas.is_monthly_snapshot,
    fas.is_primary_assignment_for_snapshot,
    fas.is_current,
    fas.dt_month_reference,
    emp.dt_birth,
    fas.dt_hired,
    fas.dt_terminated,
    fas.dt_original_hire,
    fas.dt_notified_termination,
    fc.dt_valid_from AS dt_last_raise,
    fas.ts_load
FROM
    dw_employee_details.fact_assignment_snapshots AS fas
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
    dw_employee_details.dim_event_definition AS ev_term
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
WHERE
    fas.is_monthly_snapshot = TRUE
    AND fas.is_primary_assignment_for_snapshot = TRUE
    AND fas.sk_employee <> '-1'
