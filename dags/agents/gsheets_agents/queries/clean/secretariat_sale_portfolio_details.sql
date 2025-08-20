SELECT
    email_secretary,
    email_supervisor,
    portfolio_group,
    portfolio,
    DATE(dt_reference) AS dt_reference,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.secretariat_sale_portfolio_details
