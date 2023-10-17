SELECT DISTINCT
    COALESCE(id_client,-1)  AS sk_client,
    client_cpf,
    client_name             AS client_financing_name,
    client_email,
	client_cellphone,
	client_phone,
    NOW()                   AS ts_load
FROM
    datalake_atta_clean.client_info
