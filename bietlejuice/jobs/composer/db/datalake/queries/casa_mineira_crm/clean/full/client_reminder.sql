SELECT
    id, 
    cliente_id AS id_client, 
    criado_por AS created_by, 
    CAST(prioridade AS BOOLEAN) AS is_priority,
    CAST(lembrete_em AS TIMESTAMP) AS ts_reminded,
    CAST(notificado_em AS TIMESTAMP) AS ts_notified, 
    CAST(concluido_em AS TIMESTAMP) AS ts_completed,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM    
    datalake_casa_mineira_crm_raw.cliente_lembrete