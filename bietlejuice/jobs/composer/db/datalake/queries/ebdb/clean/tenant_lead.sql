SELECT
    id,
    atualizadoEm as ts_updated,
    criadoEm as ts_created,
    email,
    nome as name,
    telefonePrincipal as main_phone
FROM
    datalake_ebdb_raw.tenantlead