SELECT
    id,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created,
    mensal AS monthly_rate,
    acumulado AS accumulated_rate,
    mes AS dt_index_month,
    extraidoDe AS extracted_from,
    type AS price_index_type,
    autor AS author
FROM
    datalake_ebdb_raw.igpm
