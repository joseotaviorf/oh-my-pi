SELECT
    id,
    vendor_natural_key                    AS id_manutencao_man,
    payload ->> 'id_imovel_imo'           AS id_imovel_imo,
    synced_at                             AS ts_synced
FROM datalake_benvi_manager_raw.lake_mirror
WHERE resource_code = 'MAINTENANCE';
