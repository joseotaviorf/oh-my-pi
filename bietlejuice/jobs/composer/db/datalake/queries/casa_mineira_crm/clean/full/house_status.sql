SELECT 
    id,
    nome AS house_status_name, 
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_crm_raw.status