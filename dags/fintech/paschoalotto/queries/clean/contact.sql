SELECT
    BIGINT(id_geqlcontato_int) AS id_contact,
    BIGINT(id_geqlcliente_int) AS id_customer,
    BIGINT(id_geqlendereco_int) AS id_address,
    BIGINT(id_geqlcontrato_int) AS id_customer_map_keys,
    BIGINT(id_geusuario_int) AS id_user,
    BIGINT(id_geqltipocontato_int) AS id_geqltipocontato,
    BIGINT(id_cemiterio_int) AS id_cemiterio,
    INT(id_geusuario_inclusao_int) AS id_geusuario_inclusao,
    contato_str AS contact,
    CASE
        WHEN classificacao_str = "1" THEN "Excelente"
        WHEN classificacao_str = "2" THEN "Bom"
        WHEN classificacao_str = "3" THEN "Ruim"
        WHEN classificacao_str = "9" THEN "Indefinido"
        ELSE NULLIF(classificacao_str,"")
    END AS phone_classification,
    tabela_origem_str AS origin_table,
    observacao_str AS note,
    nome_contato_str AS contact_name,
    cpf_str AS cpf,
    rg_str AS rg,
    BOOLEAN(excluido_bit) is_deleted,
    contato_antigo_str AS old_contact,
    BIGINT(COALESCE(score, score_int)) AS score,
    INT(score_lemit_int) AS score_lemit,
    tipo_pessoa_str AS person_type,
    ramal_str AS telephone_extension,
    IF(whatsapp_str = "S", TRUE, FALSE) AS has_whatsapp,
    trava_feriado_str AS holiday_lock,
    motivo_str AS reason,
    context,
    BOOLEAN(contatopagoufacil_bit) is_pagoufacil,
    INT(ranking_lemit_int) AS ranking_lemit,
    obs_inibicao_tel_suspeito_str AS inhibition_suspicious_phone_note,
    TO_DATE(data_score_dat, 'dd/MM/yyyy HH:mm:ss') AS dt_score,
    TO_DATE(data_alteracao_score_dat, 'dd/MM/yyyy HH:mm:ss') AS dt_score_update,
    TO_DATE(data_alteracao_ranking_dat, 'dd/MM/yyyy HH:mm:ss') AS dt_ranking_update,
    TO_TIMESTAMP(tstamp_envio, 'dd/MM/yyyy HH:mm:ss') AS ts_sent,
    TO_TIMESTAMP(tstamp_retorno, 'dd/MM/yyyy HH:mm:ss') AS ts_return,
    TO_TIMESTAMP(data_cemiterio_tst, 'dd/MM/yyyy HH:mm:ss') AS ts_cemetery,
    TO_TIMESTAMP(data_inibicao_tel_suspeito_tstamp, 'dd/MM/yyyy HH:mm:ss') AS ts_inhibition_suspicious_phone,
    TO_TIMESTAMP(tstamp_inclusao, 'dd/MM/yyyy HH:mm:ss') AS ts_phone_insert,
    TO_TIMESTAMP(tstamp_mdm_inclusao, 'dd/MM/yyyy HH:mm:ss') AS ts_insert,
    TO_TIMESTAMP(tstamp_mdm_alteracao, 'dd/MM/yyyy HH:mm:ss') AS ts_update,
    TO_TIMESTAMP(tstamp, 'dd/MM/yyyy HH:mm:ss') AS ts_timestamp,
    NOW() AS ts_load
FROM datalake_paschoalotto_raw.geqlcontato
QUALIFY ROW_NUMBER() OVER(PARTITION BY id_geqlcontato_int ORDER BY DATE(CONCAT(year, "-", month, "-", day)) DESC, ts_load DESC) = 1
