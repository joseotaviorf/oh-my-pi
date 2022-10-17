SELECT
  id_booking AS sk_tenant_booking_review,
  id_booking AS id_tenant_booking_review,
  review_status,
  visit_not_happened_reason,
  wrong_listing_info, 
  no_offer_intent_reason,
  painting,
  cost_benefit,
  conservation,
  cleaning,
  furniture,
  natural_light,
  indoor_silence,
  agent_performance,
  visit_type,
  comment,
  is_listing_accurate,
  is_offer_intent,
  does_want_same_agent,
  NOW() AS ts_load
FROM
  datalake_booking.booking_review
WHERE
  review_type = 'tenant_visit'