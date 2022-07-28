SELECT 
    id, 
    nome AS origin_contact_name, 
    slug AS origin_contact_slug_name, 
    CAST(criado_em AS TIMESTAMP) AS ts_created, 
    CAST(desativado_em AS TIMESTAMP) AS ts_disabled
FROM 
    datalake_casa_mineira_crm_raw.contato_origem