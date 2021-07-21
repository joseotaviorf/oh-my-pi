SELECT
    imovel_id AS id_house,
    ponto_interesse_id AS id_interest_point,
    CAST(distancia AS INT) AS distance,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.imovel_ponto_interesse