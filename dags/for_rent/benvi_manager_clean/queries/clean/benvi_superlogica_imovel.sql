SELECT
    id,
    vendor_natural_key AS id_imovel_imo,
    get_json_object(CAST(payload AS STRING), '$.st_identificador_imo') AS identificador_imo,
    get_json_object(CAST(payload AS STRING), '$.st_endereco_imo') AS endereco_imo,
    get_json_object(CAST(payload AS STRING), '$.st_cidade_imo') AS cidade_imo,
    get_json_object(CAST(payload AS STRING), '$.st_estado_imo') AS estado_imo,
    synced_at AS ts_synced
FROM
    datalake_benvi_manager_raw.lake_mirror
WHERE
    resource_code = 'PROPERTY'
