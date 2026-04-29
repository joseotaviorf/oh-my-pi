SELECT
    CAST(get_json_object(payload, '$.employeeUuid') AS STRING) AS id_employee_profile,
    get_json_object(payload, '$.metadata.status') AS report_status,
    get_json_object(payload, '$.metadata.hash') AS report_hash,
    CAST(get_json_object(payload, '$.metadata.startDate') AS DATE) AS dt_report_period_started,
    CAST(get_json_object(payload, '$.metadata.endDate') AS DATE) AS dt_report_period_ended,
    ts_load,
    get_json_object(payload, '$.content') AS detailed_report_content,
    get_json_object(payload, '$.metadata') AS detailed_report_metadata,
    year,
    month,
    day
FROM
    datalake_oitchau_raw.reports_detailed
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}')
        AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY
            CAST(get_json_object(payload, '$.employeeUuid') AS STRING),
            CAST(get_json_object(payload, '$.metadata.startDate') AS DATE),
            CAST(get_json_object(payload, '$.metadata.endDate') AS DATE)
        ORDER BY
            ts_load DESC NULLS LAST,
            year DESC,
            month DESC,
            day DESC
    ) = 1
