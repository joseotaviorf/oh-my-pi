WITH
absence_entries_ranked AS (
    SELECT
        pe.id_per_absence_entry,
        pe.id_period_of_service,
        pe.id_absence_type,
        pe.dt_started,
        pe.dt_ended,
        pe.dt_period_started,
        pe.dt_period_ended,
        pe.days_duration,
        CAST(pe.vacation_cash_out_request AS INT) AS days_cash_out_requested,
        pe.advance_13th_salary,
        pe.approval_status_code,
        pe.absence_status_code,
        ROW_NUMBER() OVER (
            PARTITION BY pe.id_per_absence_entry
            ORDER BY pe.object_version_number DESC
        ) AS rn
    FROM
        datalake_pin_absence_clean.person_entry AS pe
    WHERE
        MAKE_DATE(pe.year, pe.month, pe.day) <= DATE('{load_start_date}')
),
absence_entries AS (
    SELECT
        id_per_absence_entry,
        id_period_of_service,
        id_absence_type,
        dt_started,
        dt_ended,
        dt_period_started,
        dt_period_ended,
        days_duration,
        days_cash_out_requested,
        advance_13th_salary,
        approval_status_code,
        absence_status_code
    FROM
        absence_entries_ranked
    WHERE
        rn = 1
),
base_ranked AS (
    SELECT
        ae.id_per_absence_entry,
        ae.id_period_of_service,
        ae.id_absence_type,
        ae.dt_started,
        ae.dt_ended,
        ae.dt_period_started,
        ae.dt_period_ended,
        ae.days_duration,
        ae.days_cash_out_requested,
        ae.advance_13th_salary,
        ae.approval_status_code,
        ae.absence_status_code,
        im.id_assignment,
        im.person_number,
        im.assignment_number,
        ROW_NUMBER() OVER (
            PARTITION BY ae.id_per_absence_entry
            ORDER BY im.dt_started DESC NULLS LAST, im.id_assignment DESC
        ) AS rn
    FROM
        absence_entries AS ae
    INNER JOIN
        datalake_people.identifier_mapping AS im
            ON ae.id_period_of_service = im.id_period_of_service
    WHERE
        NOT im.is_user_test
        AND im.assignment_type IN ('C', 'E')
),
base AS (
    SELECT
        id_per_absence_entry,
        id_period_of_service,
        id_absence_type,
        dt_started,
        dt_ended,
        dt_period_started,
        dt_period_ended,
        days_duration,
        days_cash_out_requested,
        advance_13th_salary,
        approval_status_code,
        absence_status_code,
        id_assignment,
        person_number,
        assignment_number
    FROM
        base_ranked
    WHERE
        rn = 1
)
SELECT
    b.id_per_absence_entry AS sk_absence_request,
    DATE_FORMAT(b.dt_started, 'yyyyMMdd') AS sk_absence_started_date,
    DATE_FORMAT(b.dt_ended, 'yyyyMMdd') AS sk_absence_ended_date,
    b.id_absence_type AS sk_absence_type,
    b.id_period_of_service AS sk_period_of_service,
    b.id_assignment AS sk_assignment,
    b.person_number,
    b.assignment_number,
    b.days_duration AS days_requested,
    b.days_cash_out_requested,
    b.approval_status_code = 'APPROVED'
        AND b.absence_status_code <> 'ORA_WITHDRAWN' AS is_approved,
    b.absence_status_code = 'ORA_WITHDRAWN' AS is_withdrawn,
    b.absence_status_code <> 'ORA_WITHDRAWN' AS is_valid,
    b.approval_status_code = 'APPROVED'
        AND b.absence_status_code <> 'ORA_WITHDRAWN'
        AND b.dt_started <= DATE('{load_start_date}') AS is_effective,
    CASE
        WHEN b.advance_13th_salary IN ('S', 'Y') THEN TRUE
        WHEN b.advance_13th_salary = 'N' THEN FALSE
        ELSE NULL
    END AS is_13th_salary_advance,
    b.dt_started AS dt_absence_started,
    b.dt_ended AS dt_absence_ended,
    b.dt_period_started AS dt_acquisitive_period_started,
    b.dt_period_ended AS dt_acquisitive_period_ended,
    NOW() AS ts_load
FROM
    base AS b
