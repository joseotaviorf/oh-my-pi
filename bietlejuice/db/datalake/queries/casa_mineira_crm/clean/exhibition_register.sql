SELECT
    id,
    imovel_id AS id_house,
    usuario_id AS id_user,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_crm_raw.registro_exibicao