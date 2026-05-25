WITH
vacation AS (
    SELECT
        id_period_of_service,
        period,
        SUM(days_duration) AS days_absence,
        SUM(vacation_cash_out_request) AS days_cash_out
    FROM
        datalake_pin_absence_clean.person_entry
    WHERE
        approval_status_code <> 'DENIED'
        AND absence_status_code = 'SUBMITTED'
        AND period IS NOT NULL
    GROUP BY
        id_period_of_service,
        period
),
base AS (
    SELECT
        aei.id_assignment_extra_info,
        ei.person_number,
        ei.assignment_number,
        aei.dt_period_started,
        aei.dt_period_ended,
        aei.type_or_status,
        aei.days_vacation_acquired,
        COALESCE(v.days_absence, 0) AS days_absence,
        COALESCE(v.days_cash_out, 0) AS days_cash_out
    FROM
        datalake_pin_core_clean.assignment_extra_info AS aei
    INNER JOIN
        datalake_people.identifier_mapping AS ei
            ON ei.id_assignment = aei.id_assignment
    LEFT JOIN
        vacation AS v
            ON aei.period = v.period
            AND ei.id_period_of_service = v.id_period_of_service
    WHERE
        NOT ei.is_user_test
        AND ei.assignment_type IN ('C', 'E')
        AND aei.dt_effective_ended = DATE('4712-12-31')
        AND aei.information_type LIKE 'Saldo de F%'
)
SELECT
    b.id_assignment_extra_info AS sk_vacation_balance,
    DATE_FORMAT(b.dt_period_started, 'yyyyMMdd') AS sk_vacation_period_started_date,
    DATE_FORMAT(b.dt_period_ended, 'yyyyMMdd') AS sk_vacation_period_ended_date,
    DATE_FORMAT(b.dt_period_ended + 365, 'yyyyMMdd') AS sk_vacation_period_expiration_date,
    b.person_number,
    b.assignment_number,
    CASE b.type_or_status
        WHEN 'FECHADO' THEN 'Closed'
        WHEN 'EM ANDAMENTO' THEN 'In progress'
        WHEN 'ABERTO' THEN 'Open'
        WHEN 'PRESCRITO' THEN 'Expired'
        ELSE b.type_or_status
    END AS vacation_status,
    ROW_NUMBER() OVER (
        PARTITION BY b.person_number, b.assignment_number
        ORDER BY b.dt_period_started
    ) AS vacation_period_order,
    b.days_vacation_acquired AS days_accrued,
    b.days_absence AS days_taken_absence,
    b.days_cash_out AS days_taken_cash_out,
    b.days_absence + b.days_cash_out AS days_taken_total,
    COALESCE(
        b.days_vacation_acquired - b.days_absence - b.days_cash_out,
        0
    ) AS days_balance,
    GREATEST(30 - (b.days_absence + b.days_cash_out), 0) AS days_to_be_accrued,
    COALESCE(
        b.days_vacation_acquired - b.days_absence - b.days_cash_out,
        0
    ) > 0 AS has_available_days,
    MAX(b.dt_period_started) OVER (
        PARTITION BY b.person_number, b.assignment_number
    ) = b.dt_period_started AS is_latest_period,
    b.type_or_status = 'FECHADO' AS is_vacation_period_closed,
    b.dt_period_started AS dt_vacation_period_started,
    b.dt_period_ended AS dt_vacation_period_ended,
    b.dt_period_ended + 365 AS dt_vacation_period_expiration,
    NOW() AS ts_load
FROM
    base AS b
