select
    id,
    credit_evaluation_id as id_credit_evaluation,
    name,
    cpf,
    occupation_area,
    status,
    resident,
    income_nature,
    monthly_income,
    created_at as ts_created,
    updated_at as ts_updated
from 
    datalake_docx_raw.credit_evaluation_proponent