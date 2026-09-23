-- Widened to the full CHARGE payload so RAW cobrancas_full in the extraction spreadsheet
-- maps one to one onto this projection, monetary columns included.
-- dt_liquidacao_recb and dt_recebimento_recb are separate vendor dates; benvi-manager
-- lands both since it stopped folding dt_recebimento_recb into dt_liquidacao_recb.
-- Date strings arrive as MM/dd/yyyy or yyyy-MM-dd, so both shapes are parsed.
-- Join id_sacado_sac to locatario.id_sacado_sac, id_contrato_con to contrato.
WITH charge_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key,
        CAST(lake_mirror.payload AS STRING) AS payload_json,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_sacado_sac') AS id_sacado_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_contrato_con') AS id_contrato_con,
        lake_mirror.synced_at
    FROM
        datalake_benvi_manager_raw.lake_mirror AS lake_mirror
    WHERE
        lake_mirror.resource_code = 'CHARGE'
),
tenant_by_sacado AS (
    SELECT
        locatario.id_pessoa_pes,
        locatario.id_sacado_sac,
        ROW_NUMBER() OVER (
            PARTITION BY locatario.id_sacado_sac
            ORDER BY locatario.id
        ) AS rn
    FROM
        datalake_benvi_manager_clean.benvi_superlogica_locatario AS locatario
    WHERE
        locatario.id_sacado_sac IS NOT NULL
)
SELECT
    charge_row.id,
    charge_row.vendor_natural_key AS id_recebimento_recb,
    charge_row.id_sacado_sac,
    tenant_by_sacado.id_pessoa_pes,
    charge_row.id_contrato_con,
    contrato.codigo_contrato,
    get_json_object(charge_row.payload_json, '$.st_nomeref_sac') AS st_nomeref_sac,
    get_json_object(charge_row.payload_json, '$.st_nome_sac') AS st_nome_sac,
    get_json_object(charge_row.payload_json, '$.st_sincro_sac') AS st_sincro_sac,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_desativacao_sac'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_desativacao_sac'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_desativacao_sac,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_congelamento_sac'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_congelamento_sac'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_congelamento_sac,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_ignorarstatus_sac'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_ignorarstatus_sac'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_ignorarstatus_sac,
    get_json_object(charge_row.payload_json, '$.nm_anocartaovencimento_sac') AS nm_anocartaovencimento_sac,
    get_json_object(charge_row.payload_json, '$.nm_mescartaovencimento_sac') AS nm_mescartaovencimento_sac,
    get_json_object(charge_row.payload_json, '$.nm_cartao_sac') AS nm_cartao_sac,
    get_json_object(charge_row.payload_json, '$.st_telefone_sac') AS st_telefone_sac,
    get_json_object(charge_row.payload_json, '$.st_email_sac') AS st_email_sac,
    get_json_object(charge_row.payload_json, '$.st_cep_sac') AS st_cep_sac,
    CAST(get_json_object(charge_row.payload_json, '$.fl_pagamentopref_sac') AS INT) AS fl_pagamentopref_sac,
    CAST(get_json_object(charge_row.payload_json, '$.fl_pessoajuridica_sac') AS INT) AS fl_pessoajuridica_sac,
    get_json_object(charge_row.payload_json, '$.st_banco_sac') AS st_banco_sac,
    get_json_object(charge_row.payload_json, '$.st_cgc_sac') AS st_cgc_sac,
    get_json_object(charge_row.payload_json, '$.st_cartaobandeira_sac') AS st_cartaobandeira_sac,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_vencimento_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_vencimento_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_vencimento_recb,
    get_json_object(charge_row.payload_json, '$.id_empresa_emp') AS id_empresa_emp,
    CAST(get_json_object(charge_row.payload_json, '$.fl_status_recb') AS INT) AS fl_status_recb,
    get_json_object(charge_row.payload_json, '$.st_observacao_recb') AS st_observacao_recb,
    CAST(get_json_object(charge_row.payload_json, '$.vl_total_recb') AS DOUBLE) AS vl_total_recb,
    CAST(get_json_object(charge_row.payload_json, '$.vl_emitido_recb') AS DOUBLE) AS vl_emitido_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_cancelamento_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_cancelamento_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_cancelamento_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_geracao_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_geracao_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_geracao_recb,
    get_json_object(charge_row.payload_json, '$.st_md5_recb') AS st_md5_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_impressao_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_impressao_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_impressao_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_alteracao_sincro'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_alteracao_sincro'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_alteracao_sincro,
    get_json_object(charge_row.payload_json, '$.st_nossonumero_recb') AS st_nossonumero_recb,
    CAST(get_json_object(charge_row.payload_json, '$.vl_txmulta_recb') AS DOUBLE) AS vl_txmulta_recb,
    CAST(get_json_object(charge_row.payload_json, '$.vl_txjuros_recb') AS DOUBLE) AS vl_txjuros_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_proratadia_recb') AS INT) AS fl_proratadia_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_composicao_recb') AS INT) AS fl_composicao_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_acordo_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_acordo_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_acordo_recb,
    get_json_object(charge_row.payload_json, '$.nm_remessa_recb') AS nm_remessa_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_remessastatus_recb') AS INT) AS fl_remessastatus_recb,
    get_json_object(charge_row.payload_json, '$.tx_remessamsg_recb') AS tx_remessamsg_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_importacao_recb') AS INT) AS fl_importacao_recb,
    get_json_object(charge_row.payload_json, '$.id_nota_not') AS id_nota_not,
    get_json_object(charge_row.payload_json, '$.st_instrucoes_recb') AS st_instrucoes_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_online_recb') AS INT) AS fl_online_recb,
    get_json_object(charge_row.payload_json, '$.id_conta_cb') AS id_conta_cb,
    get_json_object(charge_row.payload_json, '$.id_online_recb') AS id_online_recb,
    get_json_object(charge_row.payload_json, '$.nm_impressoes_recb') AS nm_impressoes_recb,
    get_json_object(charge_row.payload_json, '$.id_formapagamento_recb') AS id_formapagamento_recb,
    get_json_object(charge_row.payload_json, '$.st_observacaointerna_recb') AS st_observacaointerna_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_nossonumerofixo_recb') AS INT) AS fl_nossonumerofixo_recb,
    get_json_object(charge_row.payload_json, '$.st_documentoex_recb') AS st_documentoex_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_liquidacao_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_liquidacao_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_liquidacao_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_recebimento_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_recebimento_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_recebimento_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_protestado_recb') AS INT) AS fl_protestado_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_cartao_recb') AS INT) AS fl_cartao_recb,
    get_json_object(charge_row.payload_json, '$.tx_cartaomensagem_recb') AS tx_cartaomensagem_recb,
    get_json_object(charge_row.payload_json, '$.st_label_recb') AS st_label_recb,
    CAST(get_json_object(charge_row.payload_json, '$.vl_txdesconto_recb') AS DOUBLE) AS vl_txdesconto_recb,
    get_json_object(charge_row.payload_json, '$.st_nf_recb') AS st_nf_recb,
    get_json_object(charge_row.payload_json, '$.st_observacaoexterna_recb') AS st_observacaoexterna_recb,
    get_json_object(charge_row.payload_json, '$.st_cielotid_recb') AS st_cielotid_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_cieloforcarpagamento_recb') AS INT) AS fl_cieloforcarpagamento_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_cieloultimatentativa_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_cieloultimatentativa_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_cieloultimatentativa_recb,
    get_json_object(charge_row.payload_json, '$.id_cheque_pre') AS id_cheque_pre,
    get_json_object(charge_row.payload_json, '$.id_fechamento_cfe') AS id_fechamento_cfe,
    get_json_object(charge_row.payload_json, '$.id_usuario_usu') AS id_usuario_usu,
    get_json_object(charge_row.payload_json, '$.st_maquina_recb') AS st_maquina_recb,
    get_json_object(charge_row.payload_json, '$.id_transacao_ctr') AS id_transacao_ctr,
    get_json_object(charge_row.payload_json, '$.id_contaoriginal_cb') AS id_contaoriginal_cb,
    get_json_object(charge_row.payload_json, '$.id_bandeira_ban') AS id_bandeira_ban,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_competencia_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_competencia_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_competencia_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_previsaocredito_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_previsaocredito_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_previsaocredito_recb,
    get_json_object(charge_row.payload_json, '$.id_admcartoes_adc') AS id_admcartoes_adc,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_fechamento_cfe'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_fechamento_cfe'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_fechamento_cfe,
    get_json_object(charge_row.payload_json, '$.st_label2_recb') AS st_label2_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_primeiranotificacao_recb') AS INT) AS fl_primeiranotificacao_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_segundanotificacao_recb') AS INT) AS fl_segundanotificacao_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_terceiranotificacao_recb') AS INT) AS fl_terceiranotificacao_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_acordofrentedecaixa_recb') AS INT) AS fl_acordofrentedecaixa_recb,
    get_json_object(charge_row.payload_json, '$.nm_visto_recb') AS nm_visto_recb,
    get_json_object(charge_row.payload_json, '$.st_numeroautorizacao_recb') AS st_numeroautorizacao_recb,
    get_json_object(charge_row.payload_json, '$.id_lote_recb') AS id_lote_recb,
    get_json_object(charge_row.payload_json, '$.id_contrato_mens') AS id_contrato_mens,
    get_json_object(charge_row.payload_json, '$.id_filial_fil') AS id_filial_fil,
    get_json_object(charge_row.payload_json, '$.st_label3_recb') AS st_label3_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_primeiranotificacaosms_recb') AS INT) AS fl_primeiranotificacaosms_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_segundanotificacaosms_recb') AS INT) AS fl_segundanotificacaosms_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_primeiranotificacaocart_recb') AS INT) AS fl_primeiranotificacaocart_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_segundanotificacaocarta_recb') AS INT) AS fl_segundanotificacaocarta_recb,
    get_json_object(charge_row.payload_json, '$.st_cartaodetalhes_recb') AS st_cartaodetalhes_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_temcomissao_recb') AS INT) AS fl_temcomissao_recb,
    get_json_object(charge_row.payload_json, '$.id_forma_frecb') AS id_forma_frecb,
    get_json_object(charge_row.payload_json, '$.st_label_mens') AS st_label_mens,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_cartaotransacao_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_cartaotransacao_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_cartaotransacao_recb,
    get_json_object(charge_row.payload_json, '$.st_errocartao_recb') AS st_errocartao_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_converterparanota_recb') AS INT) AS fl_converterparanota_recb,
    get_json_object(charge_row.payload_json, '$.id_adesao_plc') AS id_adesao_plc,
    get_json_object(charge_row.payload_json, '$.id_renovacao_plc') AS id_renovacao_plc,
    get_json_object(charge_row.payload_json, '$.st_complementocomposicao_recb') AS st_complementocomposicao_recb,
    get_json_object(charge_row.payload_json, '$.st_tokenfacilitador_recb') AS st_tokenfacilitador_recb,
    get_json_object(charge_row.payload_json, '$.st_tokendaconta_recb') AS st_tokendaconta_recb,
    get_json_object(charge_row.payload_json, '$.st_cielotidcancelamento_recb') AS st_cielotidcancelamento_recb,
    CAST(get_json_object(charge_row.payload_json, '$.vl_taxacobranca_recb') AS DOUBLE) AS vl_taxacobranca_recb,
    get_json_object(charge_row.payload_json, '$.st_hashparcelamento_recb') AS st_hashparcelamento_recb,
    get_json_object(charge_row.payload_json, '$.st_cartaobandeira_recb') AS st_cartaobandeira_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_despesasvinculadas_recb') AS INT) AS fl_despesasvinculadas_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_quartanotificacao_recb') AS INT) AS fl_quartanotificacao_recb,
    get_json_object(charge_row.payload_json, '$.st_tidconciliacao_recb') AS st_tidconciliacao_recb,
    get_json_object(charge_row.payload_json, '$.id_endereco_sen') AS id_endereco_sen,
    CAST(get_json_object(charge_row.payload_json, '$.fl_motivocancelar_recb') AS INT) AS fl_motivocancelar_recb,
    get_json_object(charge_row.payload_json, '$.st_idexterno_recb') AS st_idexterno_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_consultartidtardio_recb') AS INT) AS fl_consultartidtardio_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_ignorarbloqueioauto_recb') AS INT) AS fl_ignorarbloqueioauto_recb,
    get_json_object(charge_row.payload_json, '$.st_numerocartao_recb') AS st_numerocartao_recb,
    get_json_object(charge_row.payload_json, '$.nm_parcelacartao_recb') AS nm_parcelacartao_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_conciliado_recb') AS INT) AS fl_conciliado_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_tipoentrega_recb') AS INT) AS fl_tipoentrega_recb,
    get_json_object(charge_row.payload_json, '$.st_codmovimentacaorem_recb') AS st_codmovimentacaorem_recb,
    get_json_object(charge_row.payload_json, '$.id_contaorigem_recb') AS id_contaorigem_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_contratoprorrogado_recb') AS INT) AS fl_contratoprorrogado_recb,
    get_json_object(charge_row.payload_json, '$.st_marcador_recb') AS st_marcador_recb,
    get_json_object(charge_row.payload_json, '$.id_formaboleto_frecb') AS id_formaboleto_frecb,
    get_json_object(charge_row.payload_json, '$.st_hashemailpag_recb') AS st_hashemailpag_recb,
    get_json_object(charge_row.payload_json, '$.st_accesskeycr_recb') AS st_accesskeycr_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_remessastatuscr_recb') AS INT) AS fl_remessastatuscr_recb,
    get_json_object(charge_row.payload_json, '$.nm_tentativasenviocr_recb') AS nm_tentativasenviocr_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_quintanotificacao_recb') AS INT) AS fl_quintanotificacao_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_sextanotificacao_recb') AS INT) AS fl_sextanotificacao_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_terceiranotificacaosms_recb') AS INT) AS fl_terceiranotificacaosms_recb,
    get_json_object(charge_row.payload_json, '$.nm_descontoatedia_recb') AS nm_descontoatedia_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_txdescontopersonalizada_recb') AS INT) AS fl_txdescontopersonalizada_recb,
    get_json_object(charge_row.payload_json, '$.id_recebimentoantigo_recb') AS id_recebimentoantigo_recb,
    CAST(get_json_object(charge_row.payload_json, '$.vl_descontocalculado_recb') AS DOUBLE) AS vl_descontocalculado_recb,
    get_json_object(charge_row.payload_json, '$.st_splitdados_recb') AS st_splitdados_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_geracaonotificada_recb') AS INT) AS fl_geracaonotificada_recb,
    get_json_object(charge_row.payload_json, '$.nm_versaorecebimento_recb') AS nm_versaorecebimento_recb,
    get_json_object(charge_row.payload_json, '$.nm_versaorecebimentopjbank_recb') AS nm_versaorecebimentopjbank_recb,
    get_json_object(charge_row.payload_json, '$.st_motivocanceloutros_recb') AS st_motivocanceloutros_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_alteracao_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_alteracao_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_alteracao_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_desconsiderarcontabilidade_recb') AS INT) AS fl_desconsiderarcontabilidade_recb,
    get_json_object(charge_row.payload_json, '$.id_partidacontabil_pc') AS id_partidacontabil_pc,
    get_json_object(charge_row.payload_json, '$.id_partidacontabilliquidacao_pc') AS id_partidacontabilliquidacao_pc,
    get_json_object(charge_row.payload_json, '$.id_partidacontabilbaixa_pc') AS id_partidacontabilbaixa_pc,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_vencimentooriginal_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_vencimentooriginal_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_vencimentooriginal_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_pedidoregistropjbank_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_pedidoregistropjbank_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_pedidoregistropjbank_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_pedidobaixapjbank_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_pedidobaixapjbank_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_pedidobaixapjbank_recb,
    get_json_object(charge_row.payload_json, '$.id_operacaosecuritizadora_recb') AS id_operacaosecuritizadora_recb,
    CAST(get_json_object(charge_row.payload_json, '$.fl_statussecuritizadora_recb') AS INT) AS fl_statussecuritizadora_recb,
    get_json_object(charge_row.payload_json, '$.id_operacaopjbank_recb') AS id_operacaopjbank_recb,
    get_json_object(charge_row.payload_json, '$.st_complementolancignorado_recb') AS st_complementolancignorado_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_suspensaocancelada_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(charge_row.payload_json, '$.dt_suspensaocancelada_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_suspensaocancelada_recb,
    get_json_object(charge_row.payload_json, '$.st_pixqrcode_recb') AS st_pixqrcode_recb,
    get_json_object(charge_row.payload_json, '$.st_codigoerrocartao_recb') AS st_codigoerrocartao_recb,
    get_json_object(charge_row.payload_json, '$.st_falhacartao_recb') AS st_falhacartao_recb,
    get_json_object(charge_row.payload_json, '$.nm_tentativascartao_recb') AS nm_tentativascartao_recb,
    get_json_object(charge_row.payload_json, '$.nm_conveniopropriopjbank_recb') AS nm_conveniopropriopjbank_recb,
    get_json_object(charge_row.payload_json, '$.nm_tagcriacao_recb') AS nm_tagcriacao_recb,
    get_json_object(charge_row.payload_json, '$.nm_tagliquidacao_recb') AS nm_tagliquidacao_recb,
    get_json_object(charge_row.payload_json, '$.id_split_recb') AS id_split_recb,
    get_json_object(charge_row.payload_json, '$.ar_nomeformas_calc') AS ar_nomeformas_calc,
    CAST(get_json_object(charge_row.payload_json, '$.vl_valorcreditado_calc') AS DOUBLE) AS vl_valorcreditado_calc,
    CAST(get_json_object(charge_row.payload_json, '$.fl_conta_homologada') AS INT) AS fl_conta_homologada,
    CAST(get_json_object(charge_row.payload_json, '$.fl_cofre') AS INT) AS fl_cofre,
    get_json_object(charge_row.payload_json, '$.st_descricao_cb') AS st_descricao_cb,
    get_json_object(charge_row.payload_json, '$.tipo_conta') AS tipo_conta,
    get_json_object(charge_row.payload_json, '$.era_cartao') AS era_cartao,
    get_json_object(charge_row.payload_json, '$.nome_formatado') AS nome_formatado,
    get_json_object(charge_row.payload_json, '$.publickey') AS publickey,
    get_json_object(charge_row.payload_json, '$.link_2via') AS link_2via,
    get_json_object(charge_row.payload_json, '$.publickey_json') AS publickey_json,
    get_json_object(charge_row.payload_json, '$.link_2via_json') AS link_2via_json,
    get_json_object(charge_row.payload_json, '$.comconfirmacaoleitura') AS comconfirmacaoleitura,
    get_json_object(charge_row.payload_json, '$.acessovistoonline') AS acessovistoonline,
    get_json_object(charge_row.payload_json, '$.descontovalorfixo') AS descontovalorfixo,
    get_json_object(charge_row.payload_json, '$.msgdiasparadesconto') AS msgdiasparadesconto,
    get_json_object(charge_row.payload_json, '$.descontoatedia') AS descontoatedia,
    CAST(get_json_object(charge_row.payload_json, '$.vl_txdesconto_emp') AS DOUBLE) AS vl_txdesconto_emp,
    CAST(get_json_object(charge_row.payload_json, '$.vl_txjuros_emp') AS DOUBLE) AS vl_txjuros_emp,
    CAST(get_json_object(charge_row.payload_json, '$.vl_txmulta_emp') AS DOUBLE) AS vl_txmulta_emp,
    get_json_object(charge_row.payload_json, '$.tx_bancaria') AS tx_bancaria,
    get_json_object(charge_row.payload_json, '$.st_marcador_calc') AS st_marcador_calc,
    CAST(get_json_object(charge_row.payload_json, '$.fl_status_spl') AS INT) AS fl_status_spl,
    get_json_object(charge_row.payload_json, '$.identificador_leitura') AS identificador_leitura,
    get_json_object(charge_row.payload_json, '$.compo_recebimento') AS compo_recebimento,
    get_json_object(charge_row.payload_json, '$.erros_split') AS erros_split,
    get_json_object(charge_row.payload_json, '$.split_indisponivel') AS split_indisponivel,
    charge_row.synced_at AS ts_synced
FROM
    charge_row AS charge_row
LEFT JOIN
    tenant_by_sacado AS tenant_by_sacado
        ON charge_row.id_sacado_sac = tenant_by_sacado.id_sacado_sac
        AND tenant_by_sacado.rn = 1
LEFT JOIN
    datalake_benvi_manager_clean.benvi_superlogica_contrato AS contrato
        ON charge_row.id_contrato_con = contrato.id_contrato_con
