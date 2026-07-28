WITH deduped AS (
    SELECT
        uuid AS id_cost_segment,
        userProfileUuid AS id_employee_profile,
        companyUuid AS id_company,
        employeeExternalId AS id_employee_external,
        status AS cost_segment_status,
        CAST(rate AS DECIMAL(18, 4)) AS hourly_rate_amount,
        CAST(startDate AS DATE) AS dt_period_started,
        CAST(endDate AS DATE) AS dt_period_ended,
        ts_load,
        year,
        month,
        day,
        ROW_NUMBER() OVER (
            PARTITION BY uuid
            ORDER BY
                ts_load DESC NULLS LAST,
                year DESC,
                month DESC,
                day DESC
        ) AS row_number_latest
    FROM
        datalake_oitchau_raw.employee_costs
)
SELECT
    id_cost_segment,
    id_employee_profile,
    id_company,
    id_employee_external,
    cost_segment_status,
    hourly_rate_amount,
    dt_period_started,
    dt_period_ended,
    ts_load,
    year,
    month,
    day
FROM
    deduped
WHERE
    row_number_latest = 1
