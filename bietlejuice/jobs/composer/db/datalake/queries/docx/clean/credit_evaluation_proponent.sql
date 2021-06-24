SELECT
    id,
    credit_evaluation_id AS id_credit_evaluation,
    name,
    cpf,
    occupation_area,
    status,
    resident,
    proponent_type,
    income_nature,
    monthly_income,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_docx_raw.credit_evaluation_proponent