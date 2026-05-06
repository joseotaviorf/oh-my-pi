WITH deduped_employee_cost_rows AS (
    SELECT
        id_cost_segment,
        id_employee_profile,
        hourly_rate_amount,
        dt_period_started AS dt_hourly_cost_segment_started,
        dt_period_ended AS dt_hourly_cost_segment_ended,
        cost_segment_status,
        ts_load,
        year,
        month,
        day
    FROM
        datalake_oitchau_clean.employee_costs
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}')
            AND DATE('{load_end_date}')
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                id_cost_segment
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
employee_hourly_costs_with_person AS (
    SELECT
        XXHASH64(
            TRIM(CAST(cd.id_cost_segment AS STRING))
        ) AS sk_employee_cost_window,
        cd.id_cost_segment,
        cd.id_employee_profile,
        cd.hourly_rate_amount,
        cd.dt_hourly_cost_segment_started,
        cd.dt_hourly_cost_segment_ended,
        cd.cost_segment_status,
        de.sk_employee,
        TRIM(CAST(de.person_number AS STRING)) AS person_number
    FROM
        deduped_employee_cost_rows AS cd
    INNER JOIN
        employee_registration AS er
            ON er.id_employee_profile = cd.id_employee_profile
    INNER JOIN
        dw_people.dim_employee AS de
            ON TRIM(CAST(er.registration_code AS STRING)) = TRIM(CAST(de.person_number AS STRING))
)
SELECT
    cm.sk_employee_cost_window,
    cm.sk_employee,
    cm.id_employee_profile,
    cm.id_cost_segment,
    cm.person_number,
    cm.cost_segment_status,
    cm.hourly_rate_amount,
    cm.dt_hourly_cost_segment_started,
    cm.dt_hourly_cost_segment_ended,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    employee_hourly_costs_with_person AS cm
