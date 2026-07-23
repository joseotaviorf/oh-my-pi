SELECT 
  id_house,
  is_listing_accurate,
  TRUE AS has_3p_access_control
FROM
  datalake_listing_accuracy_review.listing_accuracy_history
QUALIFY 
  ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY dt_change DESC) = 1