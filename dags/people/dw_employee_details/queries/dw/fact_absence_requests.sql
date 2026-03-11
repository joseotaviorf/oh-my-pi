WITH
base AS (
    SELECT
        pe.id_per_absence_entry,
        pe.id_absence_type,
        pe.dt_started,
        pe.dt_ended,
        pe.days_duration,
        pe.approval_status_code,
        pe.absence_status_code,
        pe.object_version_number,
        im.person_number,
        im.assignment_number
    FROM
        datalake_pin_absence_clean.person_entry AS pe
    INNER JOIN
        datalake_people_core.identifier_mapping AS im
            ON pe.id_period_of_service = im.id_period_of_service
    WHERE
        NOT im.is_user_test
        AND im.assignment_type IN ('C', 'E')
        AND MAKE_DATE(pe.year, pe.month, pe.day) <= CURRENT_DATE()
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY pe.id_per_absence_entry
            ORDER BY pe.object_version_number DESC
        ) = 1
)
SELECT
    b.id_per_absence_entry AS sk_absence_request,
    DATE_FORMAT(b.dt_started, 'yyyyMMdd') AS sk_absence_started_date,
    DATE_FORMAT(b.dt_ended, 'yyyyMMdd') AS sk_absence_ended_date,
    b.id_absence_type AS sk_absence_type,
    b.person_number,
    b.assignment_number,
    b.days_duration AS days_requested,
    b.approval_status_code = 'APPROVED'
        AND b.absence_status_code <> 'ORA_WITHDRAWN' AS is_approved,
    b.absence_status_code = 'ORA_WITHDRAWN' AS is_withdrawn,
    b.absence_status_code <> 'ORA_WITHDRAWN' AS is_valid,
    b.approval_status_code = 'APPROVED'
        AND b.absence_status_code <> 'ORA_WITHDRAWN'
        AND b.dt_started <= CURRENT_DATE() AS is_effective,
    b.dt_started AS dt_absence_started,
    b.dt_ended AS dt_absence_ended,
    NOW() AS ts_load
FROM
    base AS b
