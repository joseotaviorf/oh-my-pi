SELECT
    id AS id_image,
    imovel_id AS id_house,
    rev,
    revtype AS rev_type,
    legenda AS subtitle,
    nome AS name,
    ordem AS image_order,
    principal AS is_main,
    imageVariants_MOD AS mod_image_variants
FROM
    datalake_ebdb_raw.imagem_aud
