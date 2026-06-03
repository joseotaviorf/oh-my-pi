WITH
-- Base assignments from identifier_mapping (termination dates from assignment_termination when available)
assignments_base AS (
    SELECT
        im.id_assignment,
        im.id_person,
        im.person_number,
        im.assignment_number,
        COALESCE(im.dt_started, at.dt_hired) AS dt_started,
        COALESCE(im.dt_actual_termination, at.dt_terminated) AS dt_actual_termination,
        COALESCE(im.dt_notified_termination, at.dt_notified) AS dt_notified
    FROM
        datalake_people.identifier_mapping AS im
    LEFT JOIN
        datalake_people.assignment_termination AS at
            ON at.id_assignment = im.id_assignment
    WHERE
        NOT im.is_user_test
        AND im.assignment_type IN ('E', 'C')
),
-- Assignment context: current org/job, termination events, managers, first hire
current_assignments AS (
    SELECT
        id_assignment,
        id_organization,
        id_business_unit,
        id_job,
        career_track
    FROM
        datalake_pin_core_clean.all_assignments
    WHERE
        assignment_type IN ('E', 'C')
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                id_assignment
            ORDER BY
                dt_effective_ended DESC
        ) = 1
),
termination_assignments AS (
    SELECT
        aa.id_assignment,
        aa.id_action_occurrence
    FROM
        datalake_pin_core_clean.all_assignments AS aa
    WHERE
        aa.is_primary
        AND aa.assignment_type IN ('E', 'C')
        AND aa.action_code IN (
            'TERMINATION',
            'RESIGNATION',
            'DEATH',
            'GLB_TRANSFER',
            'EXPATRIADO'
        )
        AND aa.assignment_status_type = 'INACTIVE'
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                aa.id_assignment
            ORDER BY
                aa.dt_effective_ended ASC
        ) = 1
),
termination_event_definitions AS (
    SELECT
        ta.id_assignment,
        CONCAT(
            CAST(ao.id_action AS STRING),
            '-',
            CAST(ao.id_action_reason AS STRING)
        ) AS id_event_definition
    FROM
        termination_assignments AS ta
    INNER JOIN
        datalake_pin_core_clean.action_occurrence AS ao
            ON ao.id_action_occurrence = ta.id_action_occurrence
),
first_hire_per_person AS (
    SELECT
        ps.id_person,
        MIN(ps.dt_started) AS dt_original_hire
    FROM
        datalake_pin_core_clean.periods_of_service AS ps
    GROUP BY
        ps.id_person
),
assignments_with_dates AS (
    SELECT
        ab.id_assignment,
        ab.id_person,
        ab.person_number,
        ab.assignment_number,
        ab.dt_started,
        ab.dt_actual_termination,
        ab.dt_notified,
        SEQUENCE(
            ab.dt_started,
            COALESCE(
                NULLIF(ab.dt_actual_termination, DATE('4712-12-31')),
                CURRENT_DATE()
            )
        ) AS dt_reference_array
    FROM
        assignments_base AS ab
    WHERE
        ab.dt_started IS NOT NULL
),
assignments_daily AS (
    SELECT
        awd.id_assignment,
        awd.id_person,
        awd.person_number,
        awd.assignment_number,
        awd.dt_started,
        awd.dt_actual_termination,
        awd.dt_notified,
        dt_reference,
        (
            dt_reference < awd.dt_started
        ) AS is_future_hire
    FROM
        assignments_with_dates AS awd
    LATERAL VIEW EXPLODE(dt_reference_array) dt_ref AS dt_reference
),
primary_assignment_per_person_day AS (
    SELECT
        ad.id_person,
        ad.dt_reference,
        ad.id_assignment
    FROM
        assignments_daily AS ad
    QUALIFY
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
        ) = 1
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
            AND ad.dt_reference <= COALESCE(
                NULLIF(mh.dt_valid_to, DATE('4712-12-31')),
                DATE('9999-12-31')
            )
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
)
SELECT
    ad.id_assignment,
    ad.id_person,
    ca.id_organization,
    ca.id_business_unit,
    ca.id_job,
    MD5(
        CONCAT_WS(
            '|',
            CAST(jwst.id_job AS STRING),
            CAST(jwst.dt_valid_from AS STRING)
        )
    ) AS sk_job_version,
    cc.sk_cost_center_version,
    jwst.country AS business_unit_country,
    mh.sk_hierarchy_version,
    ted.id_event_definition AS sk_termination_event_definition,
    DATE_FORMAT(ad.dt_started, 'yyyyMMdd') AS sk_hired_date,
    DATE_FORMAT(
        COALESCE(
            NULLIF(ad.dt_actual_termination, DATE('4712-12-31')),
            DATE('9999-12-31')
        ),
        'yyyyMMdd'
    ) AS sk_terminated_date,
    DATE_FORMAT(ad.dt_reference, 'yyyyMMdd') AS sk_reference_date,
    ad.person_number,
    ad.assignment_number,
    mh.manager_assignment_number,
    mh.hierarchy_level,
    mh.hierarchy_depth,
    CASE
        WHEN all_assign.assignment_status_type = 'ACTIVE'
            THEN 'Active'
        ELSE 'Terminated'
    END AS employment_status,
    CASE
        WHEN FLOOR(MONTHS_BETWEEN(ad.dt_reference, fh.dt_original_hire)) IS NULL THEN CAST(NULL AS STRING)
        WHEN FLOOR(MONTHS_BETWEEN(ad.dt_reference, fh.dt_original_hire)) < 3  THEN '< 3 months'
        WHEN FLOOR(MONTHS_BETWEEN(ad.dt_reference, fh.dt_original_hire)) < 12 THEN '3-11 months'
        WHEN FLOOR(MONTHS_BETWEEN(ad.dt_reference, fh.dt_original_hire)) < 36 THEN '1-2 years'
        WHEN FLOOR(MONTHS_BETWEEN(ad.dt_reference, fh.dt_original_hire)) < 60 THEN '3-4 years'
        ELSE '5+ years'
    END AS tenure_range,
    DATEDIFF(ad.dt_reference, fh.dt_original_hire) AS days_tenure_in_company,
    FLOOR(MONTHS_BETWEEN(ad.dt_reference, fh.dt_original_hire)) AS months_tenure_in_company,
    DATEDIFF(ad.dt_reference, ad.dt_started) AS days_tenure_in_assignment,
    COALESCE(drc.count_direct_report, 0) AS count_direct_report,
    COALESCE(irc.count_indirect_report, 0) AS count_indirect_report,
    COALESCE(drc.count_direct_report, 0) + COALESCE(irc.count_indirect_report, 0) AS count_total_report,
    (
        ca.career_track = 'L'
        OR COALESCE(drc.count_direct_report, 0) > 0
    ) AS is_manager,
    COALESCE(
        jwst.band = 'EXEC' OR TRY_CAST(jwst.band AS INT) >= 10,
        FALSE
    ) AS is_member_lt,
    COALESCE(
        mh.sk_hierarchy_version IS NOT NULL
        AND (
            mh.assignment_number_l0 = ad.assignment_number
            OR mh.assignment_number_l1 = ad.assignment_number
        )
        AND TRY_CAST(jwst.band AS INT) >= 14,
        FALSE
    ) AS is_member_et,
    IF(all_assign.assignment_status_type = 'ACTIVE', TRUE, FALSE) AS is_active,
    IF(
        ad.dt_actual_termination IS NOT NULL
        AND ad.dt_actual_termination <> DATE('4712-12-31'),
        TRUE,
        FALSE
    ) AS is_terminated,
    pei.id_person IS NOT NULL AS has_emergency_contact,
    fh.dt_original_hire IS NOT NULL
        AND fh.dt_original_hire < ad.dt_started AS is_internal_transfer,
    ad.is_future_hire,
    COALESCE(pap.id_assignment = ad.id_assignment, FALSE) AS is_primary_assignment_for_snapshot,
    COALESCE(LOWER(TRIM(lo.is_layoff)) = 'sim', FALSE) AS is_reorganization_termination,
    COALESCE(
        LAST_DAY(ad.dt_reference) = ad.dt_reference
        OR ad.dt_reference = CURRENT_DATE()
        OR ad.dt_reference = NULLIF(ad.dt_actual_termination, DATE('4712-12-31')),
        FALSE
    ) AS is_monthly_snapshot,
    ad.dt_reference = LEAST(
        COALESCE(
            NULLIF(ad.dt_actual_termination, DATE('4712-12-31')),
            CURRENT_DATE()
        ),
        CURRENT_DATE()
    ) AS is_current,
    fh.dt_original_hire,
    ad.dt_started AS dt_hired,
    COALESCE(
        NULLIF(ad.dt_actual_termination, DATE('4712-12-31')),
        DATE('9999-12-31')
    ) AS dt_terminated,
    COALESCE(
        NULLIF(ad.dt_notified, DATE('4712-12-31')),
        DATE('9999-12-31')
    ) AS dt_notified,
    ad.dt_reference AS dt_reference,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    assignments_daily AS ad
