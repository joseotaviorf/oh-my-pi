SELECT
    id,
    vendor_natural_key AS id_pessoa_pes,
    get_json_object(CAST(payload AS STRING), '$.id_sacado_sac') AS id_sacado_sac,
    get_json_object(CAST(payload AS STRING), '$.st_nome_pes') AS nome_pes,
    synced_at AS ts_synced
FROM
    datalake_benvi_manager_raw.lake_mirror
WHERE
    resource_code = 'TENANT'
