-- Widened to the full MAINTENANCE payload so RAW manutencoes in the extraction
-- spreadsheet maps one to one onto this projection.
WITH maintenance_row AS (
    SELECT
        id,
        vendor_natural_key,
        CAST(payload AS STRING) AS payload_json,
        synced_at
    FROM
        datalake_benvi_manager_raw.lake_mirror
    WHERE
        resource_code = 'MAINTENANCE'
)
SELECT
    id,
    vendor_natural_key AS id_manutencao_man,
    get_json_object(payload_json, '$.id_imovel_imo') AS id_imovel_imo,
    get_json_object(payload_json, '$.st_identificador_imo') AS st_identificador_imo,
    get_json_object(payload_json, '$.st_tipo_imo') AS st_tipo_imo,
    get_json_object(payload_json, '$.st_endereco_imo') AS st_endereco_imo,
    get_json_object(payload_json, '$.st_numero_imo') AS st_numero_imo,
    get_json_object(payload_json, '$.st_complemento_imo') AS st_complemento_imo,
    get_json_object(payload_json, '$.st_bairro_imo') AS st_bairro_imo,
    get_json_object(payload_json, '$.st_cidade_imo') AS st_cidade_imo,
    get_json_object(payload_json, '$.st_estado_imo') AS st_estado_imo,
    get_json_object(payload_json, '$.st_cep_imo') AS st_cep_imo,
    get_json_object(payload_json, '$.st_cartorio_imo') AS st_cartorio_imo,
    get_json_object(payload_json, '$.st_matriculacartorio_imo') AS st_matriculacartorio_imo,
    get_json_object(payload_json, '$.st_nome_cond') AS st_nome_cond,
    get_json_object(payload_json, '$.nm_orcamentos_pendentes_lancar_despesas') AS nm_orcamentos_pendentes_lancar_despesas,
    get_json_object(payload_json, '$.nm_arquivos') AS nm_arquivos,
    get_json_object(payload_json, '$.st_identificador_man') AS st_identificador_man,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_criacao_man'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_criacao_man'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_criacao_man,
    get_json_object(payload_json, '$.id_proprietario_imo') AS id_proprietario_imo,
    get_json_object(payload_json, '$.id_locatario_imo') AS id_locatario_imo,
    get_json_object(payload_json, '$.id_contrato_con') AS id_contrato_con,
    get_json_object(payload_json, '$.st_descricao_man') AS st_descricao_man,
    get_json_object(payload_json, '$.st_motivo_man') AS st_motivo_man,
    CAST(get_json_object(payload_json, '$.fl_prioridade_man') AS INT) AS fl_prioridade_man,
    CAST(get_json_object(payload_json, '$.fl_situacao_man') AS INT) AS fl_situacao_man,
    CAST(get_json_object(payload_json, '$.fl_solicitante_man') AS INT) AS fl_solicitante_man,
    CAST(get_json_object(payload_json, '$.fl_proprietarionotificado_man') AS INT) AS fl_proprietarionotificado_man,
    CAST(get_json_object(payload_json, '$.fl_desativada_man') AS INT) AS fl_desativada_man,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_previsaoentrega_man'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_previsaoentrega_man'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_previsaoentrega_man,
    CAST(get_json_object(payload_json, '$.fl_viaapp_man') AS INT) AS fl_viaapp_man,
    CAST(get_json_object(payload_json, '$.fl_categoria_man') AS INT) AS fl_categoria_man,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_atualizacao_man'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_atualizacao_man'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_atualizacao_man,
    get_json_object(payload_json, '$.st_identificadorexterno_man') AS st_identificadorexterno_man,
    get_json_object(payload_json, '$.st_linkexterno_man') AS st_linkexterno_man,
    get_json_object(payload_json, '$.st_terceirizada_man') AS st_terceirizada_man,
    CAST(get_json_object(payload_json, '$.fl_motivocancelamento_man') AS INT) AS fl_motivocancelamento_man,
    CAST(get_json_object(payload_json, '$.fl_atualizacaoexterna_man') AS INT) AS fl_atualizacaoexterna_man,
    CAST(get_json_object(payload_json, '$.fl_responsavel_man') AS INT) AS fl_responsavel_man,
    get_json_object(payload_json, '$.id_origem_man') AS id_origem_man,
    get_json_object(payload_json, '$.st_categoria') AS st_categoria,
    get_json_object(payload_json, '$.detalhes_formatado') AS detalhes_formatado,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_horaprevisaoentrega_man'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_horaprevisaoentrega_man'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_horaprevisaoentrega_man,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_solicitacao_man'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_solicitacao_man'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_solicitacao_man,
    CAST(get_json_object(payload_json, '$.fl_status_man') AS INT) AS fl_status_man,
    get_json_object(payload_json, '$.st_observacao_man') AS st_observacao_man,
    get_json_object(payload_json, '$.st_titulo_man') AS st_titulo_man,
    get_json_object(payload_json, '$.sugestao_execucao') AS sugestao_execucao,
    synced_at AS ts_synced
FROM
    maintenance_row
