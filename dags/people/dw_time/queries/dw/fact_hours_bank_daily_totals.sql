WITH hours_bank_snapshots_ranked AS (
    SELECT
        id_employee_profile,
        dt_balanced AS dt_hours_bank_balanced,
        FROM_JSON(
            TO_JSON(hours_bank_totals),
            'MAP<STRING, BIGINT>'
        ) AS hours_bank_totals_map,
        ts_load,
        year,
        month,
        day,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_employee_profile,
                dt_balanced
            ORDER BY
                ts_load DESC NULLS LAST,
                year DESC,
                month DESC,
                day DESC
        ) AS row_number_latest
    FROM
        datalake_oitchau_clean.hoursbank_totals
    WHERE
        dt_balanced <= DATE_SUB(DATE('{load_end_date}'), 1)
),
hours_bank_snapshots AS (
    SELECT
        id_employee_profile,
        dt_hours_bank_balanced,
        hours_bank_totals_map
    FROM
        hours_bank_snapshots_ranked
    WHERE
        row_number_latest = 1
        AND hours_bank_totals_map IS NOT NULL
        AND SIZE(hours_bank_totals_map) > 0
),
api_daily_balance AS (
    SELECT
        id_employee_profile,
        dt_hours_bank_balanced,
        AGGREGATE(
            MAP_VALUES(hours_bank_totals_map),
            CAST(0 AS BIGINT),
            (acc, minutes_value) -> acc + COALESCE(minutes_value, CAST(0 AS BIGINT))
        ) AS sum_minutes_balance_api
    FROM
        hours_bank_snapshots
),
employee_registration_ranked AS (
    SELECT
        id_employee_profile,
        id_external,
        subsidiary_name,
        is_active,
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
employee_registration AS (
    SELECT
        id_employee_profile,
        TRIM(CAST(id_external AS STRING)) AS id_external,
        subsidiary_name,
        is_active
    FROM
        employee_registration_ranked
    WHERE
        row_number_latest = 1
),
employee_with_mapping AS (
    SELECT
        employee_reg.id_employee_profile,
        employee_reg.subsidiary_name,
        employee_reg.is_active,
        identifier_mapping.id_person AS sk_employee,
        TRIM(CAST(identifier_mapping.person_number AS STRING)) AS person_number
    FROM
        employee_registration AS employee_reg
    INNER JOIN
        datalake_people.identifier_mapping AS identifier_mapping
            ON employee_reg.id_external = TRIM(CAST(identifier_mapping.person_number AS STRING))
            AND NOT identifier_mapping.is_user_test
            AND identifier_mapping.is_person_latest_assignment
),
api_with_employee AS (
    SELECT
        employee_dim.sk_employee,
        employee_dim.person_number,
        employee_dim.id_employee_profile,
        employee_dim.subsidiary_name,
        employee_dim.is_active,
        api_balance.dt_hours_bank_balanced,
        api_balance.sum_minutes_balance_api
    FROM
        api_daily_balance AS api_balance
    INNER JOIN
        employee_with_mapping AS employee_dim
            ON api_balance.id_employee_profile = employee_dim.id_employee_profile
),
employee_date_bounds_unfiltered AS (
    SELECT
        sk_employee,
        person_number,
        id_employee_profile,
        subsidiary_name,
        GREATEST(
            MIN(dt_hours_bank_balanced),
            CAST(DATE_TRUNC('MONTH', DATE('{load_end_date}')) AS DATE)
        ) AS dt_spine_started,
        CASE
            WHEN MAX(COALESCE(is_active, TRUE))
                THEN GREATEST(
                    MAX(dt_hours_bank_balanced),
                    DATE_SUB(DATE('{load_end_date}'), 1)
                )
            ELSE MAX(dt_hours_bank_balanced)
        END AS dt_spine_ended
    FROM
        api_with_employee
    GROUP BY
        sk_employee,
        person_number,
        id_employee_profile,
        subsidiary_name
),
employee_date_bounds AS (
    SELECT
        sk_employee,
        person_number,
        id_employee_profile,
        subsidiary_name,
        dt_spine_started,
        dt_spine_ended
    FROM
        employee_date_bounds_unfiltered
    WHERE
        dt_spine_ended >= dt_spine_started
),
employee_date_series AS (
    SELECT
        employee_bounds.sk_employee,
        employee_bounds.person_number,
        employee_bounds.id_employee_profile,
        employee_bounds.subsidiary_name,
        EXPLODE(
            SEQUENCE(
                employee_bounds.dt_spine_started,
                employee_bounds.dt_spine_ended,
                INTERVAL 1 DAY
            )
        ) AS dt_hours_bank_balanced
    FROM
        employee_date_bounds AS employee_bounds
),
employee_calendar_spine AS (
    SELECT
        employee_series.sk_employee,
        employee_series.person_number,
        employee_series.id_employee_profile,
        employee_series.subsidiary_name,
        employee_series.dt_hours_bank_balanced,
        calendar_date.sk_date AS sk_balance_date
    FROM
        employee_date_series AS employee_series
    INNER JOIN
        dw_public.dim_date AS calendar_date
            ON calendar_date.date = employee_series.dt_hours_bank_balanced
),
spine_with_api AS (
    SELECT
        spine.sk_employee,
        spine.person_number,
        spine.subsidiary_name,
        spine.dt_hours_bank_balanced,
        spine.sk_balance_date,
        api_balance.sum_minutes_balance_api,
        LAST_VALUE(api_balance.sum_minutes_balance_api, TRUE) OVER (
            PARTITION BY
                spine.sk_employee
            ORDER BY
                spine.dt_hours_bank_balanced
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sum_minutes_balance_api_carried
    FROM
        employee_calendar_spine AS spine
    LEFT JOIN
        api_with_employee AS api_balance
            ON spine.sk_employee = api_balance.sk_employee
            AND spine.dt_hours_bank_balanced = api_balance.dt_hours_bank_balanced
),
daily_totals AS (
    SELECT
        sk_employee,
        person_number,
        subsidiary_name,
        dt_hours_bank_balanced,
        sk_balance_date,
        sum_minutes_balance_api,
        sum_minutes_balance_api_carried AS sum_minutes_running_balance,
        sum_minutes_balance_api_carried - LAG(sum_minutes_balance_api_carried) OVER (
            PARTITION BY
                sk_employee
            ORDER BY
                dt_hours_bank_balanced
        ) AS amount_minutes_delta_day_over_day,
        CAST(
            (
                DATE_TRUNC('MONTH', dt_hours_bank_balanced) < ADD_MONTHS(
                    DATE_TRUNC('MONTH', DATE('{load_end_date}')),
                    -1
                )
                AND dt_hours_bank_balanced = LAST_DAY(dt_hours_bank_balanced)
            ) AS BOOLEAN
        ) AS is_closed,
        CAST(DATE_TRUNC('month', dt_hours_bank_balanced) AS DATE) AS dt_reference_month
    FROM
        spine_with_api
    WHERE
        sum_minutes_balance_api_carried IS NOT NULL
)
SELECT
    MD5(CONCAT_WS(
        ',',
        daily_totals.person_number,
        CAST(daily_totals.dt_hours_bank_balanced AS STRING)
    )) AS sk_hours_bank_daily_total,
    daily_totals.sk_employee,
    daily_totals.sk_balance_date,
    daily_totals.person_number,
    daily_totals.subsidiary_name,
    daily_totals.sum_minutes_balance_api,
    daily_totals.amount_minutes_delta_day_over_day,
    daily_totals.sum_minutes_running_balance,
    daily_totals.is_closed,
    daily_totals.dt_reference_month,
    daily_totals.dt_hours_bank_balanced,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    daily_totals
