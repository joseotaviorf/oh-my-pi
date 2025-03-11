SELECT
    id,
    cidadeId as id_city,
    macroId as id_macro,
    nivel as level,
    nome as name,
    macroNome as macro_name,
    cidadeNome as city_name,
    criadaEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.mapregiao