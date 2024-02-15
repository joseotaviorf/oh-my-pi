select
    id as id_credit_evaluation_proponent,
    credit_evaluation_id as id_credit_evaluation,
    rev,
    revtype as rev_type,
    name,
    cpf,
    occupation_area,
    status,
    revend as rev_end,
    resident,
    income_nature,
    monthly_income
from
    datalake_docx_raw.credit_evaluation_proponent_aud
