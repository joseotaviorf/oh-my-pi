SELECT
    u.id AS client_id,
    u.name AS client_name,
    u.email AS client_email,
    CASE
        WHEN u.personal_document_type = 'CPF' THEN 'PF'
        WHEN u.personal_document_type = 'CNPJ' THEN 'PJ'
        ELSE 'Indefinido'
    END AS client_type,
    u.cpf AS client_cpf_cnpj,
    u.country_code AS residence_country,
    u.ts_created,
    u.ts_updated
FROM
    datalake_ebdb_user.user u
