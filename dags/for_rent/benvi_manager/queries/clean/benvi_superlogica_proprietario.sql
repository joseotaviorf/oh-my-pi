SELECT
    id,
    vendor_natural_key                    AS id_pessoa_pes,
    payload ->> 'st_nome_pes'             AS nome_pes,
    synced_at                             AS ts_synced
FROM datalake_benvi_manager_raw.lake_mirror
WHERE resource_code = 'OWNER';
