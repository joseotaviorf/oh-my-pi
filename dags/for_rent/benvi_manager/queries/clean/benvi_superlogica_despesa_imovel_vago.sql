SELECT
    id,
    vendor_natural_key                    AS id_lancamento_imod,
    payload ->> 'id_imovel_imo'           AS id_imovel_imo,
    payload ->> 'id_contrato_con'         AS id_contrato_con,
    synced_at                             AS ts_synced
FROM datalake_benvi_manager_raw.lake_mirror
WHERE resource_code = 'VACANT_PROPERTY_EXPENSE';
