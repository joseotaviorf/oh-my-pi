SELECT
    id_user,
    id_agent,
    city_group,
    region_code,
    agent_type,
    quartil AS quartile,
    DATE(month) AS dt_month_reference
FROM
    datalake_gsheets_raw.agents_historical_quartile