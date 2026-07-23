SELECT
    CAST(GET_JSON_OBJECT(outputs, '$.request_id') AS STRING) AS id_request,
    id_service,
    CAST(COALESCE(
        GET_JSON_OBJECT(inputs, '$.request.id_house'),
        GET_JSON_OBJECT(inputs, '$.id_house') -- For Sale ECM logs are in a deprecated JSON structure
    ) AS BIGINT) AS id_house,
    CAST(COALESCE(
        GET_JSON_OBJECT(inputs, '$.request.id_user'),
        GET_JSON_OBJECT(inputs, '$.id_user') -- For Sale ECM logs are in a deprecated JSON structure
    ) AS BIGINT) AS id_user,
    CAST(GET_JSON_OBJECT(inputs, '$.ecm_version') AS STRING) AS ecm_version,
    service_version,
    CAST(GET_JSON_OBJECT(outputs, '$.estimated_gross_revenue') AS DOUBLE) AS estimated_gross_revenue,
    CAST(GET_JSON_OBJECT(outputs, '$.estimated_net_revenue') AS DOUBLE) AS estimated_net_revenue,
    CAST(GET_JSON_OBJECT(outputs, '$.estimated_contribution_margin') AS DOUBLE) AS estimated_contribution_margin,
    CAST(GET_JSON_OBJECT(outputs, '$.estimated_conversion_probability') AS DOUBLE) AS estimated_conversion_probability,
    CAST(GET_JSON_OBJECT(outputs, '$.estimated_discount') AS DOUBLE) AS estimated_discount,
    CAST(GET_JSON_OBJECT(outputs, '$.estimated_duration') AS DOUBLE) AS estimated_duration,
    CAST(GET_JSON_OBJECT(outputs, '$.estimated_default_probability') AS DOUBLE) AS estimated_default_probability,
    CAST(COALESCE(
        GET_JSON_OBJECT(inputs, '$.request.ts_event'),
        ts_log -- For Sale ECM logs are in a deprecated JSON structure
    ) AS TIMESTAMP) AS ts_event,
    GET_JSON_OBJECT(inputs, '$.features') AS features,
    GET_JSON_OBJECT(inputs, '$.request') AS request,
    year,
    month,
    day
FROM
    datalake_emlio_clean.emlio_logs
WHERE
    id_service IN ('eltv', 'for-sale-ecm')
    AND year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
    AND day = DAY(DATE('{load_start_date}'))
