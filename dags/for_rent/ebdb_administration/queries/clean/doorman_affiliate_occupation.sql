SELECT
    id,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created,
    name,
    rank,
    active AS is_active
FROM
    datalake_ebdb_raw.`DoormanAffiliateOccupation`