SELECT
    id,
    bairro_id AS id_neighborhood,
    imobiliaria_id AS id_real_estate_agency,
    tipo_id AS id_type,
    uid,
    ip,
    logradouro AS address,
    email,
    finalidade AS goal,
    CAST(enviado_em AS TIMESTAMP) AS ts_sent,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.captacao