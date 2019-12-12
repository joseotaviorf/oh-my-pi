SELECT
    id,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created,
    name,
    rank,
    active as is_active
FROM
    datalake_ebdb_raw.`DoormanAffiliateOccupation`