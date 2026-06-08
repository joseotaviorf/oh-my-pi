WITH closed_balance_snapshots_ranked AS (
    SELECT
        id_employee_profile,
        dt_balanced AS dt_hours_bank_balanced,
        FROM_JSON(
            TO_JSON(hours_bank_totals),
            'MAP<STRING, BIGINT>'
        ) AS hours_bank_totals_map,
        TRUE AS is_closed,
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
        datalake_oitchau_clean.hoursbank_totals_month_close
),
closed_balance_snapshots AS (
    SELECT
        id_employee_profile,
        dt_hours_bank_balanced,
        hours_bank_totals_map,
        is_closed
    FROM
        closed_balance_snapshots_ranked
    WHERE
        row_number_latest = 1
),
latest_closed_balance_by_employee AS (
    SELECT
        id_employee_profile,
        MAX(dt_hours_bank_balanced) AS dt_latest_closed_balance
    FROM
        closed_balance_snapshots
    WHERE
        hours_bank_totals_map IS NOT NULL
        AND SIZE(hours_bank_totals_map) > 0
    GROUP BY
        id_employee_profile
),
open_balance_snapshots_ranked AS (
    SELECT
        id_employee_profile,
        dt_balanced AS dt_hours_bank_balanced,
        FROM_JSON(
            TO_JSON(hours_bank_totals),
            'MAP<STRING, BIGINT>'
        ) AS hours_bank_totals_map,
        FALSE AS is_closed,
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
),
open_balance_snapshots AS (
    SELECT
        open_balance.id_employee_profile,
        open_balance.dt_hours_bank_balanced,
        open_balance.hours_bank_totals_map,
        open_balance.is_closed
    FROM
        open_balance_snapshots_ranked AS open_balance
    LEFT JOIN
        latest_closed_balance_by_employee AS latest_closed
            ON latest_closed.id_employee_profile = open_balance.id_employee_profile
    WHERE
        open_balance.row_number_latest = 1
        AND open_balance.dt_hours_bank_balanced > COALESCE(
            latest_closed.dt_latest_closed_balance,
            DATE('1900-01-01')
        )
),
hours_bank_snapshots AS (
    SELECT
        id_employee_profile,
        dt_hours_bank_balanced,
        hours_bank_totals_map,
        is_closed
    FROM
        closed_balance_snapshots
    UNION ALL
    SELECT
        id_employee_profile,
        dt_hours_bank_balanced,
        hours_bank_totals_map,
        is_closed
    FROM
        open_balance_snapshots
),
employee_registration_ranked AS (
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
employee_registration AS (
    SELECT
        id_employee_profile,
        id_external
    FROM
        employee_registration_ranked
    WHERE
        row_number_latest = 1
),
hours_bank_with_employee AS (
    SELECT
        hours_bank.dt_hours_bank_balanced,
        hours_bank.hours_bank_totals_map,
        hours_bank.is_closed,
        dim_employee.sk_employee,
        TRIM(CAST(dim_employee.person_number AS STRING)) AS person_number
    FROM
        hours_bank_snapshots AS hours_bank
    INNER JOIN
        employee_registration AS employee_reg
            ON employee_reg.id_employee_profile = hours_bank.id_employee_profile
    INNER JOIN
        dw_people.dim_employee AS dim_employee
            ON TRIM(CAST(employee_reg.id_external AS STRING)) = TRIM(CAST(dim_employee.person_number AS STRING))
    WHERE
        hours_bank.hours_bank_totals_map IS NOT NULL
        AND SIZE(hours_bank.hours_bank_totals_map) > 0
),
hours_bank_rule_lines AS (
    SELECT
        hours_bank_employee.sk_employee,
        hours_bank_employee.person_number,
        hours_bank_employee.dt_hours_bank_balanced,
        hours_bank_employee.is_closed,
        EXPLODE(hours_bank_employee.hours_bank_totals_map) AS (
            hours_bank_rule_key,
            minutes_balance_rule_raw
        )
    FROM
        hours_bank_with_employee AS hours_bank_employee
),
hours_bank_lines_with_hourly_rate_ranked AS (
    SELECT
        hours_bank_rule.sk_employee,
        hours_bank_rule.person_number,
        hours_bank_rule.dt_hours_bank_balanced,
        hours_bank_rule.is_closed,
        hours_bank_rule.hours_bank_rule_key,
        hours_bank_rule.minutes_balance_rule_raw,
        cost_window.sk_employee_cost_window,
        cost_window.hourly_rate_amount AS hourly_rate_applied,
        cost_window.dt_hourly_cost_segment_started AS dt_hourly_rate_segment_started,
        cost_window.dt_hourly_cost_segment_ended AS dt_hourly_rate_segment_ended,
        CAST(
            CASE
                WHEN cost_window.hourly_rate_amount IS NULL
                    THEN NULL
                ELSE (CAST(hours_bank_rule.minutes_balance_rule_raw AS BIGINT) / 60.0)
                    * cost_window.hourly_rate_amount
            END AS DECIMAL(18, 4)
        ) AS estimated_balance_cost_amount,
        ROW_NUMBER() OVER (
            PARTITION BY
                hours_bank_rule.sk_employee,
                hours_bank_rule.dt_hours_bank_balanced,
                hours_bank_rule.hours_bank_rule_key
            ORDER BY
                cost_window.dt_hourly_cost_segment_started DESC NULLS LAST,
                cost_window.dt_hourly_cost_segment_ended ASC NULLS LAST
        ) AS row_number_latest
    FROM
        hours_bank_rule_lines AS hours_bank_rule
    LEFT JOIN
        dw_time.fact_employee_hourly_cost_windows AS cost_window
            ON hours_bank_rule.sk_employee = cost_window.sk_employee
            AND UPPER(cost_window.cost_segment_status) = 'ACTIVE'
            AND hours_bank_rule.dt_hours_bank_balanced >= cost_window.dt_hourly_cost_segment_started
            AND (
                cost_window.dt_hourly_cost_segment_ended IS NULL
                OR hours_bank_rule.dt_hours_bank_balanced <= cost_window.dt_hourly_cost_segment_ended
            )
),
hours_bank_lines_with_hourly_rate AS (
    SELECT
        sk_employee,
        person_number,
        dt_hours_bank_balanced,
        is_closed,
        hours_bank_rule_key,
        minutes_balance_rule_raw,
        sk_employee_cost_window,
        hourly_rate_applied,
        dt_hourly_rate_segment_started,
        dt_hourly_rate_segment_ended,
        estimated_balance_cost_amount
    FROM
        hours_bank_lines_with_hourly_rate_ranked
    WHERE
        row_number_latest = 1
)
SELECT
    MD5(CONCAT_WS(
        ',',
        CAST(hours_bank_cost.sk_employee AS STRING),
        CAST(hours_bank_cost.dt_hours_bank_balanced AS STRING),
        hours_bank_cost.hours_bank_rule_key
    )) AS sk_hours_bank_rule_total,
    hours_bank_cost.sk_employee,
    balance_date.sk_date AS sk_balance_date,
    hours_bank_rule_dim.sk_hours_bank_rule,
    hours_bank_cost.sk_employee_cost_window,
    hourly_rate_started_date.sk_date AS sk_hourly_rate_segment_started_date,
    hourly_rate_ended_date.sk_date AS sk_hourly_rate_segment_ended_date,
    hours_bank_cost.hours_bank_rule_key,
    hours_bank_cost.person_number,
    CAST(hours_bank_cost.minutes_balance_rule_raw AS BIGINT) AS minutes_balance_rule,
    hours_bank_cost.hourly_rate_applied,
    hours_bank_cost.estimated_balance_cost_amount,
    hours_bank_cost.is_closed,
    hours_bank_cost.dt_hours_bank_balanced,
    hours_bank_cost.dt_hourly_rate_segment_started,
    hours_bank_cost.dt_hourly_rate_segment_ended,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    hours_bank_lines_with_hourly_rate AS hours_bank_cost
INNER JOIN
    dw_public.dim_date AS balance_date
        ON balance_date.date = hours_bank_cost.dt_hours_bank_balanced
LEFT JOIN
    dw_time.dim_hours_bank_rule AS hours_bank_rule_dim
        ON TRANSLATE(
            REGEXP_REPLACE(hours_bank_cost.hours_bank_rule_key, '^_+', ''),
            '_',
            '-'
        ) = hours_bank_rule_dim.hours_bank_rule_key
LEFT JOIN
    dw_public.dim_date AS hourly_rate_started_date
        ON hourly_rate_started_date.date = hours_bank_cost.dt_hourly_rate_segment_started
LEFT JOIN
    dw_public.dim_date AS hourly_rate_ended_date
        ON hourly_rate_ended_date.date = hours_bank_cost.dt_hourly_rate_segment_ended
