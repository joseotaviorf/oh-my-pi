SELECT
    BIGINT(id_cbfollowup_int) AS id_followup,
    BIGINT(id_cbcontrato_int) AS id_contract,
    BIGINT(id_cbparcela_int) AS id_debt,
    BIGINT(id_cbsitcontato_int) AS id_collection_history,
    BIGINT(id_geqlcontato_int) AS id_contact,
    BIGINT(id_geusuario_int) AS id_user,
    BIGINT(id_gemotivoinadimplencia_int) AS id_deliquency_reason,
    historico_str AS followup_description,
    CASE
        WHEN tipo_contato_str = "A" THEN "Ativo"
        WHEN tipo_contato_str = "R" THEN "Receptivo"
        WHEN tipo_contato_str = "N" THEN "Nenhum"
        WHEN tipo_contato_str = "L" THEN "Legal"
        ELSE NULLIF(tipo_contato_str,"")
    END AS contact_type,
    IF(acao_enviado_api_int = "1", TRUE, FALSE) AS is_sent_to_api,
    status_registro_str AS status_record,
    call_key_str AS call_key,
    instancia_str AS instance,
    tempo_ligacao_tim AS call_duration,
    context,
    IF(coloca_stand_str = "S", TRUE, FALSE) AS is_stand,
    IF(alterado_str = "S", TRUE, FALSE) AS is_updated,
    TO_DATE(data_evento_dat, 'dd/MM/yyyy HH:mm:ss') AS dt_event,
    TO_DATE(data_dat, 'dd/MM/yyyy HH:mm:ss') AS dt_followup,
    TO_DATE(data_stand_by_dat, 'dd/MM/yyyy HH:mm:ss') AS dt_stand_by,
    TO_DATE(data_cobranca_dat, 'dd/MM/yyyy HH:mm:ss') AS dt_collection,
    TO_TIMESTAMP(cobranca_inicio_tim, 'dd/MM/yyyy HH:mm:ss') AS ts_collection_start,
    TO_TIMESTAMP(cobranca_final_tim, 'dd/MM/yyyy HH:mm:ss') AS ts_collection_end,
    TO_TIMESTAMP(hora_cobranca_tim, 'dd/MM/yyyy HH:mm:ss') AS ts_collection_hour,
    TO_TIMESTAMP(hora_tim, 'dd/MM/yyyy HH:mm:ss') AS ts_hour,
    TO_TIMESTAMP(tstamp, 'dd/MM/yyyy HH:mm:ss') AS ts_timestamp,
    TO_TIMESTAMP(tstamp_mdm_inclusao, 'dd/MM/yyyy HH:mm:ss') AS ts_insert,
    TO_TIMESTAMP(tstamp_mdm_alteracao, 'dd/MM/yyyy HH:mm:ss') AS ts_update,
    NOW() AS ts_load,
    year,
    month,
    day
FROM datalake_paschoalotto_raw.cbfollowup
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
