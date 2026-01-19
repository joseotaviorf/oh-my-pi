SELECT
    sk_user_agent AS id_user_agent,
    hub,
    quartil_subhub,
    type AS agent_type,
    month_date AS dt_reference
FROM
    datalake_gsheets_raw.sv_portfolio_agents_gp