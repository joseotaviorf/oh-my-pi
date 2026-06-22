select
    id,
    score,
    calibrated_score,
    risk_category,
    liquidity,
    proposal_id as id_proposal,
    risk_category_canon
from datalake_sorting_hat_raw.screeningresult
