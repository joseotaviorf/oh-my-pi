WITH
current_people AS (
    SELECT
        id_person,
        person_number
    FROM
        datalake_pin_core_clean.all_people
    WHERE
        dt_effective_ended >= DATE('{load_end_date}')
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_person ORDER BY dt_effective_ended DESC) = 1
),
current_assignments AS (
    SELECT
        id_assignment,
        id_period_of_service,
        id_person,
        assignment_number,
        legislation_code,
        assignment_type,
        assignment_status_type,
        dt_projected_started
    FROM
        datalake_pin_core_clean.all_assignments
    WHERE
        assignment_type IN ('E', 'C', 'P')
        AND dt_effective_ended >= DATE('{load_end_date}')
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_assignment ORDER BY dt_effective_ended DESC) = 1
),
current_names AS (
    SELECT
        id_person,
        documented_first_name,
        documented_last_name,
        documented_full_name,
        display_name,
        first_social_name,
        last_social_name
    FROM
        datalake_pin_core_clean.person_name
    WHERE
        name_type = 'GLOBAL'
        AND dt_effective_ended >= DATE('{load_end_date}')
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_person ORDER BY dt_effective_ended DESC) = 1
),
work_emails AS (
    SELECT
        id_person,
        email_address
    FROM
        datalake_pin_core_clean.email_address
    WHERE
        email_type = 'W1'
        AND (dt_ended >= DATE('{load_end_date}') OR dt_ended IS NULL)
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_person ORDER BY dt_ended DESC) = 1
),
personal_emails AS (
    SELECT
        id_person,
        email_address
    FROM
        datalake_pin_core_clean.email_address
    WHERE
        email_type = 'H1'
        AND (dt_ended >= DATE('{load_end_date}') OR dt_ended IS NULL)
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_person ORDER BY dt_ended DESC) = 1
),
test_users AS (
    SELECT
        id_person
    FROM
        datalake_pin_core_clean.external_application_identifier
    WHERE
        type_external_identifier = 'ID_ONDA1'
        AND dt_ended IS NULL
),
latest_periods_of_service AS (
    SELECT
        id_period_of_service,
        id_person,
        dt_started,
        ts_updated,
        year,
        month,
        day
    FROM
        datalake_pin_core_clean.periods_of_service
    WHERE
        dt_started IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY id_period_of_service
            ORDER BY
                ts_updated DESC,
                year DESC,
                month DESC,
                day DESC
        ) = 1
),
transfer_continuation_periods AS (
    SELECT
        aa_next.id_period_of_service
    FROM
        datalake_pin_core_clean.all_assignments AS aa
    INNER JOIN
        datalake_pin_core_clean.all_assignments AS aa_next
            ON aa_next.id_person = aa.id_person
            AND aa_next.assignment_sequence = aa.assignment_sequence + 1
    WHERE
        aa.assignment_status_type = 'INACTIVE'
        AND aa.action_code = 'GLB_TRANSFER'
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY aa_next.id_period_of_service
            ORDER BY aa.dt_effective_started ASC
        ) = 1
),
period_cycle_base AS (
    SELECT
        ps.id_person,
        ps.id_period_of_service,
        ps.dt_started,
        tcp.id_period_of_service IS NOT NULL AS is_transfer_continuation
    FROM
        latest_periods_of_service AS ps
    LEFT JOIN
        transfer_continuation_periods AS tcp
            ON ps.id_period_of_service = tcp.id_period_of_service
),
period_cycle_flags AS (
    SELECT
        id_person,
        id_period_of_service,
        dt_started,
        is_transfer_continuation,
        ROW_NUMBER() OVER (
            PARTITION BY id_person
            ORDER BY dt_started ASC, id_period_of_service ASC
        ) AS period_sequence
    FROM
        period_cycle_base
),
period_cycle_groups AS (
    SELECT
        id_person,
        id_period_of_service,
        dt_started,
        SUM(
            CASE
                WHEN period_sequence = 1 THEN 1
                WHEN is_transfer_continuation THEN 0
                ELSE 1
            END
        ) OVER (
            PARTITION BY id_person
            ORDER BY dt_started ASC, id_period_of_service ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS employment_cycle_group
    FROM
        period_cycle_flags
),
period_continuous_employment_cycles AS (
    SELECT
        id_person,
        id_period_of_service,
        MIN(dt_started) OVER (
            PARTITION BY id_person, employment_cycle_group
        ) AS dt_original_hired,
        MIN(id_period_of_service) OVER (
            PARTITION BY id_person, employment_cycle_group
        ) AS id_continuous_employment_cycle
    FROM
        period_cycle_groups
)
SELECT
    ca.id_assignment,
    ca.id_period_of_service,
    pcec.id_continuous_employment_cycle,
    ca.id_person,
    COALESCE(wr.registration, lr.legacy_registration) AS legacy_registration,
    ca.assignment_number,
    ca.legislation_code,
    cp.person_number,
    ca.assignment_type,
    ca.assignment_status_type,
    INITCAP(
      TRIM(REGEXP_REPLACE(REGEXP_REPLACE(cn.documented_first_name, '[^a-zA-ZÀ-ÿ ]', ''), ' +', ' '))
    ) AS documented_first_name,
    INITCAP(
      TRIM(REGEXP_REPLACE(REGEXP_REPLACE(cn.documented_last_name, '[^a-zA-ZÀ-ÿ ]', ''), ' +', ' '))
    ) AS documented_last_name,
    INITCAP(
      TRIM(REGEXP_REPLACE(REGEXP_REPLACE(cn.documented_full_name, '[^a-zA-ZÀ-ÿ ]', ''), ' +', ' '))
    ) AS documented_full_name,
    cn.display_name,
    INITCAP(
      TRIM(REGEXP_REPLACE(REGEXP_REPLACE(
        COALESCE(
          NULLIF(TRIM(CONCAT_WS(' ', cn.first_social_name, cn.last_social_name)), ''),
          NULLIF(TRIM(cn.display_name), ''),
          TRIM(cn.documented_full_name)
        ),
        '[^a-zA-ZÀ-ÿ ]', ''), ' +', ' '))
    ) AS name,
    LOWER(we.email_address) AS work_email,
    LOWER(pe.email_address) AS personal_email,
    tu.id_person IS NOT NULL AS is_user_test,
    ca.assignment_status_type = 'ACTIVE' AS is_active,
    ROW_NUMBER() OVER (
        PARTITION BY
            ca.id_person
        ORDER BY
            pp.dt_started DESC NULLS LAST
    ) = 1 AS is_person_latest_assignment,
    ca.dt_projected_started,
    pcec.dt_original_hired,
    pp.dt_started,
    pp.dt_actual_termination,
    pp.dt_notified_termination,
    NOW() AS ts_load
FROM
    current_people AS cp
INNER JOIN
    current_assignments AS ca
        ON cp.id_person = ca.id_person
INNER JOIN
    current_names AS cn
        ON cp.id_person = cn.id_person
LEFT JOIN
    work_emails AS we
        ON cp.id_person = we.id_person
LEFT JOIN
    personal_emails AS pe
        ON cp.id_person = pe.id_person
LEFT JOIN
    test_users AS tu
        ON cp.id_person = tu.id_person
LEFT JOIN
    datalake_hr_system_custom_clean.workers_registration AS wr
        ON ca.assignment_number = wr.assignment_number
LEFT JOIN
    datalake_gsheets_people_clean.legacy_registration AS lr
        ON LOWER(lr.work_email) = LOWER(we.email_address)
LEFT JOIN
    datalake_pin_core_clean.periods_of_service AS pp
        ON pp.id_period_of_service = ca.id_period_of_service
LEFT JOIN
    period_continuous_employment_cycles AS pcec
        ON pcec.id_person = ca.id_person
        AND pcec.id_period_of_service = ca.id_period_of_service
