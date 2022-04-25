SELECT
    id,
    state_id AS id_state,
    regiaoPai_id AS id_parent_region,
    nome AS name,
    slug,
    nivel AS level,
    lat,
    lng,
    criadaEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.regiao