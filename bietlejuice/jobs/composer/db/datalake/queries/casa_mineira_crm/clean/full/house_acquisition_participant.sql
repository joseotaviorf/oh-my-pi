SELECT 
    id,
    imovel_id AS id_house, 
    usuario_id AS id_user, 
    usuario_grupo_id AS id_user_group, 
    criado_por AS created_by, 
    removido_por AS removed_by, 
    CAST(criado_em AS TIMESTAMP) AS ts_created, 
    CAST(deletado_em AS TIMESTAMP) AS ts_deleted

FROM 
    datalake_casa_mineira_crm_raw.imovel_captacao_participante