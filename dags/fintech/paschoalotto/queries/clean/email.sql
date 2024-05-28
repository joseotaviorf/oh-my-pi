SELECT
    BIGINT(id_geqlemail_int) AS id_email,
    BIGINT(id_geqlcliente_int) AS id_customer,
    email_str AS email,
    classificacao_str AS classification,
    context,
    BOOLEAN(excluido_bit) AS is_deleted,
    TO_TIMESTAMP(tstamp_mdm_inclusao, 'dd/MM/yyyy HH:mm:ss') AS ts_insert,
    TO_TIMESTAMP(tstamp_mdm_alteracao, 'dd/MM/yyyy HH:mm:ss') AS ts_update,
    TO_TIMESTAMP(tstamp, 'dd/MM/yyyy HH:mm:ss') AS ts_timestamp,
    NOW() AS ts_load
FROM datalake_paschoalotto_raw.geqlemail
QUALIFY ROW_NUMBER() OVER(PARTITION BY id_geqlemail_int ORDER BY DATE(CONCAT(year, "-", month, "-", day)) DESC, ts_load DESC) = 1