INNER JOIN
    current_assignments AS ca
        ON ca.id_assignment = ad.id_assignment
LEFT JOIN
    termination_event_definitions AS ted
        ON ted.id_assignment = ad.id_assignment
LEFT JOIN
    first_hire_per_person AS fh
        ON fh.id_person = ad.id_person
LEFT JOIN
    datalake_people.management_hierarchy AS mh
        ON mh.assignment_number = ad.assignment_number
        AND ad.dt_reference >= mh.dt_valid_from
        AND ad.dt_reference <= COALESCE(
            NULLIF(mh.dt_valid_to, DATE('4712-12-31')),
            DATE('9999-12-31')
        )
LEFT JOIN
    datalake_pin_core_clean.all_assignments AS all_assign
        ON all_assign.id_assignment = ad.id_assignment
        AND all_assign.assignment_type IN ('E', 'C')
        AND ad.dt_reference >= all_assign.dt_effective_started
        AND ad.dt_reference <= COALESCE(
            NULLIF(all_assign.dt_effective_ended, DATE('4712-12-31')),
            DATE('9999-12-31')
        )
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
    ON jwst.id_job = ca.id_job
    AND ad.dt_reference >= jwst.dt_valid_from
    AND ad.dt_reference <= COALESCE(
        NULLIF(jwst.dt_valid_to, DATE('4712-12-31')),
        DATE('9999-12-31')
    )
