SELECT
    nome AS name,
    email,
    cpf,
    pis,
    nome_mae AS mothers_name,
    nome_pai AS fathers_name,
    estado_civil AS marital_status
FROM
    datalake_gsheets_raw.autonomous_agent_payment_data_form_origin