SELECT
    id,
    vendor_natural_key AS id_lancamento_imod,
    get_json_object(CAST(payload AS STRING), '$.id_imovel_imo') AS id_imovel_imo,
    get_json_object(CAST(payload AS STRING), '$.id_contrato_con') AS id_contrato_con,
    synced_at AS ts_synced
FROM
    datalake_benvi_manager_raw.lake_mirror
WHERE
    resource_code = 'VACANT_PROPERTY_EXPENSE'
