SELECT
    BIGINT(id_cbsitcontato_int) AS id_collection_history,
    BIGINT(id_geusuario_int) AS id_user,
    BIGINT(id_cbsituacaocontrato_int) AS id_customer_history,
    BIGINT(codigo_int) AS id_negotiation,
    BIGINT(id_gecliente_int) AS id_customer,
    BIGINT(id_geqlresponsavel_int) AS id_geqlresponsavel,
    BIGINT(id_geqlsituacao_int) AS id_geqlsituacao,
    BIGINT(id_geaplicacao_int) AS id_geaplicacao,
    BIGINT(id_getipodocumento_int) AS id_getipodocumento,
    BIGINT(id_gegrupotipodocumento_int) AS id_gegrupotipodocumento,
    BIGINT(id_cbvalortipodespesa_int) AS id_cbvalortipodespesa,
    BIGINT(id_sysatdinamico_int) AS id_sysatdinamico,
    BIGINT(id_jutipocontrole) AS id_jutipocontrole,
    IF(id_gemotivoinadimplencia_int = "24", "Não CPC", NULLIF(id_gemotivoinadimplencia_int, "")) AS delinquency_reason,
    CASE
        WHEN tipo_contato_str = "D" THEN "Direto"
        WHEN tipo_contato_str = "I" THEN "Indireto"
        WHEN tipo_contato_str = "G" THEN "Geral"
        ELSE tipo_contato_str
    END AS contact_type,
    CASE
        WHEN tp_acio_str = "A" THEN "Ativo"
        WHEN tp_acio_str = "R" THEN "Receptivo"
        WHEN tp_acio_str = "T" THEN "Todos"
        ELSE NULLIF(tp_acio_str,"")
    END AS trigger_type,
    codigo_banco_str AS bank_code,
    descricao_str AS contact_description,
    historico_padrao_str AS historical_user_contact_description,
    at_str AS description,
    CASE
        WHEN classificacao_str = "1" THEN "Excelente"
        WHEN classificacao_str = "2" THEN "Bom"
        WHEN classificacao_str = "3" THEN "Ruim"
        WHEN classificacao_str = "9" THEN "Indefinido"
        ELSE NULLIF(classificacao_str, "")
    END AS contact_classification,
    context,
    IF(positivo_str = "P", TRUE, FALSE) AS is_positive_call,
    IF(telefone_str = "S", TRUE, FALSE) AS has_telephone,
    IF(painel_classificacao_str = "S", TRUE, FALSE) AS has_reclassified_phone,
    IF(envia_email_str = "S", TRUE, FALSE) AS has_email_sending,
    IF(email_automatico_str = "S", TRUE, FALSE) AS has_sent_automatic_email,
    assunto_email_auto_txt AS email_subject,
    doc_str AS document_name,
    situacao_cobranca_str AS collection_status,
    IF(situacao_parcela_int = "6", "Baixado", NULLIF(situacao_parcela_int,"")) AS installment_status,
    IF(fup_filacobranca_str = "S", TRUE, FALSE) AS has_collection,
    IF(exclui_contrato_str = "N", "Não", NULLIF(exclui_contrato_str, "")) AS excludes_contract,
    IF(fup_banco_str = "S", TRUE, FALSE) AS has_bank_followup,
    IF(primordial_str = "S", TRUE, FALSE) AS is_primordial,
    IF(gera_retorno = 1, TRUE, FALSE) AS has_return,
    IF(ativo_str = "S", TRUE, FALSE) AS is_active,
    IF(atualiza_data_contato_manual_str = "S", TRUE, FALSE) AS is_automatic_fup,
    IF(class_at_str = "S", TRUE, FALSE) AS is_classifies_at_asm,
    BOOLEAN(atendida_bit) AS has_answer,
    BOOLEAN(produtiva_bit) AS is_productive,
    BOOLEAN(cpc_bit) AS is_cpc,
    IF(contato_alo_str = "S", TRUE, FALSE) AS is_alo_contact,
    BOOLEAN(terceiro_bit) AS is_third_party,
    BOOLEAN(data_evento_bit) AS is_event_date,
    IF(preenchimento_obrigatorio_str = "1", TRUE, FALSE) AS is_mandatory_filling,
    IF(boleto_str = "S", TRUE, FALSE) AS has_bank_slip,
    IF(ouvidoria_str = "S", TRUE, FALSE) AS has_ombudsman,
    IF(provisionamento_str = "S", TRUE, FALSE) AS has_provisioning,
    IF(liberacao_str = "S", TRUE, FALSE) AS has_release,
    IF(contatou_cliente_str = "S", TRUE, FALSE) AS has_contacted_customer,
    IF(doc_anexo_str = "S", TRUE, FALSE) AS has_attached_document,
    IF(documento_fisico_str = "S", TRUE, FALSE) AS has_physical_document,
    IF(monitor_ativo_str = "S", TRUE, FALSE) AS has_active_monitor,
    IF(protesto_str = "S", TRUE, FALSE) AS has_protest,
    IF(standby_automatico_str = "S", TRUE, FALSE) AS has_automatic_standby,
    IF(escolhe_usuario_agendamento_str = "S", TRUE, FALSE) AS has_choosen_user_appointment,
    IF(recebimento_str = "S", TRUE, FALSE) AS has_receipt,
    IF(visualizacao_externa_str = "S", TRUE, FALSE) AS has_external_view_legal,
    IF(abre_tela_depois_salvar_str = "1", TRUE, FALSE) AS has_open_screen_after_save,
    IF(apenas_aberto_str = "S", TRUE, FALSE) AS is_contract_open,
    IF(lancamento_unico_str = "S", TRUE, FALSE) AS is_unique_release,
    IF(lancamento_depende_str = "S", TRUE, FALSE) AS is_release_depends,
    IF(agendamento_str = "S", TRUE, FALSE) AS has_appointment,
    IF(agendamento_agenda_str = "S", TRUE, FALSE) AS is_shown_agenda,
    IF(agendamento_unico_str = "S", TRUE, FALSE) AS is_single_scheduling,
    CASE
        WHEN agendamento_por_str = "G" THEN "Grupo"
        WHEN agendamento_por_str = "U" THEN "Usuário"
        ELSE NULLIF(agendamento_por_str, "")
    END AS scheduled_by,
    descricao_npcob_web_str AS npcob_description,
    CASE
        WHEN tp_acao_str = "S" THEN "Stand-by"
        WHEN tp_acao_str = "F" THEN "Finalizado"
        WHEN tp_acao_str = "P" THEN "Pendente"
        ELSE tp_acao_str
    END AS lawsuit,
    IF(painel_npjur_str = "S", TRUE, FALSE) AS has_npjur_panel,
    IF(painel_jur_npjur_str = "S", TRUE, FALSE) AS has_panel_jur_npjur,
    IF(painel_custas_npjur_str = "S", TRUE, FALSE) AS has_cost_panel_npjur,
    IF(lanca_movimento_npjur_str = "S", TRUE, FALSE) AS has_launched_movement_npjur,
    CASE
        WHEN tipo_protocolo_npjur_bit = 0 THEN "Fechado"
        WHEN tipo_protocolo_npjur_bit = 1 THEN "Aberto"
        ELSE NULLIF(tipo_protocolo_npjur_bit, "")
    END AS type_protocol_npjur,
    IF(painel_purgacao_str = "S", TRUE, FALSE) AS is_mora_purge_panel,
    IF(solic_aju_str = "S", TRUE, FALSE) AS has_request_filing,
    CASE
        WHEN id_gemotivonajuizamento_int = "1" THEN "CONTRATO AJUIZADO"
        WHEN id_gemotivonajuizamento_int = "2" THEN "SEPARADO PARA TRIAGEM"
        WHEN id_gemotivonajuizamento_int = "3" THEN "AGUARDANDO SUBSIDIOS ELAW"
        WHEN id_gemotivonajuizamento_int = "4" THEN "RETORNO SUBSIDIOS ELAW"
        WHEN id_gemotivonajuizamento_int = "5" THEN "KIT ANEXADO NPJUR"
        ELSE NULLIF(id_gemotivonajuizamento_int, "")
    END AS reason_filing,
    IF(mov_processo_str = "S", TRUE, FALSE) AS has_process,
    CASE
        WHEN id_geprocesso_int = "15" THEN "BKO_5 ANDAR"
        WHEN id_geprocesso_int = "16" THEN "PAINEL PRÉJUR"
        WHEN id_geprocesso_int = "18" THEN "BKO Termo Acordo saida Imóvel * *JPL **"
        WHEN id_geprocesso_int = "19" THEN "ACORDO PASCH"
        WHEN id_geprocesso_int = "21" THEN "Quinto Resolve_Tratativa COGNITO"
        ELSE NULLIF(id_geprocesso_int, "")
    END AS process,
    CASE
        WHEN id_gegrupoprocesso_int = "1003" THEN "1.RET 1h"
        WHEN id_gegrupoprocesso_int = "1004" THEN "2.RET 48h"
        WHEN id_gegrupoprocesso_int = "1007" THEN "ROTINA"
        WHEN id_gegrupoprocesso_int = "1008" THEN "BKO Termo Acordo saida Imóvel * *JPL **"
        WHEN id_gegrupoprocesso_int = "1009" THEN "Extra Jud."
        WHEN id_gegrupoprocesso_int = "1011" THEN "Acordo EVIC"
        WHEN id_gegrupoprocesso_int = "1016" THEN "Quinto Resolve"
        WHEN id_gegrupoprocesso_int = "1018" THEN "Não Enviado"
        WHEN id_gegrupoprocesso_int = "1019" THEN "Comprovantes"
        ELSE NULLIF(id_gegrupoprocesso_int, "")
    END AS process_group,
    CASE
        WHEN id_geitemprocesso_int = "88" THEN "Ag.Retorno"
        WHEN id_geitemprocesso_int = "90" THEN "Reiteração"
        WHEN id_geitemprocesso_int = "92" THEN "Dowload"
        WHEN id_geitemprocesso_int = "93" THEN "T._PERDÃO DÍVIDA"
        WHEN id_geitemprocesso_int = "96" THEN "RET. JUD."
        WHEN id_geitemprocesso_int = "97" THEN "Alterar Acordo"
        WHEN id_geitemprocesso_int = "98" THEN "FINALIZADO"
        WHEN id_geitemprocesso_int = "99" THEN "ACORDO OP."
        WHEN id_geitemprocesso_int = "100" THEN "AG. JUD."
        WHEN id_geitemprocesso_int = "101" THEN "SAÍDA IMÓVEL"
        WHEN id_geitemprocesso_int = "102" THEN "Alterar Saída"
        WHEN id_geitemprocesso_int = "103" THEN "AG.LINK"
        WHEN id_geitemprocesso_int = "105" THEN "T. Novo"
        WHEN id_geitemprocesso_int = "107" THEN "LINK ENVIADO"
        WHEN id_geitemprocesso_int = "113" THEN "Análise"
        WHEN id_geitemprocesso_int = "114" THEN "Analise"
        WHEN id_geitemprocesso_int = "115" THEN "FINALIZADO"
        WHEN id_geitemprocesso_int = "116" THEN "Ag. Contato"
        ELSE NULLIF(id_geitemprocesso_int, "")
    END AS item_process,
    IF(data_envio_date = "S", TRUE, FALSE) AS is_shipping_date,
    IF(atualiza_data_ultimo_contato_str = "S", TRUE, FALSE) AS has_updated_last_contact_date,
    proxima_chamada_tim AS pending_time,
    IFNULL(INT(limite_stdby_int), 0) AS limit_standby,
    INT(qtde_ocorrencia_follow_int) AS total_occurrence_follow,
    INT(horas_blacklist_int) AS hours_blacklist,
    INT(dias_cobranca_int) AS collection_days,
    INT(tempo_ideal_int) AS ideal_time,
    INT(margem_tolerancia_int) AS tolerance_margin,
    INT(agendamento_dias_int) AS scheduling_days,
    TO_TIMESTAMP(tstamp, 'dd/MM/yyyy HH:mm:ss') AS ts_timestamp,
    NOW() AS ts_load
FROM datalake_paschoalotto_raw.cbsitcontato
QUALIFY ROW_NUMBER() OVER(PARTITION BY id_cbsitcontato_int ORDER BY DATE(CONCAT(year, "-", month, "-", day)) DESC, ts_load DESC) = 1
