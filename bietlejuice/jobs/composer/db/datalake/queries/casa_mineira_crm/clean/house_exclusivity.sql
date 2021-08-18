SELECT
    id,
    imovel_id AS id_house,
    usuario_cancelamento_id AS id_user_cancellation,
    usuario_exclusao_id AS id_user_exclusion,
    criado_por AS created_by,
    CAST(inicio_em AS DATE) AS dt_begun,
    CAST(cancelado_em AS DATE) AS dt_cancelled,
    CAST(deletado_em AS DATE) AS dt_deleted,
    CAST(termino_em AS DATE) AS dt_finished
FROM 
    datalake_casa_mineira_crm_raw.imovel_exclusividade