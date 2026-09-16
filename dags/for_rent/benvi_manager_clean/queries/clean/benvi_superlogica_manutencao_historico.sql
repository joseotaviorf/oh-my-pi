SELECT
    id,
    vendor_natural_key AS vendor_natural_key,
    split(vendor_natural_key, '\\\\|')[0] AS id_manutencao_man,
    split(vendor_natural_key, '\\\\|')[1] AS id_historico_mhis,
    synced_at AS ts_synced
FROM
    datalake_benvi_manager_raw.lake_mirror
WHERE
    resource_code = 'MAINTENANCE_HISTORY'
