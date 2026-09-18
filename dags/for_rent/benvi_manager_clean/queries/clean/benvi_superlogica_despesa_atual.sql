SELECT
    lake_mirror.id,
    lake_mirror.vendor_natural_key AS id_lancamento_imod,
    get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_imovel_imo') AS id_imovel_imo,
    get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_contrato_con') AS id_contrato_con,
    get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_recebimento_recb') AS id_recebimento_recb,
    get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_repasse_rep') AS id_repasse_rep,
    get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_acordo_aco') AS id_acordo_aco,
    get_json_object(CAST(lake_mirror.payload AS STRING), '$.fl_status_imod') AS fl_status_imod,
    get_json_object(CAST(lake_mirror.payload AS STRING), '$.fl_tipo_imod') AS fl_tipo_imod,
    get_json_object(CAST(lake_mirror.payload AS STRING), '$.fl_repassar_imod') AS fl_repassar_imod,
    get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_descricao_prd') AS st_descricao_prd,
    get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_label_imod') AS st_label_imod,
    CAST(get_json_object(CAST(lake_mirror.payload AS STRING), '$.vl_valor_imod') AS DOUBLE) AS vl_valor_imod,
    TO_DATE(get_json_object(CAST(lake_mirror.payload AS STRING), '$.dt_lancamento_imod')) AS dt_lancamento_imod,
    TO_DATE(get_json_object(CAST(lake_mirror.payload AS STRING), '$.dt_competencia_imod')) AS dt_competencia_imod,
    TO_DATE(get_json_object(CAST(lake_mirror.payload AS STRING), '$.dt_referencia_imod')) AS dt_referencia_imod,
    TO_DATE(get_json_object(CAST(lake_mirror.payload AS STRING), '$.dt_liquidacao_mov')) AS dt_liquidacao_mov,
    lake_mirror.synced_at AS ts_synced
FROM
    datalake_benvi_manager_raw.lake_mirror AS lake_mirror
WHERE
    lake_mirror.resource_code = 'CONTRACT_EXPENSE'
