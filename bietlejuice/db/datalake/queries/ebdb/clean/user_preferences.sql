SELECT
    id,
    usuario_id AS id_user,
    receivesSms AS is_receiving_sms,
    receivesWhatsapp AS is_receiving_whatsapp,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM datalake_ebdb_raw.userpreferences
