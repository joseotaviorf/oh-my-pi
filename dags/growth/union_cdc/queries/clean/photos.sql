SELECT
    codigo AS id_photo,
    fkEmpresa AS id_company,
    fkimovel AS id_house,
    referencia_imovel,
    descricao,
    arqfoto,
    fotosel,
    ordem,
    minia,
    tipo,
    flagdesk,
    paratime AS dt_paratime,
    codigo_importacao
FROM
    datalake_union_cdc_raw.fotos
