SELECT
    id AS id_image,
    nome AS name,
    principal AS is_principal,
    imovel_id AS id_house,
    legenda AS subtitle,
    ordem AS sequence,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created
FROM
    datalake_ebdb_raw.imagem
