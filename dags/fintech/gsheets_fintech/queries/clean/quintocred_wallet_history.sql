SELECT
    NULLIF(executive, '') AS executive,
    CAST(NULLIF(id_broker, '') AS INT) AS id_broker,
    NULLIF(dt_updated, '') AS dt_updated,
    NULLIF(month, '') AS month,
    NULLIF(year, '') AS year
FROM
    datalake_gsheets_raw.quintocred_wallet_history
