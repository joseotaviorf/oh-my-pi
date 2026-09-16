SELECT
    id,
    vendor_natural_key AS id_contrato_con,
    get_json_object(CAST(payload AS STRING), '$.codigo_contrato') AS codigo_contrato,
    get_json_object(CAST(payload AS STRING), '$.id_imovel_imo') AS id_imovel_imo,
    CAST(get_json_object(CAST(payload AS STRING), '$.fl_ativo_con') AS INT) AS fl_ativo,
    TO_DATE(get_json_object(CAST(payload AS STRING), '$.dt_rescisao_con')) AS dt_rescisao,
    synced_at AS ts_synced
FROM
    datalake_benvi_manager_raw.lake_mirror
WHERE
    resource_code = 'CONTRACT'
