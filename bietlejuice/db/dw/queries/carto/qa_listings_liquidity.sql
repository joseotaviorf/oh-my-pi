SELECT
  rf.sk_house_listing,
  -- rf.days_visit_to_offer_submitted,
  rf.days_house_listing_to_contract_signed
FROM public.fact_listing_rent_flows rf
WHERE rf.days_house_listing_to_contract_signed > 0
