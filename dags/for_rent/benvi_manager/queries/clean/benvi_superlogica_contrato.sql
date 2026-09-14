SELECT
    id,
    vendor_natural_key                    AS id_contrato_con,
    payload ->> 'codigo_contrato'         AS codigo_contrato,
    payload ->> 'id_imovel_imo'           AS id_imovel_imo,
    CAST(payload ->> 'fl_ativo_con' AS INT) AS fl_ativo,
    CAST(payload ->> 'dt_rescisao_con' AS DATE) AS dt_rescisao,
    synced_at                             AS ts_synced
FROM datalake_benvi_manager_raw.lake_mirror
WHERE resource_code = 'CONTRACT';
