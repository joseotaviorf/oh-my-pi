SELECT
    user_identity.email AS user_email,
    SPLIT_PART(request_params.table_full_name, '.', 1) AS catalog_name,
    SPLIT_PART(request_params.table_full_name, '.', 2) AS schema_name,
    SPLIT_PART(request_params.table_full_name, '.', 3) AS table_name,
    request_params.table_full_name,
    COUNT_IF(request_params.operation = 'READ') AS read_operations,
    COUNT_IF(request_params.operation = 'READ_WRITE') AS write_operations,
    event_date AS dt_event,
    YEAR(dt_event) AS year,
    MONTH(dt_event) AS month,
    DAY(dt_event) AS day
FROM
    system.access.audit
WHERE
    action_name = 'generateTemporaryTableCredential'
    AND response.status_code = 200
    AND event_date BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND request_params.table_full_name LIKE '{catalog_name}.%'
    AND request_params.table_full_name NOT LIKE '%hightouch%' -- Hightouch creates too many tables
GROUP BY
    user_identity.email,
    request_params.table_full_name,
    event_date