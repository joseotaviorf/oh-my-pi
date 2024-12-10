SELECT DISTINCT
  sk_buyer_prospect_type,
  bp_type AS buyer_prospect_type,
  CASE 
    WHEN bp_type = 'NBP' THEN 'New Buyer Prospect'
    WHEN bp_type = 'RBP' THEN 'Recovery Buyer Prospect'
  END AS buyer_prospect_type_long,
  NOW() AS ts_load
FROM 
  datalake_buyer_prospect.buyer_prospect_type