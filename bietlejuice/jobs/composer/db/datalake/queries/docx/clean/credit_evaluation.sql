select
    id,
    proposal_id as id_proposal,
    house_id as id_house,
    user_id as id_user,
    reason,
    result,
    status,
    early_result,
    created_at as ts_created,
    updated_at as ts_updated
from
    datalake_docx_raw.credit_evaluation