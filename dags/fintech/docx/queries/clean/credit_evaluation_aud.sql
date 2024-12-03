select
    id as id_credit_evaluation,
    proposal_id as id_proposal,
    house_id as id_house,
    user_id as id_user,
    rev,
    revtype as rev_type,
    status,
    result,
    reason,
    early_result,
    revend as rev_end,
    user_id_mod as mod_id_user,
    status_mod as mod_status,
    result_mod as mod_result,
    reason_mod as mod_reason,
    early_result_mod as mod_early_result
from
    datalake_docx_raw.credit_evaluation_aud
