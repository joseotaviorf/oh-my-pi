WITH params AS (
    SELECT 
        *,
        MAKE_DATE(reference_year, 1, 1) AS dt_year_started,
        MAKE_DATE(reference_year, 12, 31) AS dt_year_ended
    FROM 
        dw_compensation.dim_plr_parameters
    WHERE
        reference_year <> -1
),
performance_calibration_with_meeting_year AS (
    SELECT
        fpc.person_number,
        fpc.performa_score,
        fpc.sk_committee_meeting,
        dcm.meeting_year
    FROM
        dw_performance.fact_performance_calibrations AS fpc
    INNER JOIN
        dw_performance.dim_committee_meeting AS dcm
            ON fpc.sk_committee_meeting = dcm.sk_meeting
),
assignments_plr_eligibility_ranked AS (
    /* Base eligibility rules: hired by cutoff date, 90+ days in year (only for hires in reference year;
       hires before reference year are eligible regardless of days worked), not terminated for just cause.
       Date calculation: first day of work counts (exit_date - admission_date + 1).
       IPA comes from Performa calibration (meeting_year = reference_year + 1). */
    SELECT
        im.id_period_of_service AS sk_period_of_service,
        im.id_assignment AS sk_contract,
        im.assignment_number,
        im.person_number,
        ed.dismissal_type,
        ed.dismissal_reason,
        fpc.performa_score,
        CASE
            WHEN fpc.performa_score = 'Outstanding' THEN 1.50
            WHEN fpc.performa_score = 'Above expectations' THEN 1.20
            WHEN fpc.performa_score = 'Meets expectations' THEN 1.00
            WHEN fpc.performa_score = 'Partially misses expectations' THEN 0.70
            WHEN fpc.performa_score = 'Insufficient' THEN 0.00
            ELSE NULL
        END AS performa_ipa,
        im.dt_started AS dt_hired,
        COALESCE(im.dt_actual_termination, DATE('9999-12-31')) AS dt_terminated,
        CASE
            WHEN im.dt_started > plr_params.dt_year_ended
            THEN 0
            ELSE DATEDIFF(
                LEAST(
                    COALESCE(im.dt_actual_termination, plr_params.dt_year_ended),
                    plr_params.dt_year_ended
                ),
                GREATEST(im.dt_started, plr_params.dt_year_started)
            ) + 1
        END AS days_worked_in_year_before_removing_unpaid_leaves,
        plr_params.pct_default_corporate_goals_terminated,
        plr_params.pct_default_ipa_terminated,
        plr_params.pct_min_protected_leave_ipa,
        plr_params.pct_corporate_goals,
        plr_params.min_days_worked_in_year_for_eligibility,
        plr_params.min_days_worked_in_month_to_count,
        plr_params.pct_min_corporate_goals,
        COALESCE(im.dt_started < plr_params.dt_admission_cutoff, FALSE) AS is_eligible_by_hired_date,
        COALESCE(ed.dismissal_reason <> 'Dispensa por Justa Causa', TRUE) AS is_eligible_by_dismissal_reason,
        COALESCE(
            im.dt_actual_termination < plr_params.dt_evaluation_cycle_started,
            FALSE
        ) AS is_terminated_before_evaluation_cycle_started,
        COALESCE(im.dt_actual_termination < plr_params.dt_payment_cutoff, FALSE) AS is_terminated_before_payment_cutoff,
        plr_params.reference_year,
        ROW_NUMBER() OVER (
            PARTITION BY im.person_number, plr_params.reference_year
            ORDER BY fpc.meeting_year DESC, fpc.sk_committee_meeting DESC
        ) AS rn
    FROM
        datalake_people.identifier_mapping AS im
    LEFT JOIN
        datalake_employment.employee_details AS ed
            ON ed.id_assignment = im.id_assignment
    CROSS JOIN
        params AS plr_params
    LEFT JOIN
        performance_calibration_with_meeting_year AS fpc
            ON fpc.person_number = im.person_number
            AND fpc.meeting_year = plr_params.reference_year + 1
    WHERE
        YEAR(im.dt_started) <= plr_params.reference_year
        AND (
            YEAR(im.dt_actual_termination) IS NULL
            OR YEAR(im.dt_actual_termination) >= plr_params.reference_year
        )
        AND im.assignment_type <> 'P'
        AND NOT im.is_user_test
),
assignments_plr_eligibility AS (
    SELECT
        sk_period_of_service,
        sk_contract,
        assignment_number,
        person_number,
        dismissal_type,
        dismissal_reason,
        performa_score,
        performa_ipa,
        dt_hired,
        dt_terminated,
        days_worked_in_year_before_removing_unpaid_leaves,
        pct_default_corporate_goals_terminated,
        pct_default_ipa_terminated,
        pct_min_protected_leave_ipa,
        pct_corporate_goals,
        min_days_worked_in_year_for_eligibility,
        min_days_worked_in_month_to_count,
        pct_min_corporate_goals,
        is_eligible_by_hired_date,
        is_eligible_by_dismissal_reason,
        is_terminated_before_evaluation_cycle_started,
        is_terminated_before_payment_cutoff,
        reference_year
    FROM
        assignments_plr_eligibility_ranked
    WHERE
        rn = 1
),
plr_reference_months AS (
    /* Calendar months for the PLR reference year (January to December). */
    SELECT
        dd.month_start AS dt_month_started,
        dd.month_end AS dt_month_ended,
        ANY_VALUE(dd.total_days_in_month) AS days_in_month
    FROM
        dw_public.dim_date AS dd
    CROSS JOIN
        params AS plr_params
    WHERE
        dd.year = plr_params.reference_year
    GROUP BY 
        dd.month_start, dd.month_end
),
absence_days_by_assignment_month AS (
    /* Monthly absence days: unpaid leave reduces worked days, protected leave (maternity/parental/health)
       ensures minimum 100% IPA when >= 15 days in the month. */
    SELECT
        far.sk_assignment,
        mc.dt_month_started,
        SUM(
            CASE
                WHEN NOT dat.is_paid_leave
                THEN DATEDIFF(
                    LEAST(
                        COALESCE(far.dt_absence_ended, mc.dt_month_ended),
                        mc.dt_month_ended
                    ),
                    GREATEST(far.dt_absence_started, mc.dt_month_started)
                ) + 1
                ELSE 0
            END
        ) AS days_unpaid_leave,
        SUM(
            CASE
                WHEN dat.is_performa_protected
                THEN DATEDIFF(
                    LEAST(
                        COALESCE(far.dt_absence_ended, mc.dt_month_ended),
                        mc.dt_month_ended
                    ),
                    GREATEST(far.dt_absence_started, mc.dt_month_started)
                ) + 1
                ELSE 0
            END
        ) AS days_protected_leave
    FROM
        plr_reference_months AS mc
    INNER JOIN
        dw_time.fact_absence_requests AS far
            ON far.dt_absence_started <= mc.dt_month_ended
            AND COALESCE(far.dt_absence_ended, mc.dt_month_ended) >= mc.dt_month_started
            AND far.is_approved = TRUE
    INNER JOIN
        dw_time.dim_absence_type AS dat
            ON far.sk_absence_type = dat.sk_absence_type
    GROUP BY
        far.sk_assignment,
        mc.dt_month_started
    HAVING
        days_unpaid_leave + days_protected_leave > 0
),
absence_days_by_assignment_year AS (
    /* Annual absence totals: used to determine if employee had >= 15 days of protected leave,
       which guarantees minimum 100% IPA regardless of performance score. */
    SELECT
        sk_assignment,
        SUM(days_unpaid_leave) AS total_unpaid_absence_days_in_the_year,
        SUM(days_protected_leave) AS total_protected_absence_days_in_the_year
    FROM
        absence_days_by_assignment_month
    GROUP BY
        sk_assignment
),
compensation_by_contract_month_ranked AS (
    /* Monthly compensation and job info: eligibility by country/band (BR/PT/US exclude interns, LATAM requires Band 9+).
       Target PLR calculation: Core countries use monthly salary * multiplier / 12, LATAM uses last salary in position * multiplier / 12. */
    SELECT
        mc.dt_month_started,
        mc.dt_month_ended,
        fc.sk_contract,
        fc.sk_job_version,
        fc.currency_code,
        fc.amount_salary,
        FIRST_VALUE(fc.amount_salary) OVER (PARTITION BY fc.sk_contract, dj.id_job ORDER BY fc.dt_valid_from DESC) AS last_salary_in_position,
        dj.country,
        dj.band,
        dj.target_plr,
        dj.target_plr_salary_multiplier,
        fc.dt_valid_from AS dt_job_info_valid_from,
        fc.dt_valid_to AS dt_job_info_valid_to,
        CASE
            WHEN dj.band IS NULL
                OR dj.country IS NULL THEN NULL
            WHEN dj.country IN ('Brazil', 'Portugal', 'United States')
                AND dj.band NOT IN ('Estag1', 'Estag2', 'Estag3', 'Trainee') THEN TRUE
            WHEN dj.country NOT IN ('Brazil', 'Portugal', 'United States')
                AND TRY_CAST(dj.band AS INT) >= 9 THEN TRUE
            ELSE FALSE
        END AS is_eligible_by_country_and_band,
        CASE
            WHEN dj.country IN ('Brazil', 'Portugal', 'United States') THEN TRUE
            ELSE FALSE
        END AS is_core_country,
        ROW_NUMBER() OVER (PARTITION BY fc.sk_contract, mc.dt_month_started ORDER BY fc.dt_valid_from DESC) AS rn
    FROM
        dw_compensation.fact_compensations AS fc
    LEFT JOIN
        dw_compensation.dim_job AS dj
            ON fc.sk_job_version = dj.sk_job_version
    CROSS JOIN
        params AS plr_params
    LEFT JOIN
        plr_reference_months AS mc
            ON fc.dt_valid_from <= mc.dt_month_ended
            AND fc.dt_valid_to >= mc.dt_month_started
    WHERE
        plr_params.reference_year BETWEEN YEAR(fc.dt_valid_from)
            AND YEAR(fc.dt_valid_to)
),
compensation_by_contract_month AS (
    SELECT
        dt_month_started,
        dt_month_ended,
        sk_contract,
        sk_job_version,
        currency_code,
        amount_salary,
        last_salary_in_position,
        country,
        band,
        target_plr,
        target_plr_salary_multiplier,
        dt_job_info_valid_from,
        dt_job_info_valid_to,
        is_eligible_by_country_and_band,
        is_core_country
    FROM
        compensation_by_contract_month_ranked
    WHERE
        rn = 1
),
base_calculations AS (
    /* Consolidates all base calculations: worked days (monthly and yearly), absences, compensation, and eligibility flags.
       Monthly worked days = days in month minus unpaid leave. Yearly worked days = total days minus annual unpaid leave. */
    SELECT
        ab.sk_period_of_service,
        ab.sk_contract,
        ab.reference_year AS sk_plr_parameters,
        ab.reference_year,
        comp.dt_month_started AS sk_reference_month,
        comp.sk_job_version,
        ab.assignment_number,
        ab.person_number,
        ab.dismissal_type,
        ab.dismissal_reason,
        ab.performa_score,
        comp.country,
        comp.band,
        comp.currency_code,
        COALESCE(abs_m.days_unpaid_leave, 0) AS days_unpaid_leave,
        COALESCE(abs_m.days_protected_leave, 0) AS days_protected_leave,
        COALESCE(abs_y.total_unpaid_absence_days_in_the_year, 0) AS total_unpaid_absence_days_in_the_year,
        COALESCE(abs_y.total_protected_absence_days_in_the_year, 0) AS total_protected_absence_days_in_the_year,
        comp.amount_salary,
        comp.last_salary_in_position,
        comp.target_plr,
        comp.target_plr_salary_multiplier,
        /* Days worked in month: intersection of month period and employment period, minus unpaid leave. */
        CASE 
            WHEN LEAST(comp.dt_month_ended, ab.dt_terminated) >= GREATEST(comp.dt_month_started, ab.dt_hired)
            THEN DATEDIFF(LEAST(comp.dt_month_ended, ab.dt_terminated), GREATEST(comp.dt_month_started, ab.dt_hired)) + 1
                 - COALESCE(abs_m.days_unpaid_leave, 0)
            ELSE 0 
        END AS days_worked_in_month,
        /* Days worked in year: total days in reference year minus annual unpaid leave (not monthly). */
        COALESCE(ab.days_worked_in_year_before_removing_unpaid_leaves, 0)
            - COALESCE(abs_y.total_unpaid_absence_days_in_the_year, 0) AS days_worked_in_year,
        ab.performa_ipa,
        ab.pct_default_corporate_goals_terminated,
        ab.pct_default_ipa_terminated,
        ab.pct_min_protected_leave_ipa,
        ab.pct_corporate_goals,
        ab.is_terminated_before_evaluation_cycle_started,
        ab.is_eligible_by_hired_date,
        ab.is_eligible_by_dismissal_reason,
        comp.is_eligible_by_country_and_band,
        comp.is_core_country,
        ab.min_days_worked_in_year_for_eligibility,
        ab.pct_min_corporate_goals,
        ab.is_terminated_before_payment_cutoff,
        ab.min_days_worked_in_month_to_count,
        ab.dt_hired,
        ab.dt_terminated,
        comp.dt_job_info_valid_from,
        comp.dt_job_info_valid_to
    FROM
        assignments_plr_eligibility AS ab
    LEFT JOIN
        compensation_by_contract_month AS comp
            ON comp.sk_contract = ab.sk_contract
    LEFT JOIN
        absence_days_by_assignment_month AS abs_m
            ON abs_m.sk_assignment = ab.sk_contract
            AND comp.dt_month_started = abs_m.dt_month_started
    LEFT JOIN
        absence_days_by_assignment_year AS abs_y
            ON abs_y.sk_assignment = ab.sk_contract
)
SELECT
    MD5(CONCAT_WS('|', CAST(sk_period_of_service AS STRING), CAST(sk_reference_month AS STRING))) AS sk_plr_monthly,
    sk_period_of_service,
    sk_contract,
    sk_plr_parameters,
    sk_reference_month,
    sk_job_version,
    assignment_number,
    person_number,
    dismissal_type,
    dismissal_reason,
    performa_score,
    country,
    band,
    currency_code,
    days_unpaid_leave,
    days_protected_leave,
    total_unpaid_absence_days_in_the_year,
    total_protected_absence_days_in_the_year,
    amount_salary,
    last_salary_in_position,
    target_plr,
    target_plr_salary_multiplier,
    days_worked_in_month,
    days_worked_in_year,
    performa_ipa,
    pct_default_corporate_goals_terminated,
    pct_default_ipa_terminated,
    pct_min_protected_leave_ipa,
    pct_corporate_goals,
    is_terminated_before_evaluation_cycle_started,
    is_eligible_by_hired_date,
    is_eligible_by_dismissal_reason,
    is_eligible_by_country_and_band,
    /* Eligibility flags: 90+ days worked in year only for hires in reference year; hires before reference year
       are eligible regardless. 15+ days in month counts as full month. */
    (
        YEAR(dt_hired) < reference_year
        OR days_worked_in_year >= min_days_worked_in_year_for_eligibility
    ) AS is_eligible_by_yearly_worked_days,
    (pct_corporate_goals >= pct_min_corporate_goals) AS is_corporate_goal_met,
    is_terminated_before_payment_cutoff,
    (days_worked_in_month >= min_days_worked_in_month_to_count)
        AS is_month_eligible_by_worked_days,
    (total_protected_absence_days_in_the_year >= min_days_worked_in_month_to_count)
        AS is_month_protected_by_ipa,
    /* PLR multipliers: eligibility * IPA * corporate_goals * target.
       IPA rules: Protected leave >= 15 days guarantees 100% IPA minimum.
       Terminated employees: Brazil uses 70% IPA if terminated before evaluation cycle, LATAM uses 70% for both IPA and corporate goals. */
    CASE
        WHEN is_eligible_by_hired_date
            AND is_eligible_by_dismissal_reason
            AND is_eligible_by_country_and_band
            AND (
                YEAR(dt_hired) < reference_year
                OR days_worked_in_year >= min_days_worked_in_year_for_eligibility
            )
            AND (days_worked_in_month >= min_days_worked_in_month_to_count)
        THEN 1
        ELSE 0
    END AS multiplier_eligibility,
    CASE
        WHEN total_protected_absence_days_in_the_year >= min_days_worked_in_month_to_count
        THEN GREATEST(pct_min_protected_leave_ipa, performa_ipa)
        WHEN country <> 'Brazil' AND is_terminated_before_payment_cutoff
        THEN pct_default_ipa_terminated
        WHEN is_terminated_before_evaluation_cycle_started
        THEN pct_default_corporate_goals_terminated
        ELSE performa_ipa
    END AS multiplier_ipa,
    CASE
        WHEN country <> 'Brazil' AND is_terminated_before_payment_cutoff
        THEN pct_default_corporate_goals_terminated
        WHEN pct_corporate_goals < pct_min_corporate_goals THEN 0.0
        ELSE pct_corporate_goals
    END AS multiplier_corporate_goals,
    CASE
        WHEN COALESCE(target_plr_salary_multiplier, 0) > 0 AND NOT is_core_country
        THEN last_salary_in_position * target_plr_salary_multiplier / 12
        WHEN COALESCE(target_plr_salary_multiplier, 0) > 0 AND is_core_country
        THEN amount_salary * target_plr_salary_multiplier / 12
        ELSE target_plr / 12
    END AS multiplier_target_plr,
    COALESCE(
        (CASE
            WHEN is_eligible_by_hired_date
                AND is_eligible_by_dismissal_reason
                AND is_eligible_by_country_and_band
                AND (
                    YEAR(dt_hired) < reference_year
                    OR days_worked_in_year >= min_days_worked_in_year_for_eligibility
                )
                AND (days_worked_in_month >= min_days_worked_in_month_to_count)
            THEN 1
            ELSE 0
        END) *
        (CASE
            WHEN total_protected_absence_days_in_the_year >= min_days_worked_in_month_to_count
            THEN GREATEST(pct_min_protected_leave_ipa, performa_ipa)
            WHEN country <> 'Brazil' AND is_terminated_before_payment_cutoff
            THEN pct_default_ipa_terminated
            WHEN is_terminated_before_evaluation_cycle_started
            THEN pct_default_corporate_goals_terminated
            ELSE performa_ipa
        END) *
        (CASE
            WHEN country <> 'Brazil' AND is_terminated_before_payment_cutoff
            THEN pct_default_corporate_goals_terminated
            WHEN pct_corporate_goals < pct_min_corporate_goals THEN 0.0
            ELSE pct_corporate_goals
        END) *
        (CASE
            WHEN COALESCE(target_plr_salary_multiplier, 0) > 0 AND NOT is_core_country
            THEN last_salary_in_position * target_plr_salary_multiplier / 12
            WHEN COALESCE(target_plr_salary_multiplier, 0) > 0 AND is_core_country
            THEN amount_salary * target_plr_salary_multiplier / 12
            ELSE target_plr / 12
        END)
    , 0) AS amount_plr_monthly,
    dt_hired,
    dt_terminated,
    dt_job_info_valid_from,
    dt_job_info_valid_to,
    NOW() AS ts_load
FROM
    base_calculations
WHERE
    sk_reference_month IS NOT NULL