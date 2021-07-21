SELECT
    id,
    imobiliaria_id AS id_real_estate_agency,
    criado_por AS created_by,
    CAST(valor AS FLOAT) AS budget_value,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.imobiliaria_verba