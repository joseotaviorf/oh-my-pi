SELECT
    CAST(sk_user_agent AS BIGINT) AS id_agent,
    portfolio,
    DATE(dt_reference) AS dt_reference,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.secretariat_sale_portfolio
