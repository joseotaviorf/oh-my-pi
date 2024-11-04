SELECT
    id,
    credit_evaluation_id AS id_credit_evaluation,
    reference_id AS id_reference,
    name,
    cpf,
    occupation_area,
    status,
    resident,
    proponent_type,
    income_nature,
    monthly_income,
    score,
    phone,
    identity_number,
    reference_type,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_docx_raw.credit_evaluation_proponent
