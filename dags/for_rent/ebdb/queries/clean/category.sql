SELECT
    id AS id_category,
    name AS category_name,
    version,
    active AS is_active,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.category