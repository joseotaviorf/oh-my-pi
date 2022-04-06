SELECT
    CAST(sk_pp AS BIGINT) AS id_owner,
    prospects,
    cluster,
    DATE(data_envio_msg) AS dt_message_sent
FROM
    datalake_gsheets_raw.base_hunter
