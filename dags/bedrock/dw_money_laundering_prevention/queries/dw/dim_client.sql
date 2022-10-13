SELECT
    client_id AS sk_client,
    client_name,
    client_email,
    client_type,
    client_cpf_cnpj,
    residence_country,
    occupation_area,
    income_nature,
    monthly_income,
    ts_credit_evaluation_created,
    ts_credit_evaluation_updated,
    ts_user_created,
    ts_user_updated
FROM
    datalake_money_laundering_prevention.client
