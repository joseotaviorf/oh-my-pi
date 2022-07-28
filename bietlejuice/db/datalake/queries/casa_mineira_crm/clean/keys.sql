SELECT 
    id,
    nome AS key_name,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM 
    datalake_casa_mineira_crm_raw.chave