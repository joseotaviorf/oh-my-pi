-- The source spreadsheet is generated with data from the datalake, 
-- therefore, it should not be used as a dependency for other tables
SELECT
    sk_user_agent AS id_user_agent,
    sk_agent AS id_agent,
    mes_descritivo AS month_description,
    praca AS square,
    hub,
    quartil AS quartile,
    CAST(REPLACE(score_gp, ',', '.') AS FLOAT) AS score_gp,
    mes AS month,
    ano AS year
FROM
    datalake_gsheets_raw.broker_score_by_quartiles

