SELECT
    id,
    atualizadoEm as ts_updated,
    criadoEm AS ts_created,
    codigo AS code,
    nome AS name,
    nomeFebraban AS febraban_name,
    featuredRank AS featured_rank
FROM
    datalake_ebdb_raw.`banco`