SELECT
    CAST(id_partner AS BIGINT) AS id_partner,
    carteira_vinculada AS portfolio_user_name,
    cluster AS cluster_name,
    ts_load AS ts_created,
    YEAR(ts_load) AS year,
    MONTH(ts_load) AS month,
    DAY(ts_load) AS day
FROM
    datalake_gsheets_raw.ciq_portfolio