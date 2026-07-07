WITH
assignments_with_series_end AS (
    SELECT
        im.id_assignment,
        im.id_person,
        im.person_number,
        im.assignment_number,
        im.dt_started,
        im.dt_actual_termination AS dt_terminated,
        im.dt_notified_termination,
        LEAST(COALESCE(im.dt_actual_termination, DATE('{load_start_date}')), DATE('{load_start_date}')) AS dt_series_end
    FROM
        datalake_people.identifier_mapping AS im
    WHERE
        im.is_valid_assignment
        AND im.dt_started IS NOT NULL
        AND im.dt_started <= DATE('{load_start_date}')
),
assignments_with_dates AS (
    SELECT
        aws.id_assignment,
        aws.id_person,
        aws.person_number,
        aws.assignment_number,
        aws.dt_started,
        aws.dt_terminated,
        aws.dt_notified_termination,
        aws.dt_series_end,
        SEQUENCE(aws.dt_started, aws.dt_series_end) AS dt_reference_array
    FROM
        assignments_with_series_end AS aws
),
assignments_daily AS (
    SELECT
        awd.id_assignment,
        awd.id_person,
        awd.person_number,
        awd.assignment_number,
        awd.dt_started,
        awd.dt_terminated,
        awd.dt_notified_termination,
        awd.dt_series_end,
        dt_reference,
        (
            dt_reference < awd.dt_started
        ) AS is_future_hire
    FROM
        assignments_with_dates AS awd
    LATERAL VIEW EXPLODE(dt_reference_array) dt_ref AS dt_reference
),
primary_assignment_per_person_day_ranked AS (
    SELECT
        ad.id_person,
        ad.dt_reference,
        ad.id_assignment,
        ROW_NUMBER() OVER (
            PARTITION BY
                ad.id_person,
                ad.dt_reference
            ORDER BY
                CASE
                    WHEN NOT ad.is_future_hire THEN 0
                    ELSE 1
                END ASC,
                ad.dt_started DESC
        ) AS rn
    FROM
        assignments_daily AS ad
),
primary_assignment_per_person_day AS (
    SELECT
        id_person,
        dt_reference,
        id_assignment
    FROM
        primary_assignment_per_person_day_ranked
    WHERE
        rn = 1
),
-- Direct and indirect report counts from management hierarchy
hierarchy_with_direct_manager AS (
    SELECT
        ad.assignment_number AS reporter_assignment_number,
        ad.dt_reference,
        mh.assignment_number_l0,
        mh.assignment_number_l1,
        mh.assignment_number_l2,
        mh.assignment_number_l3,
        mh.assignment_number_l4,
        mh.assignment_number_l5,
        mh.assignment_number_l6,
        mh.assignment_number_l7,
        mh.manager_assignment_number AS direct_manager_assignment_number,
        mh.hierarchy_depth AS employee_depth
    FROM
        assignments_daily AS ad
    INNER JOIN
        datalake_people.management_hierarchy AS mh
            ON mh.assignment_number = ad.assignment_number
            AND ad.dt_reference >= mh.dt_valid_from
            AND ad.dt_reference <= mh.dt_valid_to
    WHERE
        NOT ad.is_future_hire
),
direct_report_counts AS (
    SELECT
        dt_reference,
        direct_manager_assignment_number AS manager_assignment_number,
        COUNT(DISTINCT reporter_assignment_number) AS count_direct_report
    FROM
        hierarchy_with_direct_manager
    WHERE
        direct_manager_assignment_number IS NOT NULL
    GROUP BY
        dt_reference,
        direct_manager_assignment_number
),
indirect_manager_reporter AS (
    SELECT
        dt_reference,
        assignment_number_l0 AS manager_assignment_number,
        reporter_assignment_number
    FROM
        hierarchy_with_direct_manager
    WHERE
        employee_depth >= 2
        AND assignment_number_l0 IS NOT NULL
    UNION
    SELECT
        dt_reference,
        assignment_number_l1 AS manager_assignment_number,
        reporter_assignment_number
    FROM
        hierarchy_with_direct_manager
    WHERE
        employee_depth >= 3
        AND assignment_number_l1 IS NOT NULL
    UNION
    SELECT
        dt_reference,
        assignment_number_l2 AS manager_assignment_number,
        reporter_assignment_number
    FROM
        hierarchy_with_direct_manager
    WHERE
        employee_depth >= 4
        AND assignment_number_l2 IS NOT NULL
    UNION
    SELECT
        dt_reference,
        assignment_number_l3 AS manager_assignment_number,
        reporter_assignment_number
    FROM
        hierarchy_with_direct_manager
    WHERE
        employee_depth >= 5
        AND assignment_number_l3 IS NOT NULL
    UNION
    SELECT
        dt_reference,
        assignment_number_l4 AS manager_assignment_number,
        reporter_assignment_number
    FROM
        hierarchy_with_direct_manager
    WHERE
        employee_depth >= 6
        AND assignment_number_l4 IS NOT NULL
    UNION
    SELECT
        dt_reference,
        assignment_number_l5 AS manager_assignment_number,
        reporter_assignment_number
    FROM
        hierarchy_with_direct_manager
    WHERE
        employee_depth >= 7
        AND assignment_number_l5 IS NOT NULL
    UNION
    SELECT
        dt_reference,
        assignment_number_l6 AS manager_assignment_number,
        reporter_assignment_number
    FROM
        hierarchy_with_direct_manager
    WHERE
        employee_depth >= 8
        AND assignment_number_l6 IS NOT NULL
    UNION
    SELECT
        dt_reference,
        assignment_number_l7 AS manager_assignment_number,
        reporter_assignment_number
    FROM
        hierarchy_with_direct_manager
    WHERE
        employee_depth >= 9
        AND assignment_number_l7 IS NOT NULL
),
indirect_report_counts AS (
    SELECT
        dt_reference,
        manager_assignment_number,
        COUNT(DISTINCT reporter_assignment_number) AS count_indirect_report
    FROM
        indirect_manager_reporter
    GROUP BY
        dt_reference,
        manager_assignment_number
),
assignment_snapshots_ranked AS (
    SELECT
        ad.id_assignment,
        ad.id_person,
        all_assign.id_organization,
        all_assign.id_business_unit,
        all_assign.id_job,
        MD5(
            CONCAT_WS(
                '|',
                CAST(jwst.id_job AS STRING),
                CAST(jwst.dt_valid_from AS STRING)
            )
        ) AS sk_job_version,
        cc.sk_cost_center_version,
        cv.sk_compensation AS sk_compensation_version,
        jwst.country AS business_unit_country,
        mh.sk_hierarchy_version,
        im.id_termination_event_definition AS sk_termination_event_definition,
        DATE_FORMAT(ad.dt_started, 'yyyyMMdd') AS sk_hired_date,
        DATE_FORMAT(
            COALESCE(ad.dt_terminated, DATE('9999-12-31')),
            'yyyyMMdd'
        ) AS sk_terminated_date,
        DATE_FORMAT(ad.dt_reference, 'yyyyMMdd') AS sk_reference_date,
        ad.person_number,
        ad.assignment_number,
        mh.manager_assignment_number,
        mh.hierarchy_level,
        mh.hierarchy_depth,
        CASE
            WHEN ad.dt_terminated IS NOT NULL
                AND ad.dt_reference >= ad.dt_terminated
                AND NOT COALESCE(im.is_transfer_termination, FALSE) THEN 'Terminated'
            ELSE 'Active'
        END AS employment_status,
        CASE
            WHEN FLOOR(MONTHS_BETWEEN(ad.dt_reference, im.dt_original_hired)) IS NULL THEN CAST(NULL AS STRING)
            WHEN FLOOR(MONTHS_BETWEEN(ad.dt_reference, im.dt_original_hired)) < 3  THEN '< 3 months'
            WHEN FLOOR(MONTHS_BETWEEN(ad.dt_reference, im.dt_original_hired)) < 12 THEN '3-11 months'
            WHEN FLOOR(MONTHS_BETWEEN(ad.dt_reference, im.dt_original_hired)) < 36 THEN '1-2 years'
            WHEN FLOOR(MONTHS_BETWEEN(ad.dt_reference, im.dt_original_hired)) < 60 THEN '3-4 years'
            ELSE '5+ years'
        END AS tenure_range,
        DATEDIFF(ad.dt_reference, im.dt_original_hired) AS days_tenure_in_company,
        FLOOR(MONTHS_BETWEEN(ad.dt_reference, im.dt_original_hired)) AS months_tenure_in_company,
        DATEDIFF(ad.dt_reference, ad.dt_started) AS days_tenure_in_assignment,
        COALESCE(drc.count_direct_report, 0) AS count_direct_report,
        COALESCE(irc.count_indirect_report, 0) AS count_indirect_report,
        COALESCE(drc.count_direct_report, 0) + COALESCE(irc.count_indirect_report, 0) AS count_total_report,
        (
            COALESCE(jwst.is_leadership_job, FALSE)
            OR COALESCE(drc.count_direct_report, 0) > 0
        ) AS is_manager,
        COALESCE(jwst.is_leadership_team_job, FALSE) AS is_leadership_team_member,
        COALESCE(
            mh.sk_hierarchy_version IS NOT NULL
            AND (
                mh.assignment_number_l0 = ad.assignment_number
                OR mh.assignment_number_l1 = ad.assignment_number
            )
            AND TRY_CAST(jwst.band AS INT) >= 14,
            FALSE
        ) AS is_executive_team_member,
        CASE
            WHEN ad.dt_terminated IS NOT NULL
                AND ad.dt_reference >= ad.dt_terminated
                AND NOT COALESCE(im.is_transfer_termination, FALSE) THEN FALSE
            ELSE TRUE
        END AS is_active,
        pei.id_person IS NOT NULL AS has_emergency_contact,
        im.dt_original_hired IS NOT NULL
            AND im.dt_original_hired < ad.dt_started AS is_internal_transfer,
        COALESCE(im.is_transfer_termination, FALSE) AS is_transfer_termination,
        ad.is_future_hire,
        COALESCE(pap.id_assignment = ad.id_assignment, FALSE) AS is_primary_assignment_for_snapshot,
        lo.id_employee IS NOT NULL AS is_reorganization_termination,
        (
            LAST_DAY(ad.dt_reference) = ad.dt_reference
            OR ad.dt_reference = DATE('{load_start_date}')
            OR ad.dt_reference = ad.dt_series_end
        ) AS is_monthly_snapshot,
        ad.dt_reference = ad.dt_series_end AS is_current,
        im.dt_original_hired AS dt_original_hire,
        ad.dt_started AS dt_hired,
        ad.dt_terminated,
        ad.dt_notified_termination,
        ad.dt_reference AS dt_reference,
        LAST_DAY(ad.dt_reference) AS dt_month_reference,
        NOW() AS ts_load,
        ROW_NUMBER() OVER (
            PARTITION BY
                ad.id_assignment,
                ad.dt_reference
            ORDER BY
                cc.sk_cost_center_version NULLS LAST,
                pei.id_person_extra_info NULLS LAST,
                jwst.dt_valid_from DESC NULLS LAST,
                cv.dt_valid_from DESC NULLS LAST,
                all_assign.effective_sequence DESC NULLS LAST
        ) AS rn
    FROM
        assignments_daily AS ad
    INNER JOIN
        datalake_people.identifier_mapping AS im
            ON im.id_assignment = ad.id_assignment
    LEFT JOIN
        datalake_people.management_hierarchy AS mh
            ON mh.assignment_number = ad.assignment_number
            AND ad.dt_reference >= mh.dt_valid_from
            AND ad.dt_reference <= mh.dt_valid_to
    LEFT JOIN
        datalake_pin_core_clean.all_assignments AS all_assign
            ON all_assign.id_assignment = ad.id_assignment
            AND all_assign.assignment_type IN ('E', 'C')
            AND ad.dt_reference >= all_assign.dt_effective_started
            AND ad.dt_reference <= all_assign.dt_effective_ended
    LEFT JOIN
        direct_report_counts AS drc
            ON drc.manager_assignment_number = ad.assignment_number
            AND drc.dt_reference = ad.dt_reference
    LEFT JOIN
        indirect_report_counts AS irc
            ON irc.manager_assignment_number = ad.assignment_number
            AND irc.dt_reference = ad.dt_reference
    LEFT JOIN
        datalake_people.job_with_salary_table AS jwst
            ON jwst.id_job = all_assign.id_job
            AND ad.dt_reference >= jwst.dt_valid_from
            AND ad.dt_reference <= COALESCE(jwst.dt_valid_to, DATE('9999-12-31'))
    LEFT JOIN
        datalake_people.cost_center_history AS cc
            ON cc.id_organization = all_assign.id_organization
            AND ad.dt_reference >= cc.dt_valid_from
            AND ad.dt_reference <= cc.dt_valid_to
    LEFT JOIN
        datalake_pin_core_clean.people_extra_info AS pei
            ON pei.id_person = ad.id_person
            AND pei.information_type = 'Contatos de Emergência'
            AND ad.dt_reference >= pei.dt_effective_started
            AND ad.dt_reference <= pei.dt_effective_ended
    LEFT JOIN
        primary_assignment_per_person_day AS pap
            ON pap.id_person = ad.id_person
            AND pap.dt_reference = ad.dt_reference
    LEFT JOIN
        datalake_gsheets_people_clean.layoffs AS lo
            ON ad.assignment_number = UPPER(lo.id_employee)
    LEFT JOIN
        datalake_people.compensation_versions AS cv
            ON cv.assignment_number = ad.assignment_number
            AND ad.dt_reference >= cv.dt_valid_from
            AND ad.dt_reference <= cv.dt_valid_to
),
current_primary_assignment_ranked AS (
    SELECT
        asr.id_assignment,
        asr.dt_reference,
        ROW_NUMBER() OVER (
            PARTITION BY
                asr.id_person
            ORDER BY
                CASE
                    WHEN asr.is_active THEN 0
                    ELSE 1
                END,
                asr.dt_reference DESC,
                asr.assignment_number DESC
        ) AS person_primary_rn
    FROM
        assignment_snapshots_ranked AS asr
    WHERE
        asr.rn = 1
        AND asr.is_current = TRUE
        AND asr.is_primary_assignment_for_snapshot = TRUE
)
SELECT
    asr.id_assignment,
    asr.id_person,
    asr.id_organization,
    asr.id_business_unit,
    asr.id_job,
    asr.sk_job_version,
    asr.sk_cost_center_version,
    asr.sk_compensation_version,
    asr.business_unit_country,
    asr.sk_hierarchy_version,
    asr.sk_termination_event_definition,
    asr.sk_hired_date,
    asr.sk_terminated_date,
    asr.sk_reference_date,
    asr.person_number,
    asr.assignment_number,
    asr.manager_assignment_number,
    asr.hierarchy_level,
    asr.hierarchy_depth,
    asr.employment_status,
    asr.tenure_range,
    asr.days_tenure_in_company,
    asr.months_tenure_in_company,
    asr.days_tenure_in_assignment,
    asr.count_direct_report,
    asr.count_indirect_report,
    asr.count_total_report,
    asr.is_manager,
    asr.is_leadership_team_member,
    asr.is_executive_team_member,
    asr.is_active,
    asr.has_emergency_contact,
    asr.is_internal_transfer,
    asr.is_transfer_termination,
    asr.is_future_hire,
    asr.is_primary_assignment_for_snapshot,
    asr.is_reorganization_termination,
    asr.is_monthly_snapshot,
    asr.is_current,
    COALESCE(cpar.person_primary_rn = 1, FALSE) AS is_current_for_employee,
    asr.dt_original_hire,
    asr.dt_hired,
    asr.dt_terminated,
    asr.dt_notified_termination,
    asr.dt_reference,
    asr.dt_month_reference,
    asr.ts_load
FROM
    assignment_snapshots_ranked AS asr
LEFT JOIN
    current_primary_assignment_ranked AS cpar
        ON asr.id_assignment = cpar.id_assignment
        AND asr.dt_reference = cpar.dt_reference
WHERE
    asr.rn = 1
