WITH hours_bank_snapshots AS (
    SELECT
        id_employee_profile,
        dt_balanced AS dt_hours_bank_balanced,
        FROM_JSON(
            TO_JSON(hours_bank_totals),
            'MAP<STRING, BIGINT>'
        ) AS hours_bank_totals_map,
        ts_load
    FROM
        datalake_oitchau_clean.hoursbank_totals
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}')
            AND DATE('{load_end_date}')
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                id_employee_profile,
                dt_balanced
            ORDER BY
                ts_load DESC NULLS LAST,
                year DESC,
                month DESC,
                day DESC
        ) = 1
),
employee_registration AS (
    SELECT
        id_employee_profile,
        registration_code
    FROM
        datalake_oitchau_clean.employees
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}')
            AND DATE('{load_end_date}')
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                id_employee_profile
            ORDER BY
                ts_load DESC NULLS LAST,
                year DESC,
                month DESC,
                day DESC
        ) = 1
),
hours_bank_with_employee AS (
    SELECT
        hb.dt_hours_bank_balanced,
        hb.hours_bank_totals_map,
        de.sk_employee,
        TRIM(CAST(de.person_number AS STRING)) AS person_number
    FROM
        hours_bank_snapshots AS hb
    INNER JOIN
        employee_registration AS er
            ON er.id_employee_profile = hb.id_employee_profile
    INNER JOIN
        dw_people.dim_employee AS de
            ON TRIM(CAST(er.registration_code AS STRING)) = TRIM(CAST(de.person_number AS STRING))
    WHERE
        hb.hours_bank_totals_map IS NOT NULL
        AND SIZE(hb.hours_bank_totals_map) > 0
),
hours_bank_rule_lines AS (
    SELECT
        hm.sk_employee,
        hm.person_number,
        hm.dt_hours_bank_balanced,
        EXPLODE(hm.hours_bank_totals_map) AS (
            hours_bank_rule_key,
            minutes_balance_rule_raw
        )
    FROM
        hours_bank_with_employee AS hm
),
hours_bank_lines_with_hourly_rate AS (
    SELECT
        br.sk_employee,
        br.person_number,
        br.dt_hours_bank_balanced,
        br.hours_bank_rule_key,
        br.minutes_balance_rule_raw,
        cw.sk_employee_cost_window,
        cw.hourly_rate_amount AS hourly_rate_applied,
        cw.dt_hourly_cost_segment_started AS dt_hourly_rate_segment_started,
        cw.dt_hourly_cost_segment_ended AS dt_hourly_rate_segment_ended,
        CAST(
            CASE
                WHEN cw.hourly_rate_amount IS NULL
                    THEN NULL
                ELSE (CAST(br.minutes_balance_rule_raw AS BIGINT) / 60.0)
                    * cw.hourly_rate_amount
            END AS DECIMAL(18, 4)
        ) AS estimated_balance_cost_amount
    FROM
        hours_bank_rule_lines AS br
    LEFT JOIN
        dw_time.fact_employee_hourly_cost_windows AS cw
            ON br.sk_employee = cw.sk_employee
            AND UPPER(cw.cost_segment_status) = 'ACTIVE'
            AND br.dt_hours_bank_balanced >= cw.dt_hourly_cost_segment_started
            AND (
                cw.dt_hourly_cost_segment_ended IS NULL
                OR br.dt_hours_bank_balanced <= cw.dt_hourly_cost_segment_ended
            )
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                br.sk_employee,
                br.dt_hours_bank_balanced,
                br.hours_bank_rule_key
            ORDER BY
                cw.dt_hourly_cost_segment_started DESC NULLS LAST,
                cw.dt_hourly_cost_segment_ended ASC NULLS LAST
        ) = 1
)
SELECT
    XXHASH64(
        CAST(bw.sk_employee AS STRING),
        CAST(bw.dt_hours_bank_balanced AS STRING),
        bw.hours_bank_rule_key
    ) AS sk_hours_bank_rule_total,
    bw.sk_employee,
    dd.sk_date AS sk_balance_date,
    hr.sk_hours_bank_rule,
    bw.sk_employee_cost_window,
    bw.hours_bank_rule_key,
    bw.person_number,
    CAST(bw.minutes_balance_rule_raw AS BIGINT) AS minutes_balance_rule,
    bw.hourly_rate_applied,
    bw.estimated_balance_cost_amount,
    bw.dt_hours_bank_balanced,
    bw.dt_hourly_rate_segment_started,
    bw.dt_hourly_rate_segment_ended,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    hours_bank_lines_with_hourly_rate AS bw
INNER JOIN
    dw_public.dim_date AS dd
        ON dd.date = bw.dt_hours_bank_balanced
LEFT JOIN
    dw_time.dim_hours_bank_rule AS hr
        ON TRANSLATE(
            REGEXP_REPLACE(bw.hours_bank_rule_key, '^_+', ''),
            '_',
            '-'
        ) = hr.hours_bank_rule_key
