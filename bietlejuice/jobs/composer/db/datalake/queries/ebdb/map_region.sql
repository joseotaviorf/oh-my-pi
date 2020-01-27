SELECT
    id,
    criadaEm AS ts_created,
    atualizadoEm AS ts_updated,
    nivel as level,
    nome as name,
    macroId as id_macro,
    macroNome as macro_name,
    cidadeId as id_city,
    cidadeNome as city_name
FROM
    datalake_ebdb_raw.mapregiao