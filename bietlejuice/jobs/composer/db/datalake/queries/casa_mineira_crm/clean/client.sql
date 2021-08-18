SELECT 
    id, 
    criado_por AS created_by,
    email,
    telefone AS phone_number,
    telefone_secundario AS second_phone_number,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM 
    datalake_casa_mineira_crm_raw.cliente