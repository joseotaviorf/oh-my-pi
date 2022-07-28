SELECT
    id,
    bairro_id AS id_neighborhood,
    imobiliaria_id AS id_real_estate_agency,
    finalidade AS goal,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.bairro_exclusivo