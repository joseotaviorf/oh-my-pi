SELECT
    id AS id_credit_analysis,
    created_at AS ts_created,
    updated_at AS ts_updated,
    level,
    type,
    should_interview,
    result,
    rejection_motive,
    comment,
    analyst_name,
    analyst_main_id AS id_analyst,
    proposal_id AS id_proposal
FROM
    datalake_sorting_hat_raw.`creditanalysis`