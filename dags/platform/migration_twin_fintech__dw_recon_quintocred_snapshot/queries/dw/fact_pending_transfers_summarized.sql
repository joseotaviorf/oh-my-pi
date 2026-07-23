SELECT
  sk_propose,
  activator_amount,
  paid_amount,
  open_amount,
  dt_contract_started,
  NOW() AS ts_snapshot,
  YEAR(CURRENT_DATE()) AS year,
  MONTH(CURRENT_DATE()) AS month,
  DAY(CURRENT_DATE()) AS day
FROM
  dw_recon_quintocred.fact_pending_transfers_summarized
