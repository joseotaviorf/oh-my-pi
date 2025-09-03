-- Query to extract formatted house data from EBDB for portfolio reprocessing
SELECT DISTINCT
    imovel.id AS property_id,
    imovel.dataCriacao AS created_at,
    'house' AS event_type,
    TO_JSON(NAMED_STRUCT(
        'zipcode', imovel.cep,
        'state', estado.nome,
        'city', imovel.cidade,
        'neighbourhood', imovel.bairro,
        'street', imovel.endereco,
        'number', imovel.numero,
        'complement', imovel.complemento,
        'region', regiao.nome,
        'lat', imovel.lat,
        'lng', imovel.lng,
        'regionSlug', regiao.slug
    )) AS address,
    TO_JSON(NAMED_STRUCT(
        'ownerId', person.id,
        'personUUId', person.uuid_person,
        'name', person.person_name,
        'phoneNumber', contact_info.contact_info
    )) AS owner,
    TO_JSON(NAMED_STRUCT(
        'area', imovel.areaTotal,
        'iptu', imovel.iptu,
        'forRent', imovel.forRent,
        'forSale', imovel.forSale,
        'rentValue', imovel.aluguel,
        'saleValue', imovel.salePrice,
        'condominium', imovel.condominio,
        'numberRooms', imovel.numeroQuartos,
        'numberSuites', imovel.numeroSuites,
        'numberBathrooms', imovel.numeroBanheiros,
        'houseType', imovel.tipo
    )) AS property_info
FROM
    datalake_ebdb_raw.imovel AS imovel
LEFT JOIN
    datalake_ebdb_raw.estado AS estado
        ON imovel.estado_id = estado.id
LEFT JOIN
    datalake_ebdb_raw.regiao AS regiao
        ON imovel.regiao_id = regiao.id
LEFT JOIN
    datalake_person_clean.person AS person
        ON imovel.usuario_id = person.id
LEFT JOIN
    datalake_person_clean.contact_info AS contact_info
        ON person.id = contact_info.id_person
WHERE
    imovel.id IS NOT NULL
    AND (
        imovel.endereco IS NOT NULL
        OR (imovel.lat IS NOT NULL AND imovel.lng IS NOT NULL)
    )