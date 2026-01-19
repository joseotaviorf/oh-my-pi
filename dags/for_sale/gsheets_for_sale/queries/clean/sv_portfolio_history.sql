SELECT
    sk_user_agent AS id_user_agent,
    portfolio,
    dt_reference
FROM
    datalake_gsheets_raw.sv_portfolio_history