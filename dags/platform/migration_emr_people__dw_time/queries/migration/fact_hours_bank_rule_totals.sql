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
        closed_balance_snapshots AS existing_closed
            ON existing_closed.id_employee_profile = open_balance.id_employee_profile
            AND existing_closed.dt_hours_bank_balanced = open_balance.dt_hours_bank_balanced
    WHERE
        open_balance.row_number_latest = 1
        AND existing_closed.id_employee_profile IS NULL
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
        hours_bank_rule_dim.segment_label,
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
        ) AS amount_balance_base,
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
        dw_time.dim_hours_bank_rule AS hours_bank_rule_dim
            ON TRANSLATE(
                REGEXP_REPLACE(hours_bank_rule.hours_bank_rule_key, '^_+', ''),
                '_',
                '-'
            ) = hours_bank_rule_dim.hours_bank_rule_key
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
        hourly_rate_ranked.sk_employee,
        hourly_rate_ranked.person_number,
        hourly_rate_ranked.dt_hours_bank_balanced,
        CAST(
            DATE_TRUNC('month', hourly_rate_ranked.dt_hours_bank_balanced) AS DATE
        ) AS dt_reference_month,
        hourly_rate_ranked.is_closed,
        hourly_rate_ranked.hours_bank_rule_key,
        hourly_rate_ranked.minutes_balance_rule_raw,
        hourly_rate_ranked.segment_label,
        TRY_CAST(
            TRIM(CAST(hourly_rate_ranked.segment_label AS STRING)) AS INT
        ) AS segment_label_numeric,
        hourly_rate_ranked.sk_employee_cost_window,
        hourly_rate_ranked.hourly_rate_applied,
        hourly_rate_ranked.dt_hourly_rate_segment_started,
        hourly_rate_ranked.dt_hourly_rate_segment_ended,
        hourly_rate_ranked.amount_balance_base
    FROM
        hours_bank_lines_with_hourly_rate_ranked AS hourly_rate_ranked
    WHERE
        hourly_rate_ranked.row_number_latest = 1
),
month_payment_calendar AS (
    SELECT
        CAST(DATE_TRUNC('month', calendar_date.date) AS DATE) AS dt_payment_month,
        CAST(SUM(
            CASE
                WHEN calendar_date.week_day = 0
                    THEN 1
                ELSE 0
            END
        ) AS INT) AS sundays_in_month,
        CAST(SUM(
            CASE
                WHEN calendar_date.is_brz_holiday = 'Holiday'
                    AND calendar_date.week_day BETWEEN 1 AND 5
                    AND LOWER(COALESCE(calendar_date.br_holiday_name, '')) NOT LIKE '%carnival%'
                    THEN 1
                ELSE 0
            END
        ) AS INT) AS weekday_holidays_excl_carnival,
        CAST(SUM(
            CASE
                WHEN calendar_date.week_day BETWEEN 1 AND 6
                    AND calendar_date.is_brz_holiday <> 'Holiday'
                    THEN 1
                ELSE 0
            END
        ) AS INT) AS mon_sat_workdays
    FROM
        dw_public.dim_date AS calendar_date
    GROUP BY
        CAST(DATE_TRUNC('month', calendar_date.date) AS DATE)
),
hours_bank_lines_with_realized_cost AS (
    SELECT
        hourly_rate_lines.sk_employee,
        hourly_rate_lines.person_number,
        hourly_rate_lines.dt_hours_bank_balanced,
        hourly_rate_lines.dt_reference_month,
        hourly_rate_lines.is_closed,
        hourly_rate_lines.hours_bank_rule_key,
        hourly_rate_lines.minutes_balance_rule_raw,
        hourly_rate_lines.segment_label,
        hourly_rate_lines.sk_employee_cost_window,
        hourly_rate_lines.hourly_rate_applied,
        hourly_rate_lines.dt_hourly_rate_segment_started,
        hourly_rate_lines.dt_hourly_rate_segment_ended,
        hourly_rate_lines.amount_balance_base,
        CAST(
            CASE
                WHEN hourly_rate_lines.segment_label_numeric IN (50, 60)
                    THEN hourly_rate_lines.segment_label_numeric
                ELSE NULL
            END AS DECIMAL(5, 2)
        ) AS premium_pct,
        CASE
            WHEN hourly_rate_lines.is_closed
                AND hourly_rate_lines.segment_label_numeric IN (50, 60)
                THEN TRUE
            ELSE FALSE
        END AS is_in_overtime_realized,
        CAST(
            CASE
                WHEN hourly_rate_lines.amount_balance_base IS NULL
                    THEN NULL
                WHEN hourly_rate_lines.is_closed
                    AND hourly_rate_lines.segment_label_numeric IN (50, 60)
                    THEN hourly_rate_lines.amount_balance_base
                        * (
                            1.0 + (
                                CAST(hourly_rate_lines.segment_label_numeric AS DOUBLE) / 100.0
                            )
                        )
                ELSE hourly_rate_lines.amount_balance_base
            END AS DECIMAL(18, 4)
        ) AS estimated_balance_cost_amount,
        CAST(
            CASE
                WHEN hourly_rate_lines.amount_balance_base IS NULL
                    OR NOT hourly_rate_lines.is_closed
                    OR hourly_rate_lines.segment_label_numeric NOT IN (50, 60)
                    OR payment_calendar.mon_sat_workdays IS NULL
                    OR payment_calendar.mon_sat_workdays = 0
                    THEN NULL
                ELSE (
                    hourly_rate_lines.amount_balance_base
                    * (
                        1.0 + (
                            CAST(hourly_rate_lines.segment_label_numeric AS DOUBLE) / 100.0
                        )
                    )
                    * (
                        CAST(
                            payment_calendar.sundays_in_month
                            + payment_calendar.weekday_holidays_excl_carnival
                        AS DOUBLE)
                        / CAST(payment_calendar.mon_sat_workdays AS DOUBLE)
                    )
                )
            END AS DECIMAL(18, 4)
        ) AS amount_dsr_on_overtime,
        CAST(
            CASE
                WHEN hourly_rate_lines.amount_balance_base IS NULL
                    THEN NULL
                WHEN hourly_rate_lines.is_closed
                    AND hourly_rate_lines.segment_label_numeric IN (50, 60)
                    AND payment_calendar.mon_sat_workdays IS NOT NULL
                    AND payment_calendar.mon_sat_workdays <> 0
                    THEN (
                        hourly_rate_lines.amount_balance_base
                        * (
                            1.0 + (
                                CAST(hourly_rate_lines.segment_label_numeric AS DOUBLE) / 100.0
                            )
                        )
                    )
                    * (
                        1.0 + (
                            CAST(
                                payment_calendar.sundays_in_month
                                + payment_calendar.weekday_holidays_excl_carnival
                            AS DOUBLE)
                            / CAST(payment_calendar.mon_sat_workdays AS DOUBLE)
                        )
                    )
                WHEN hourly_rate_lines.is_closed
                    AND hourly_rate_lines.segment_label_numeric IN (50, 60)
                    THEN NULL
                ELSE hourly_rate_lines.amount_balance_base
            END AS DECIMAL(18, 4)
        ) AS amount_overtime_realized_total
    FROM
        hours_bank_lines_with_hourly_rate AS hourly_rate_lines
    LEFT JOIN
        month_payment_calendar AS payment_calendar
            ON payment_calendar.dt_payment_month = CAST(
                ADD_MONTHS(hourly_rate_lines.dt_reference_month, 1) AS DATE
            )
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
    hours_bank_cost.premium_pct,
    hours_bank_cost.amount_balance_base,
    hours_bank_cost.estimated_balance_cost_amount,
    hours_bank_cost.amount_dsr_on_overtime,
    hours_bank_cost.amount_overtime_realized_total,
    hours_bank_cost.is_in_overtime_realized,
    hours_bank_cost.is_closed,
    hours_bank_cost.dt_reference_month,
    hours_bank_cost.dt_hours_bank_balanced,
    hours_bank_cost.dt_hourly_rate_segment_started,
    hours_bank_cost.dt_hourly_rate_segment_ended,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    hours_bank_lines_with_realized_cost AS hours_bank_cost
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
