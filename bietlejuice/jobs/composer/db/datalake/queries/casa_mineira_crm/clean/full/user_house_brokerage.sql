SELECT
    id,
    imovel_id AS id_house,
    usuario_id AS id_user,
    criado_por AS created_by,
    removido_por AS removed_by,
    CAST(comissao AS FLOAT) AS brokerage_fee,
    CAST(principal AS BOOLEAN) AS is_principal,
    CAST(criado_em AS TIMESTAMP) AS ts_created,
    CAST(deletado_em AS TIMESTAMP) AS ts_deleted
FROM
    datalake_casa_mineira_crm_raw.usuario_comissao_imovel
