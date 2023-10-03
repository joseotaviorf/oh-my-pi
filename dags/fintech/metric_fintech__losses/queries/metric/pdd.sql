SELECT 
  pd_range_rule_e, 
  status, 
  contracts, 
  wallet, 
  pdd, 
  dt_closing as ts_closing,
  YEAR(dt_closing) AS year,
  MONTH(dt_closing) AS month,
  DAY(dt_closing) AS day,
  NOW() AS ts_load
FROM
  datalake_losses_daily.pdd