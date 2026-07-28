WITH deduped AS (
    SELECT
        CAST(GET_JSON_OBJECT(payload, '$.employeeUuid') AS STRING) AS id_employee_profile,
        GET_JSON_OBJECT(payload, '$.metadata.status') AS report_status,
        GET_JSON_OBJECT(payload, '$.metadata.hash') AS report_hash,
        CAST(GET_JSON_OBJECT(payload, '$.metadata.startDate') AS DATE) AS dt_report_period_started,
        CAST(GET_JSON_OBJECT(payload, '$.metadata.endDate') AS DATE) AS dt_report_period_ended,
        ts_load,
        GET_JSON_OBJECT(payload, '$.content') AS detailed_report_content,
        GET_JSON_OBJECT(payload, '$.metadata') AS detailed_report_metadata,
        year,
        month,
        day,
        ROW_NUMBER() OVER (
            PARTITION BY
                CAST(GET_JSON_OBJECT(payload, '$.employeeUuid') AS STRING),
                CAST(GET_JSON_OBJECT(payload, '$.metadata.startDate') AS DATE),
                CAST(GET_JSON_OBJECT(payload, '$.metadata.endDate') AS DATE)
            ORDER BY
                ts_load DESC NULLS LAST,
                year DESC,
                month DESC,
                day DESC
        ) AS row_number_latest
    FROM
        datalake_oitchau_raw.reports_detailed
    WHERE
        MAKE_DATE(year, month, day) = DATE_ADD(DATE('{load_start_date}'), 1)
)
SELECT
    id_employee_profile,
    report_status,
    report_hash,
    dt_report_period_started,
    dt_report_period_ended,
    ts_load,
    detailed_report_content,
    detailed_report_metadata,
    year,
    month,
    day
FROM
    deduped
WHERE
    row_number_latest = 1
