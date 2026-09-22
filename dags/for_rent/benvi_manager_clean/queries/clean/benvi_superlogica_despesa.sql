-- Union of CONTRACT_EXPENSE (GET /despesas) and VACANT_PROPERTY_EXPENSE
-- (GET /imoveisdespesa), widened to every key either endpoint sends.
-- Same launch id keeps the CONTRACT_EXPENSE row.
-- The 12 column spreadsheet tab RAW despesas_full is a derived view over this one,
-- projected separately as benvi_superlogica_despesa_full.
WITH expense_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key,
        CAST(lake_mirror.payload AS STRING) AS payload_json,
        lake_mirror.synced_at,
        lake_mirror.resource_code,
        ROW_NUMBER() OVER (
            PARTITION BY lake_mirror.vendor_natural_key
            ORDER BY
                CASE lake_mirror.resource_code
                    WHEN 'CONTRACT_EXPENSE' THEN 0
                    ELSE 1
                END,
                lake_mirror.id
        ) AS rn
    FROM
        datalake_benvi_manager_raw.lake_mirror AS lake_mirror
    WHERE
        lake_mirror.resource_code IN ('CONTRACT_EXPENSE', 'VACANT_PROPERTY_EXPENSE')
)
SELECT
    expense_row.id,
    expense_row.vendor_natural_key AS id_lancamento_imod,
    expense_row.resource_code,
    get_json_object(expense_row.payload_json, '$.competencia') AS competencia,
    get_json_object(expense_row.payload_json, '$.credito_reembolso') AS credito_reembolso,
    get_json_object(expense_row.payload_json, '$.despesas_parcela') AS despesas_parcela,
    get_json_object(expense_row.payload_json, '$.detalhes_contrato') AS detalhes_contrato,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_atualizacao_imod'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_atualizacao_imod'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_atualizacao_imod,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_competencia_aux'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_competencia_aux'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_competencia_aux,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_competencia_imod'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_competencia_imod'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_competencia_imod,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_fim_imodm'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_fim_imodm'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_fim_imodm,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_inicio_imodm'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_inicio_imodm'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_inicio_imodm,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_lancamento_imod'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_lancamento_imod'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_lancamento_imod,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_liquidacao_imom'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_liquidacao_imom'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_liquidacao_imom,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_liquidacao_mov'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_liquidacao_mov'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_liquidacao_mov,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_liquidacao_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_liquidacao_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_liquidacao_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_recebimento_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_recebimento_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_recebimento_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_referencia_imod'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_referencia_imod'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_referencia_imod,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_referenciareembolso'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_referenciareembolso'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_referenciareembolso,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_repasse_rep'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_repasse_rep'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_repasse_rep,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_vencimento_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(expense_row.payload_json, '$.dt_vencimento_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_vencimento_recb,
    CAST(get_json_object(expense_row.payload_json, '$.fl_agrupado_rep') AS INT) AS fl_agrupado_rep,
    CAST(get_json_object(expense_row.payload_json, '$.fl_alterouvalor_imod') AS INT) AS fl_alterouvalor_imod,
    CAST(get_json_object(expense_row.payload_json, '$.fl_calcularproporcionalrescisao') AS INT) AS fl_calcularproporcionalrescisao,
    CAST(get_json_object(expense_row.payload_json, '$.fl_calcularproporcionalrescisao_imod') AS INT) AS fl_calcularproporcionalrescisao_imod,
    CAST(get_json_object(expense_row.payload_json, '$.fl_cobrartxadm_imod') AS INT) AS fl_cobrartxadm_imod,
    CAST(get_json_object(expense_row.payload_json, '$.fl_cobrartxadm_imodm') AS INT) AS fl_cobrartxadm_imodm,
    CAST(get_json_object(expense_row.payload_json, '$.fl_conciliado_imod') AS INT) AS fl_conciliado_imod,
    CAST(get_json_object(expense_row.payload_json, '$.fl_despesaalterada_imod') AS INT) AS fl_despesaalterada_imod,
    CAST(get_json_object(expense_row.payload_json, '$.fl_despesacaixaexcluida_imod') AS INT) AS fl_despesacaixaexcluida_imod,
    CAST(get_json_object(expense_row.payload_json, '$.fl_despesaproporcional') AS INT) AS fl_despesaproporcional,
    CAST(get_json_object(expense_row.payload_json, '$.fl_despesaproporcional_imod') AS INT) AS fl_despesaproporcional_imod,
    CAST(get_json_object(expense_row.payload_json, '$.fl_elegivel_alterar_credito_imobiliaria') AS INT) AS fl_elegivel_alterar_credito_imobiliaria,
    CAST(get_json_object(expense_row.payload_json, '$.fl_especial_imod') AS INT) AS fl_especial_imod,
    CAST(get_json_object(expense_row.payload_json, '$.fl_especialfin_imod') AS INT) AS fl_especialfin_imod,
    CAST(get_json_object(expense_row.payload_json, '$.fl_exibir_imod') AS INT) AS fl_exibir_imod,
    CAST(get_json_object(expense_row.payload_json, '$.fl_garantida_imod') AS INT) AS fl_garantida_imod,
    CAST(get_json_object(expense_row.payload_json, '$.fl_pagtoantecipado_imod') AS INT) AS fl_pagtoantecipado_imod,
    CAST(get_json_object(expense_row.payload_json, '$.fl_parcelada') AS INT) AS fl_parcelada,
    CAST(get_json_object(expense_row.payload_json, '$.fl_parcelada_imod') AS INT) AS fl_parcelada_imod,
    CAST(get_json_object(expense_row.payload_json, '$.fl_remessastatus_mov') AS INT) AS fl_remessastatus_mov,
    CAST(get_json_object(expense_row.payload_json, '$.fl_repassar_imod') AS INT) AS fl_repassar_imod,
    CAST(get_json_object(expense_row.payload_json, '$.fl_retencao_imod') AS INT) AS fl_retencao_imod,
    CAST(get_json_object(expense_row.payload_json, '$.fl_status_imod') AS INT) AS fl_status_imod,
    CAST(get_json_object(expense_row.payload_json, '$.fl_status_mov') AS INT) AS fl_status_mov,
    CAST(get_json_object(expense_row.payload_json, '$.fl_status_recb') AS INT) AS fl_status_recb,
    CAST(get_json_object(expense_row.payload_json, '$.fl_statusdebito_imod') AS INT) AS fl_statusdebito_imod,
    CAST(get_json_object(expense_row.payload_json, '$.fl_terceiroexcluido_desp') AS INT) AS fl_terceiroexcluido_desp,
    CAST(get_json_object(expense_row.payload_json, '$.fl_tipo_imod') AS INT) AS fl_tipo_imod,
    CAST(get_json_object(expense_row.payload_json, '$.fl_tipocompetencia') AS INT) AS fl_tipocompetencia,
    get_json_object(expense_row.payload_json, '$.id_acordo_aco') AS id_acordo_aco,
    get_json_object(expense_row.payload_json, '$.id_contabanco_cb') AS id_contabanco_cb,
    get_json_object(expense_row.payload_json, '$.id_contrato_con') AS id_contrato_con,
    get_json_object(expense_row.payload_json, '$.id_credito_imod') AS id_credito_imod,
    get_json_object(expense_row.payload_json, '$.id_credito_imodm') AS id_credito_imodm,
    get_json_object(expense_row.payload_json, '$.id_debito_imod') AS id_debito_imod,
    get_json_object(expense_row.payload_json, '$.id_debito_imodm') AS id_debito_imodm,
    get_json_object(expense_row.payload_json, '$.id_despesa') AS id_despesa,
    get_json_object(expense_row.payload_json, '$.id_despesa_desp') AS id_despesa_desp,
    get_json_object(expense_row.payload_json, '$.id_despesa_despm') AS id_despesa_despm,
    get_json_object(expense_row.payload_json, '$.id_despesaorigem_imod') AS id_despesaorigem_imod,
    get_json_object(expense_row.payload_json, '$.id_despesareembolso_imod') AS id_despesareembolso_imod,
    get_json_object(expense_row.payload_json, '$.id_faturamento_comp') AS id_faturamento_comp,
    get_json_object(expense_row.payload_json, '$.id_faturamento_facs') AS id_faturamento_facs,
    get_json_object(expense_row.payload_json, '$.id_formapagamento_imod') AS id_formapagamento_imod,
    get_json_object(expense_row.payload_json, '$.id_formapagamento_imodm') AS id_formapagamento_imodm,
    get_json_object(expense_row.payload_json, '$.id_formarecebimento_frp') AS id_formarecebimento_frp,
    get_json_object(expense_row.payload_json, '$.id_imovel_imo') AS id_imovel_imo,
    get_json_object(expense_row.payload_json, '$.id_iptulancamento_iil') AS id_iptulancamento_iil,
    get_json_object(expense_row.payload_json, '$.id_lancamento_imodm') AS id_lancamento_imodm,
    get_json_object(expense_row.payload_json, '$.id_lancamentocredito_imod') AS id_lancamentocredito_imod,
    get_json_object(expense_row.payload_json, '$.id_lancamentodebito_imod') AS id_lancamentodebito_imod,
    get_json_object(expense_row.payload_json, '$.id_lanctoprogrealizado_lpr') AS id_lanctoprogrealizado_lpr,
    get_json_object(expense_row.payload_json, '$.id_md5parcelamento_imod') AS id_md5parcelamento_imod,
    get_json_object(expense_row.payload_json, '$.id_mensalidade_mens') AS id_mensalidade_mens,
    get_json_object(expense_row.payload_json, '$.id_orcamento_morc') AS id_orcamento_morc,
    get_json_object(expense_row.payload_json, '$.id_pagtoindevido_imod') AS id_pagtoindevido_imod,
    get_json_object(expense_row.payload_json, '$.id_previsao_prt') AS id_previsao_prt,
    get_json_object(expense_row.payload_json, '$.id_produto_prd') AS id_produto_prd,
    get_json_object(expense_row.payload_json, '$.id_propdiferenca_imod') AS id_propdiferenca_imod,
    get_json_object(expense_row.payload_json, '$.id_proprietariocredito_imod') AS id_proprietariocredito_imod,
    get_json_object(expense_row.payload_json, '$.id_proprietariodebito_imod') AS id_proprietariodebito_imod,
    get_json_object(expense_row.payload_json, '$.id_recebimento_recb') AS id_recebimento_recb,
    get_json_object(expense_row.payload_json, '$.id_repasse_rep') AS id_repasse_rep,
    get_json_object(expense_row.payload_json, '$.id_seguro_seg') AS id_seguro_seg,
    get_json_object(expense_row.payload_json, '$.id_terceiro_fav') AS id_terceiro_fav,
    get_json_object(expense_row.payload_json, '$.imovel_formatado') AS imovel_formatado,
    get_json_object(expense_row.payload_json, '$.movimentacoes') AS movimentacoes,
    get_json_object(expense_row.payload_json, '$.nm_diavencimento_con') AS nm_diavencimento_con,
    get_json_object(expense_row.payload_json, '$.nm_diavencimento_imodm') AS nm_diavencimento_imodm,
    get_json_object(expense_row.payload_json, '$.nm_locacoesimovel_con') AS nm_locacoesimovel_con,
    get_json_object(expense_row.payload_json, '$.nm_parcelas') AS nm_parcelas,
    get_json_object(expense_row.payload_json, '$.nm_parcelas_fim') AS nm_parcelas_fim,
    get_json_object(expense_row.payload_json, '$.nm_tagcriacao') AS nm_tagcriacao,
    get_json_object(expense_row.payload_json, '$.nm_tagcriacao_imod') AS nm_tagcriacao_imod,
    get_json_object(expense_row.payload_json, '$.nm_tagliquidacao') AS nm_tagliquidacao,
    get_json_object(expense_row.payload_json, '$.nm_tagliquidacao_imod') AS nm_tagliquidacao_imod,
    get_json_object(expense_row.payload_json, '$.nm_tipo_imodm') AS nm_tipo_imodm,
    get_json_object(expense_row.payload_json, '$.nome_imovel') AS nome_imovel,
    get_json_object(expense_row.payload_json, '$.nome_proprietariocredito') AS nome_proprietariocredito,
    get_json_object(expense_row.payload_json, '$.nome_proprietariodebito') AS nome_proprietariodebito,
    get_json_object(expense_row.payload_json, '$.produto_opcional') AS produto_opcional,
    get_json_object(expense_row.payload_json, '$.repasses') AS repasses,
    get_json_object(expense_row.payload_json, '$.st_bairro_imo') AS st_bairro_imo,
    get_json_object(expense_row.payload_json, '$.st_cep_imo') AS st_cep_imo,
    get_json_object(expense_row.payload_json, '$.st_codigobarras_mov') AS st_codigobarras_mov,
    get_json_object(expense_row.payload_json, '$.st_complemento') AS st_complemento,
    get_json_object(expense_row.payload_json, '$.st_complemento_imo') AS st_complemento_imo,
    get_json_object(expense_row.payload_json, '$.st_complemento_imod') AS st_complemento_imod,
    get_json_object(expense_row.payload_json, '$.st_conta_cont') AS st_conta_cont,
    get_json_object(expense_row.payload_json, '$.st_cpfcnpjpagadororiginal_imod') AS st_cpfcnpjpagadororiginal_imod,
    get_json_object(expense_row.payload_json, '$.st_descricao_prd') AS st_descricao_prd,
    get_json_object(expense_row.payload_json, '$.st_endereco_imo') AS st_endereco_imo,
    get_json_object(expense_row.payload_json, '$.st_hashcomposicaoparcela_imod') AS st_hashcomposicaoparcela_imod,
    get_json_object(expense_row.payload_json, '$.st_hashdespesa_imod') AS st_hashdespesa_imod,
    get_json_object(expense_row.payload_json, '$.st_identificador_imo') AS st_identificador_imo,
    get_json_object(expense_row.payload_json, '$.st_label3_recb') AS st_label3_recb,
    get_json_object(expense_row.payload_json, '$.st_label_imod') AS st_label_imod,
    get_json_object(expense_row.payload_json, '$.st_label_recb') AS st_label_recb,
    get_json_object(expense_row.payload_json, '$.st_numero_imo') AS st_numero_imo,
    get_json_object(expense_row.payload_json, '$.st_split_imod') AS st_split_imod,
    get_json_object(expense_row.payload_json, '$.st_tipo_imo') AS st_tipo_imo,
    get_json_object(expense_row.payload_json, '$.tem_composicao_alterada') AS tem_composicao_alterada,
    get_json_object(expense_row.payload_json, '$.valor') AS valor,
    get_json_object(expense_row.payload_json, '$.vencimento') AS vencimento,
    CAST(get_json_object(expense_row.payload_json, '$.vl_pagtoindevido_imod') AS DOUBLE) AS vl_pagtoindevido_imod,
    CAST(get_json_object(expense_row.payload_json, '$.vl_valor_imod') AS DOUBLE) AS vl_valor_imod,
    CAST(get_json_object(expense_row.payload_json, '$.vl_valor_imodm') AS DOUBLE) AS vl_valor_imodm,
    expense_row.synced_at AS ts_synced
FROM
    expense_row AS expense_row
WHERE
    expense_row.rn = 1
