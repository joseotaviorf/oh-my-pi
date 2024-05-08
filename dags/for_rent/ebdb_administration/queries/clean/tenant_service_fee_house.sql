SELECT
    id,
    house_id AS id_house,
    fee,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.TenantServiceFeeHouse