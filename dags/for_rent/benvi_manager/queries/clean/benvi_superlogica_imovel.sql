SELECT
    id,
    vendor_natural_key                    AS id_imovel_imo,
    payload ->> 'st_identificador_imo'    AS identificador_imo,
    payload ->> 'st_endereco_imo'         AS endereco_imo,
    payload ->> 'st_cidade_imo'           AS cidade_imo,
    payload ->> 'st_estado_imo'           AS estado_imo,
    synced_at                             AS ts_synced
FROM datalake_benvi_manager_raw.lake_mirror
WHERE resource_code = 'PROPERTY';
