SELECT
    CAST(id_owner AS BIGINT) AS id_owner,
    cluster,
    ts_load
FROM
    datalake_gsheets_raw.pp_multi_cluster