select
    id,
    screening_result_id as id_screening_result,
    score,
    risk_category,
    liquidity,
    proposal_id as id_proposal,
    timestamp(versioned_at) as ts_versioned
from datalake_sorting_hat_raw.screeningresultversion