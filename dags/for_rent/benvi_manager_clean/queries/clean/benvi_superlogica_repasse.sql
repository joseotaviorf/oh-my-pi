-- Widened to the full PAYOUT payload so RAW repasses in the extraction spreadsheet maps
-- one to one onto this projection.
-- fonte_extracao has no vendor key: the extraction script writes the constant
-- repasses_realizados, reproduced here as a literal.
-- Join id_contrato_con to contrato, id_recebimento_recb to cobranca,
-- id_locatario_pes to locatario.id_pessoa_pes.
WITH payout_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key,
        CAST(lake_mirror.payload AS STRING) AS payload_json,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_contrato_con') AS id_contrato_con,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_recebimento_recb') AS id_recebimento_recb,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_locatario_pes') AS id_locatario_pes,
        lake_mirror.synced_at
    FROM
        datalake_benvi_manager_raw.lake_mirror AS lake_mirror
    WHERE
        lake_mirror.resource_code = 'PAYOUT'
)
SELECT
    payout_row.id,
    payout_row.vendor_natural_key AS id_repasse_rep,
    payout_row.id_contrato_con,
    contrato.codigo_contrato,
    payout_row.id_recebimento_recb,
    cobranca.id_sacado_sac,
    payout_row.id_locatario_pes,
    locatario.nome_pes,
    get_json_object(payout_row.payload_json, '$.id_imovel_imo') AS id_imovel_imo,
    get_json_object(payout_row.payload_json, '$.st_tipo_imo') AS st_tipo_imo,
    get_json_object(payout_row.payload_json, '$.st_identificador_imo') AS st_identificador_imo,
    get_json_object(payout_row.payload_json, '$.st_endereco_imo') AS st_endereco_imo,
    get_json_object(payout_row.payload_json, '$.st_bairro_imo') AS st_bairro_imo,
    get_json_object(payout_row.payload_json, '$.st_numero_imo') AS st_numero_imo,
    get_json_object(payout_row.payload_json, '$.st_cep_imo') AS st_cep_imo,
    get_json_object(payout_row.payload_json, '$.st_cidade_imo') AS st_cidade_imo,
    get_json_object(payout_row.payload_json, '$.st_estado_imo') AS st_estado_imo,
    get_json_object(payout_row.payload_json, '$.st_complemento_imo') AS st_complemento_imo,
    get_json_object(payout_row.payload_json, '$.st_tipodimob_imo') AS st_tipodimob_imo,
    get_json_object(payout_row.payload_json, '$.id_tipo_con') AS id_tipo_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_inicio_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_inicio_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_inicio_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_fim_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_fim_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_fim_con,
    get_json_object(payout_row.payload_json, '$.tx_adm_con') AS tx_adm_con,
    CAST(get_json_object(payout_row.payload_json, '$.vl_aluguel_con') AS DOUBLE) AS vl_aluguel_con,
    get_json_object(payout_row.payload_json, '$.nm_diavencimento_con') AS nm_diavencimento_con,
    get_json_object(payout_row.payload_json, '$.id_indicereajuste_con') AS id_indicereajuste_con,
    get_json_object(payout_row.payload_json, '$.nm_txjuros_con') AS nm_txjuros_con,
    get_json_object(payout_row.payload_json, '$.nm_txmulta_con') AS nm_txmulta_con,
    get_json_object(payout_row.payload_json, '$.nm_txdesconto_con') AS nm_txdesconto_con,
    get_json_object(payout_row.payload_json, '$.tx_locacao_con') AS tx_locacao_con,
    get_json_object(payout_row.payload_json, '$.id_corretor_con') AS id_corretor_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_garantia_con') AS INT) AS fl_garantia_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_tipocaucaogarantia_con') AS INT) AS fl_tipocaucaogarantia_con,
    get_json_object(payout_row.payload_json, '$.st_descricaogarantia_con') AS st_descricaogarantia_con,
    get_json_object(payout_row.payload_json, '$.st_identificadorgarantia_con') AS st_identificadorgarantia_con,
    get_json_object(payout_row.payload_json, '$.st_observacaogarantia_con') AS st_observacaogarantia_con,
    CAST(get_json_object(payout_row.payload_json, '$.vl_valorgarantia_con') AS DOUBLE) AS vl_valorgarantia_con,
    get_json_object(payout_row.payload_json, '$.nm_diarepasse_con') AS nm_diarepasse_con,
    get_json_object(payout_row.payload_json, '$.nm_mesreajuste_con') AS nm_mesreajuste_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_rescisao_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_rescisao_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_rescisao_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_ativo_con') AS INT) AS fl_ativo_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_garantiainicio_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_garantiainicio_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_garantiainicio_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_garantiafim_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_garantiafim_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_garantiafim_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_garantiaresponsavel_con') AS INT) AS fl_garantiaresponsavel_con,
    get_json_object(payout_row.payload_json, '$.nm_garantiaparcelas_con') AS nm_garantiaparcelas_con,
    CAST(get_json_object(payout_row.payload_json, '$.vl_garantiaparcela_con') AS DOUBLE) AS vl_garantiaparcela_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_seguroincendioinicio_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_seguroincendioinicio_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_seguroincendioinicio_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_seguroincendiofim_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_seguroincendiofim_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_seguroincendiofim_con,
    CAST(get_json_object(payout_row.payload_json, '$.vl_seguroincendio_con') AS DOUBLE) AS vl_seguroincendio_con,
    get_json_object(payout_row.payload_json, '$.st_seguroincendiodescricao_con') AS st_seguroincendiodescricao_con,
    get_json_object(payout_row.payload_json, '$.st_seguroincendioidentificador_con') AS st_seguroincendioidentificador_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_responsavelcontrato_con') AS INT) AS fl_responsavelcontrato_con,
    get_json_object(payout_row.payload_json, '$.st_seguroincendioplanocontrato_con') AS st_seguroincendioplanocontrato_con,
    get_json_object(payout_row.payload_json, '$.st_seguroincendioobservacao_con') AS st_seguroincendioobservacao_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_seguroincendio_con') AS INT) AS fl_seguroincendio_con,
    get_json_object(payout_row.payload_json, '$.nm_locacoesimovel_con') AS nm_locacoesimovel_con,
    get_json_object(payout_row.payload_json, '$.id_mensalidade_mens') AS id_mensalidade_mens,
    CAST(get_json_object(payout_row.payload_json, '$.fl_endcobranca_con') AS INT) AS fl_endcobranca_con,
    get_json_object(payout_row.payload_json, '$.st_cep_con') AS st_cep_con,
    get_json_object(payout_row.payload_json, '$.st_endereco_con') AS st_endereco_con,
    get_json_object(payout_row.payload_json, '$.st_numero_con') AS st_numero_con,
    get_json_object(payout_row.payload_json, '$.st_complemento_con') AS st_complemento_con,
    get_json_object(payout_row.payload_json, '$.st_bairro_con') AS st_bairro_con,
    get_json_object(payout_row.payload_json, '$.st_cidade_con') AS st_cidade_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_ultimoreajuste_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_ultimoreajuste_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_ultimoreajuste_con,
    get_json_object(payout_row.payload_json, '$.st_estado_con') AS st_estado_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_txadmvalorfixo_con') AS INT) AS fl_txadmvalorfixo_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_txlocacaovalorfixo_con') AS INT) AS fl_txlocacaovalorfixo_con,
    get_json_object(payout_row.payload_json, '$.nm_parcelastxlocacao_con') AS nm_parcelastxlocacao_con,
    get_json_object(payout_row.payload_json, '$.nm_repassegarantido_con') AS nm_repassegarantido_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_cobrarnosegundoaluguel_con') AS INT) AS fl_cobrarnosegundoaluguel_con,
    get_json_object(payout_row.payload_json, '$.id_primeiraparcela_con') AS id_primeiraparcela_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_reterir_con') AS INT) AS fl_reterir_con,
    get_json_object(payout_row.payload_json, '$.st_label_mens') AS st_label_mens,
    CAST(get_json_object(payout_row.payload_json, '$.fl_emitirnotafiscal_con') AS INT) AS fl_emitirnotafiscal_con,
    get_json_object(payout_row.payload_json, '$.id_contabanco_cb') AS id_contabanco_cb,
    CAST(get_json_object(payout_row.payload_json, '$.fl_mesvencido_con') AS INT) AS fl_mesvencido_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_diafixorepasse_con') AS INT) AS fl_diafixorepasse_con,
    get_json_object(payout_row.payload_json, '$.st_clausulas_con') AS st_clausulas_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_faturamento_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_faturamento_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_faturamento_con,
    get_json_object(payout_row.payload_json, '$.tx_multacontratual_con') AS tx_multacontratual_con,
    CAST(get_json_object(payout_row.payload_json, '$.vl_tarifabancariarepasse_con') AS DOUBLE) AS vl_tarifabancariarepasse_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_tarifabancariarepasse_con') AS INT) AS fl_tarifabancariarepasse_con,
    get_json_object(payout_row.payload_json, '$.id_txbancaria_mens') AS id_txbancaria_mens,
    CAST(get_json_object(payout_row.payload_json, '$.fl_cobrartxbancaria_con') AS INT) AS fl_cobrartxbancaria_con,
    get_json_object(payout_row.payload_json, '$.id_endereco_sen') AS id_endereco_sen,
    CAST(get_json_object(payout_row.payload_json, '$.fl_status_con') AS INT) AS fl_status_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_tipoentrega_con') AS INT) AS fl_tipoentrega_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_suspenso_con') AS INT) AS fl_suspenso_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_dimob_con') AS INT) AS fl_dimob_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_desocupacao_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_desocupacao_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_desocupacao_con,
    get_json_object(payout_row.payload_json, '$.st_atividadecomercial_con') AS st_atividadecomercial_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_txlocacao_con') AS INT) AS fl_txlocacao_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_renovacao_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_renovacao_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_renovacao_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_irdeduzirtxadm_con') AS INT) AS fl_irdeduzirtxadm_con,
    get_json_object(payout_row.payload_json, '$.nm_carencia_con') AS nm_carencia_con,
    get_json_object(payout_row.payload_json, '$.id_seguro_seg') AS id_seguro_seg,
    CAST(get_json_object(payout_row.payload_json, '$.fl_mesfechado_con') AS INT) AS fl_mesfechado_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_cadastro_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_cadastro_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_cadastro_con,
    get_json_object(payout_row.payload_json, '$.id_filial_fil') AS id_filial_fil,
    CAST(get_json_object(payout_row.payload_json, '$.fl_split_con') AS INT) AS fl_split_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_contratodigital_con') AS INT) AS fl_contratodigital_con,
    get_json_object(payout_row.payload_json, '$.id_arquivo_arq') AS id_arquivo_arq,
    get_json_object(payout_row.payload_json, '$.st_observacaorecisao_con') AS st_observacaorecisao_con,
    get_json_object(payout_row.payload_json, '$.st_observacao_con') AS st_observacao_con,
    CAST(get_json_object(payout_row.payload_json, '$.vl_importanciaseguradaincendio_con') AS DOUBLE) AS vl_importanciaseguradaincendio_con,
    CAST(get_json_object(payout_row.payload_json, '$.vl_premioseguroincendio_con') AS DOUBLE) AS vl_premioseguroincendio_con,
    get_json_object(payout_row.payload_json, '$.id_seguradora_seg') AS id_seguradora_seg,
    get_json_object(payout_row.payload_json, '$.st_motivopausa_con') AS st_motivopausa_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_ultimapausa_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_ultimapausa_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_ultimapausa_con,
    get_json_object(payout_row.payload_json, '$.nm_parcelasseguroincendio_con') AS nm_parcelasseguroincendio_con,
    get_json_object(payout_row.payload_json, '$.id_seguradorafianca_con') AS id_seguradorafianca_con,
    get_json_object(payout_row.payload_json, '$.id_forma_pag') AS id_forma_pag,
    CAST(get_json_object(payout_row.payload_json, '$.fl_locacaodigital_con') AS INT) AS fl_locacaodigital_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_previsaodesocupacao_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_previsaodesocupacao_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_previsaodesocupacao_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_sincronizacaofaturamento_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_sincronizacaofaturamento_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_sincronizacaofaturamento_con,
    get_json_object(payout_row.payload_json, '$.st_linkpropostaexterna_con') AS st_linkpropostaexterna_con,
    get_json_object(payout_row.payload_json, '$.st_propostaexterna_con') AS st_propostaexterna_con,
    get_json_object(payout_row.payload_json, '$.nm_mesesisencaomulta_con') AS nm_mesesisencaomulta_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_ocupacao_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_ocupacao_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_ocupacao_con,
    get_json_object(payout_row.payload_json, '$.id_agentecomercial_con') AS id_agentecomercial_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_tiporepassegarantido_con') AS INT) AS fl_tiporepassegarantido_con,
    get_json_object(payout_row.payload_json, '$.id_contarepasse_con') AS id_contarepasse_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_atualizacao_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_atualizacao_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_atualizacao_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_tipoatividade_con') AS INT) AS fl_tipoatividade_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_entregachaves_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_entregachaves_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_entregachaves_con,
    get_json_object(payout_row.payload_json, '$.id_gerente_con') AS id_gerente_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_motivorescisao_con') AS INT) AS fl_motivorescisao_con,
    get_json_object(payout_row.payload_json, '$.id_garantia_grt') AS id_garantia_grt,
    get_json_object(payout_row.payload_json, '$.st_cotacao_grt') AS st_cotacao_grt,
    CAST(get_json_object(payout_row.payload_json, '$.fl_reterjurosemulta_con') AS INT) AS fl_reterjurosemulta_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_multisplit_con') AS INT) AS fl_multisplit_con,
    get_json_object(payout_row.payload_json, '$.st_outromotivo_con') AS st_outromotivo_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_seguroincendiostatus_con') AS INT) AS fl_seguroincendiostatus_con,
    get_json_object(payout_row.payload_json, '$.id_identificadorimportacao_con') AS id_identificadorimportacao_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_irporcentagemlocatario_con') AS INT) AS fl_irporcentagemlocatario_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_cobrarseguroaluguel_con') AS INT) AS fl_cobrarseguroaluguel_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_renovacaoautomatica_con') AS INT) AS fl_renovacaoautomatica_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_notificacaoocupacao_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_notificacaoocupacao_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_notificacaoocupacao_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_notificacaodesocupacao_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_notificacaodesocupacao_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_notificacaodesocupacao_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_refproporcionalocupacao_con'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_refproporcionalocupacao_con'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_refproporcionalocupacao_con,
    get_json_object(payout_row.payload_json, '$.st_emailgarantia_con') AS st_emailgarantia_con,
    CAST(get_json_object(payout_row.payload_json, '$.fl_destinacaofiscal_con') AS INT) AS fl_destinacaofiscal_con,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_proc_rep'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_proc_rep'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_proc_rep,
    CAST(get_json_object(payout_row.payload_json, '$.fl_status_rep') AS INT) AS fl_status_rep,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_liquidacao_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_liquidacao_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_liquidacao_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_credito_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_credito_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_credito_recb,
    CAST(get_json_object(payout_row.payload_json, '$.vl_total_recb') AS DOUBLE) AS vl_total_recb,
    get_json_object(payout_row.payload_json, '$.st_md5_recb') AS st_md5_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_geracao_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_geracao_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_geracao_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_competencia_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_competencia_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_competencia_recb,
    CAST(get_json_object(payout_row.payload_json, '$.fl_garantido_rep') AS INT) AS fl_garantido_rep,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_vencimento_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_vencimento_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_vencimento_recb,
    CAST(get_json_object(payout_row.payload_json, '$.vl_aluguel_rep') AS DOUBLE) AS vl_aluguel_rep,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_repasse_rep'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_repasse_rep'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_repasse_rep,
    get_json_object(payout_row.payload_json, '$.st_label3_recb') AS st_label3_recb,
    get_json_object(payout_row.payload_json, '$.st_label_recb') AS st_label_recb,
    get_json_object(payout_row.payload_json, '$.id_acordo_aco') AS id_acordo_aco,
    get_json_object(payout_row.payload_json, '$.st_observacaoexterna_rep') AS st_observacaoexterna_rep,
    CAST(get_json_object(payout_row.payload_json, '$.fl_repassougarantido_rep') AS INT) AS fl_repassougarantido_rep,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_notafiscal_rep'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_notafiscal_rep'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_notafiscal_rep,
    get_json_object(payout_row.payload_json, '$.id_repasseagrupado_rep') AS id_repasseagrupado_rep,
    CAST(get_json_object(payout_row.payload_json, '$.fl_agrupado_rep') AS INT) AS fl_agrupado_rep,
    CAST(get_json_object(payout_row.payload_json, '$.fl_split_rep') AS INT) AS fl_split_rep,
    get_json_object(payout_row.payload_json, '$.tx_adm_rep') AS tx_adm_rep,
    CAST(get_json_object(payout_row.payload_json, '$.fl_txadmfixa_rep') AS INT) AS fl_txadmfixa_rep,
    CAST(get_json_object(payout_row.payload_json, '$.vl_txadm_rep') AS DOUBLE) AS vl_txadm_rep,
    get_json_object(payout_row.payload_json, '$.id_formapagamento_recb') AS id_formapagamento_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_atualizacao_rep'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_atualizacao_rep'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_atualizacao_rep,
    CAST(get_json_object(payout_row.payload_json, '$.fl_spliterro') AS INT) AS fl_spliterro,
    CAST(get_json_object(payout_row.payload_json, '$.fl_splitindisponivel') AS INT) AS fl_splitindisponivel,
    CAST(get_json_object(payout_row.payload_json, '$.fl_status_spl') AS INT) AS fl_status_spl,
    get_json_object(payout_row.payload_json, '$.nome_imovel_formatado') AS nome_imovel_formatado,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_pagamento'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payout_row.payload_json, '$.dt_pagamento'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_pagamento,
    get_json_object(payout_row.payload_json, '$.erros_split') AS erros_split,
    get_json_object(payout_row.payload_json, '$.imovel_formatado') AS imovel_formatado,
    get_json_object(payout_row.payload_json, '$.proprietarios_beneficiarios') AS proprietarios_beneficiarios,
    get_json_object(payout_row.payload_json, '$.repasse_item') AS repasse_item,
    get_json_object(payout_row.payload_json, '$.split_indisponivel') AS split_indisponivel,
    'repasses_realizados' AS fonte_extracao,
    payout_row.synced_at AS ts_synced
FROM
    payout_row AS payout_row
LEFT JOIN
    datalake_benvi_manager_clean.benvi_superlogica_contrato AS contrato
        ON payout_row.id_contrato_con = contrato.id_contrato_con
LEFT JOIN
    datalake_benvi_manager_clean.benvi_superlogica_cobranca AS cobranca
        ON payout_row.id_recebimento_recb = cobranca.id_recebimento_recb
LEFT JOIN
    datalake_benvi_manager_clean.benvi_superlogica_locatario AS locatario
        ON payout_row.id_locatario_pes = locatario.id_pessoa_pes
