SELECT
    id,
    imovel_id AS id_house,
    campo AS modified_column,
    valor AS modified_value,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.imovel_historico