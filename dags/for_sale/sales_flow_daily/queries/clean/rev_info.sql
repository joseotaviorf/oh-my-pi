SELECT
    id,
    user_id AS id_user,
    keycloak_id AS id_keycloak, 
    trace_id AS id_trace,
    CAST(FROM_UNIXTIME(CAST(timestamp AS BIGINT)/1000) AS TIMESTAMP) AS ts_created,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.revinfo