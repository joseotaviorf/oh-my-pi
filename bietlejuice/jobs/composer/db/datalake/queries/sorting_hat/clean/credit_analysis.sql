SELECT
    id AS id_credit_analysis,
    analyst_main_id AS id_analyst,
    proposal_id AS id_proposal,
    variant_id AS id_variant,    
    level,
    type,
    result,
    reason,
    comment,
    analyst_name,    
    category,
    automatic_decision_reason,
    bypass,
    should_interview AS is_a_potential_interview,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_sorting_hat_raw.`creditanalysis`
