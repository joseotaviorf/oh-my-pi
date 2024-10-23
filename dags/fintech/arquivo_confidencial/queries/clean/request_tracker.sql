SELECT
    id,
    integration_report_id AS id_integration_report,
    business_unit,
    version,
    is_cached,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_arquivo_confidencial_raw.request_tracker
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
