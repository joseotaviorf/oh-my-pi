SELECT
  frf.sk_rent_flow,
  frf.sk_house,
  frf.sk_tenant_prospect,
  frf.ts_first_event,
  drf.first_touchpoint,
  drf.has_offer_flow,
  drf.has_tta_flow,
  drf.has_visit_flow,
  drf.has_direct_offer_flow AS had_flow_direct_offer,
  frf.nbr_direct_offers_submitted,
  frf.nbr_tta_messages,
  frf.nbr_offers_submitted,
  frf.nbr_bookings_created,
  frf.nbr_visits_completed,
  frf.nbr_visits_performed,
  frf.ts_first_direct_offer_submitted,
  frf.ts_first_offer_submitted,
  frf.ts_first_booking_created,
  frf.ts_first_visit_completed,
  frf.ts_first_visit_performed,
  CASE
    WHEN NOT frf.ts_first_direct_offer_submitted IS NULL
    AND drf.has_visit_flow = FALSE
    AND drf.has_tta_flow = FALSE
    THEN 'DIRECT'
    WHEN drf.has_tta_flow = TRUE AND drf.has_visit_flow = FALSE
    THEN 'TTA'
    WHEN drf.has_visit_flow = TRUE
    THEN 'VISIT'
    ELSE 'UNKNOWN'
  END AS funnel_flow,
  CASE
    WHEN NOT frf.ts_first_direct_offer_submitted IS NULL
    AND drf.has_visit_flow = FALSE
    AND drf.has_tta_flow = FALSE
    THEN '(1) ONLY DIRECT OFFER'
    WHEN has_visit_flow = FALSE AND ts_first_direct_offer_submitted IS NULL AND has_tta_flow = TRUE
    THEN '(2) ONLY TALK TO AGENT'
    WHEN has_visit_flow = TRUE AND ts_first_direct_offer_submitted IS NULL AND has_tta_flow = FALSE
    THEN '(3) ONLY VISIT'
    WHEN has_visit_flow = FALSE
    AND NOT ts_first_direct_offer_submitted IS NULL
    AND has_tta_flow = TRUE
    THEN '(1) DIRECT OFFER + (2) TALK TO AGENT'
    WHEN has_visit_flow = TRUE
    AND NOT ts_first_direct_offer_submitted IS NULL
    AND has_tta_flow = FALSE
    THEN '(1) DIRECT OFFER + (3) VISIT'
    WHEN has_visit_flow = TRUE AND ts_first_direct_offer_submitted IS NULL AND has_tta_flow = TRUE
    THEN '(2) TALK TO AGENT + (3) VISIT'
    WHEN has_visit_flow = TRUE
    AND NOT ts_first_direct_offer_submitted IS NULL
    AND has_tta_flow = TRUE
    THEN '(1) DO + (2) TTA + (3) VISIT'
    WHEN has_visit_flow = TRUE AND ts_first_direct_offer_submitted IS NULL AND has_tta_flow = FALSE
    THEN 'NO ONE'
    ELSE 'UNK'
  END AS flow_type
FROM dw_rent.fact_rent_flows AS frf
INNER JOIN dw_rent.dim_rent_flow_type AS drf
  ON frf.sk_rent_flow_type = drf.sk_rent_flow_type