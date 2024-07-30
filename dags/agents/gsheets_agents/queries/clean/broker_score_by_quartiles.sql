-- The source spreadsheet is generated with data from the datalake, 
-- therefore, it should not be used as a dependency for other tables
SELECT
    CAST(REPLACE(sk_user_agent, '.', '') AS BIGINT) AS id_user_agent,
    CAST(sk_agent  AS BIGINT) AS id_agent,
    mes_descritivo AS month_description,
    praca AS square,
    hub,
    quartil AS quartile,
    CAST(REPLACE(score_gp, ',', '.') AS FLOAT) AS score_gp,
    CAST(mes AS INT) AS month,
    CAST(ano AS INT) AS year
FROM
    datalake_gsheets_raw.broker_score_by_quartiles

