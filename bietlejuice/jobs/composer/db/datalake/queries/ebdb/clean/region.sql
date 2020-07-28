SELECT
    id,
    nome AS name,
    nivel AS level,
    regiaoPai_id as id_parent_region,
    criadaEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.regiao