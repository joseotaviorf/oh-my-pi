SELECT
    CAST(id_partner AS BIGINT) AS id_partner,
    carteira_vinculada,
    cluster,
    ts_load
FROM
    datalake_gsheets_raw.carteira_ciq