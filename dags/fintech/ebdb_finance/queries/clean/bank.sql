SELECT
    id,
    country_id AS id_country,
    nome AS name,
    codigo AS code,
    nomeFebraban AS febraban_name,
    featuredRank AS featured_rank,
    atualizadoEm as ts_updated,
    criadoEm AS ts_created
FROM
    datalake_ebdb_raw.`banco`