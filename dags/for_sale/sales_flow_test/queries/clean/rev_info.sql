SELECT
    id,
    user_id AS id_user,
    keycloak_id AS id_keycloak, 
    CAST(FROM_UNIXTIME(CAST(timestamp AS BIGINT)/1000) AS TIMESTAMP) AS ts_created,
    year,
    month,
    day
FROM
    datalake_sales_flow_test_raw.revinfo