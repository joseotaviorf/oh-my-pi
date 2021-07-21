SELECT
    id,
    bairro_id AS id_neighborhood,
    nome AS neighborhood,
    correios AS mail,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.bairro_alternativo