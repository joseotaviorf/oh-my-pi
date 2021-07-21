SELECT
    id,
    imobiliaria_id AS id_real_estate_agency,
    grupo_id AS id_group,
    CAST(suspenso AS BOOLEAN) AS is_suspended,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.usuario