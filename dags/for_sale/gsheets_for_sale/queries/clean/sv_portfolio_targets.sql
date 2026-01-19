SELECT
    city_group,
    portfolio_group,
    portfolio,
    indicator,
    value AS target_value,
    date AS dt_reference
FROM
    datalake_gsheets_raw.sv_portfolio_targets