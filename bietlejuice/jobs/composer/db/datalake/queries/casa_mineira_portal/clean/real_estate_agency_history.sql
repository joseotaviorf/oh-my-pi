SELECT
    id,
    imobiliaria_id AS id_real_estate_agency,
    usuario_id AS id_user,
    campo AS modified_column,
    valor AS modified_value,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.imobiliaria_historico