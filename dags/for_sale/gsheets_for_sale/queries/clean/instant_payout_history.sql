SELECT 
  sk_house_listing
  id_house,
  planning_conversion,
  planning_cluster,
  listing_category_start,
  ticket_range,
  with_frontdoor AS is_with_frontdoor,
  occupied AS is_occupied,
  easy_entry AS is_easy_entry,
  hybrid_pub AS is_hybrid_pub,
  is_exclusive, 
  Group AS group,
  NOW() AS ts_load
FROM 
  datalake_gsheets_raw.instant_payout_history