LEFT JOIN
    datalake_people.cost_center_history AS cc
    ON cc.id_organization = ca.id_organization
    AND ad.dt_reference >= cc.dt_valid_from
    AND ad.dt_reference <= COALESCE(
        NULLIF(cc.dt_valid_to, DATE('4712-12-31')),
        DATE('9999-12-31')
    )
LEFT JOIN
    datalake_pin_core_clean.people_extra_info AS pei
        ON pei.id_person = ad.id_person
        AND pei.information_type = 'Contatos de Emergência'
        AND ad.dt_reference >= pei.dt_effective_started
        AND ad.dt_reference <= COALESCE(
            NULLIF(pei.dt_effective_ended, DATE('4712-12-31')),
            DATE('9999-12-31')
        )
LEFT JOIN
    primary_assignment_per_person_day AS pap
        ON pap.id_person = ad.id_person
        AND pap.dt_reference = ad.dt_reference
LEFT JOIN
    datalake_gsheets_people_clean.layoffs AS lo
        ON ad.assignment_number = UPPER(lo.id_employee)
QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY
            ad.id_assignment,
            ad.dt_reference
        ORDER BY
            cc.sk_cost_center_version NULLS LAST,
            pei.id_person_extra_info NULLS LAST,
            jwst.dt_valid_from DESC NULLS LAST,
            all_assign.effective_sequence DESC NULLS LAST
    ) = 1
