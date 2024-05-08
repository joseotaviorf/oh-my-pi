SELECT
    id,
    region_id AS id_region,
    fee,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.TenantServiceFee