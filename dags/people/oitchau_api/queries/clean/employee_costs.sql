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
    day
FROM
    datalake_oitchau_raw.employee_costs
QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY uuid
        ORDER BY
            ts_load DESC NULLS LAST,
            year DESC,
            month DESC,
            day DESC
    ) = 1
