SELECT
  id AS id_screening_result,
  end_transaction_id AS id_end_transaction,
  transaction_id AS id_transaction,
  proposal_id AS id_proposal,
  liquidity,
  operation_type,
  risk_category,
  score,
  proposal_id_mod AS mod_id_proposal,
  liquidity_mod AS mod_liquidity,
  risk_category_mod AS mod_risk_category,
  score_mod AS mod_score
FROM 
  datalake_sorting_hat_raw.screeningresult_version