SELECT
    id,
    imovel_id AS id_house,
    arquivo AS image_file,
    url_original AS original_url,
    url_original_hash AS original_url_hash,
    CAST(largura AS INT) AS width,
    CAST(altura AS INT) AS height,
    CAST(ordem AS INT) AS image_order,
    CAST(criado_em AS TIMESTAMP) AS ts_created,
    CAST(deletado_em AS TIMESTAMP) AS ts_deleted
FROM
    datalake_casa_mineira_portal_raw.imagem