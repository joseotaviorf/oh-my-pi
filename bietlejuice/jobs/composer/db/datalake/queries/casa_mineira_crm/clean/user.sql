SELECT 
    id, 
    grupo_id AS id_group, 
    gerente_id AS id_manager,
    unidade_id AS id_unit,  
    criado_por AS created_by,
    nivel AS level, 
    nome AS user_name,
    nome_completo AS user_full_name,
    email AS email,
    telefone AS phone,
    CONCAT(SUBSTR(cpf,1,3),'.',SUBSTR(cpf,4,3),'.',SUBSTR(cpf,7,3),'-',SUBSTR(cpf,10,2)) AS cpf,
    percentual_comissao AS percentage_comission,
    CAST(interno AS BOOLEAN) AS is_intern, 
    CAST(suspenso AS BOOLEAN) AS is_suspended, 
    CAST(contrato_corretor_data AS DATE) AS dt_agent_contract, 
    CAST(entrou_em AS TIMESTAMP) AS ts_started, 
    CAST(criado_em AS TIMESTAMP) AS ts_created,
    CAST(atualizado_em AS TIMESTAMP) AS ts_updated, 
    CAST(deletado_em AS TIMESTAMP) AS ts_deleted
FROM 
    datalake_casa_mineira_crm_raw.usuario 