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
    codigo_importacao,
    year,
    month,
    day
FROM
    datalake_union_raw.fotos
WHERE
    year <> 1900
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY codigo ORDER BY paratime DESC) = 1