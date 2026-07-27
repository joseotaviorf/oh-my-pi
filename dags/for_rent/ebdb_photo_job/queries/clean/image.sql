SELECT
    id AS id_image,
    imovel_id AS id_house,
    development_id AS id_development,
    nome AS name,
    principal AS is_principal,
    legenda AS subtitle,
    ordem AS sequence,
    has_original,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created
FROM
    datalake_ebdb_raw.imagem