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
    cep.occupation_area,
    cep.income_nature,
    cep.monthly_income,
    cep.ts_created AS ts_credit_evaluation_created,
    cep.ts_updated AS ts_credit_evaluation_updated,
    u.ts_created AS ts_user_created,
    u.ts_updated AS ts_user_updated
FROM
    datalake_ebdb_user.user u
INNER JOIN datalake_docx_clean.credit_evaluation ce
    ON ce.id_user = u.id
INNER JOIN datalake_docx_clean.credit_evaluation_proponent cep
    ON cep.id_credit_evaluation = ce.id
