SELECT 
    id,
    cliente_id AS id_client,
    criado_por AS created_by, 
    tipo AS attendance_type,
    CAST(criado_em AS TIMESTAMP) AS ts_created, 
    CAST(atendimento_em AS TIMESTAMP) AS ts_attended
FROM 
    datalake_casa_mineira_crm_raw.cliente_atendimento