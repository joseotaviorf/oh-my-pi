WITH deduped_punches AS (
    SELECT
        id_punch,
        id_punch_key,
        id_employee,
        id_employee_profile,
        id_employee_external,
        id_created_by,
        id_created_by_profile,
        id_created_by_external,
        id_location,
        punch_key,
        timezone_name,
        punch_type,
        punch_status,
        punch_reason,
        punch_source,
        validation_status,
        late_reason,
        duration_minutes,
        is_manual_adjustment,
        is_custom_location,
        is_force_validated,
        dt_punched,
        punch_time_local,
        ts_load,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_punch
            ORDER BY
                ts_load DESC NULLS LAST,
                year DESC,
                month DESC,
                day DESC
        ) AS row_number_latest
    FROM
        datalake_oitchau_clean.punches
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}')
            AND DATE('{load_end_date}')
),
latest_punches AS (
    SELECT
        id_punch,
        id_punch_key,
        id_employee,
        id_employee_profile,
        id_employee_external,
        id_created_by,
        id_created_by_profile,
        id_created_by_external,
        id_location,
        punch_key,
        timezone_name,
        punch_type,
        punch_status,
        punch_reason,
        punch_source,
        validation_status,
        late_reason,
        duration_minutes,
        is_manual_adjustment,
        is_custom_location,
        is_force_validated,
        dt_punched,
        punch_time_local,
        ts_load
    FROM
        deduped_punches
    WHERE
        row_number_latest = 1
),
deduped_employees AS (
    SELECT
        id_employee_profile,
        id_external,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_employee_profile
            ORDER BY
                ts_load DESC NULLS LAST,
                year DESC,
                month DESC,
                day DESC
        ) AS row_number_latest
    FROM
        datalake_oitchau_clean.employees
),
latest_employees AS (
    SELECT
        id_employee_profile,
        id_external
    FROM
        deduped_employees
    WHERE
        row_number_latest = 1
),
punches_with_person AS (
    SELECT
        lp.id_punch,
        lp.id_punch_key,
        lp.id_employee,
        lp.id_employee_profile,
        lp.id_employee_external,
        lp.id_created_by,
        lp.id_created_by_profile,
        lp.id_created_by_external,
        lp.id_location,
        lp.punch_key,
        lp.timezone_name,
        lp.punch_type,
        lp.punch_status,
        lp.punch_reason,
        lp.punch_source,
        lp.validation_status,
        lp.late_reason,
        lp.duration_minutes,
        lp.is_manual_adjustment,
        lp.is_custom_location,
        lp.is_force_validated,
        lp.dt_punched,
        lp.punch_time_local,
        im.id_person AS sk_employee,
        im.person_number
    FROM
        latest_punches AS lp
    INNER JOIN
        latest_employees AS le
            ON le.id_employee_profile = lp.id_employee_profile
    INNER JOIN
        datalake_people.identifier_mapping AS im
            ON TRIM(CAST(le.id_external AS STRING)) = TRIM(CAST(im.person_number AS STRING))
            AND NOT im.is_user_test
            AND im.is_person_latest_assignment
    WHERE
        lp.id_punch IS NOT NULL
)
SELECT
    XXHASH64(
        CAST(pp.id_punch AS STRING)
    ) AS sk_employee_punch,
    pp.sk_employee,
    dd.sk_date AS sk_punched_date,
    pp.id_punch,
    pp.id_punch_key,
    pp.id_employee_profile,
    pp.id_employee,
    pp.id_employee_external,
    pp.id_created_by_profile,
    pp.id_created_by_external,
    pp.id_created_by,
    pp.id_location,
    pp.person_number,
    pp.punch_key,
    pp.timezone_name,
    pp.punch_type,
    pp.punch_status,
    pp.punch_reason,
    pp.punch_source,
    pp.validation_status,
    pp.late_reason,
    pp.duration_minutes,
    pp.is_manual_adjustment,
    pp.is_custom_location,
    pp.is_force_validated,
    pp.dt_punched,
    CAST(pp.punch_time_local AS TIMESTAMP) AS ts_punched,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    punches_with_person AS pp
INNER JOIN
    dw_public.dim_date AS dd
        ON dd.date = pp.dt_punched
