SELECT
  CONCAT(fde1.sk_rent_flow, '-', fde1.sk_event, '-', fde1.sk_event_type, '-', fde2.sk_event, '-', fde2.sk_event_type) AS sk_cohort_conversion,
  CONCAT(fde1.sk_event_type, '-', fde2.sk_event_type) AS sk_cohort_type,
  fde1.sk_event AS sk_base_event,
  fde1.sk_event_type AS sk_base_event_type,
  fde1.sk_rent_flow, 
  fde1.sk_tenant_prospect,
  fde1.sk_house,
  fde1.sk_house_listing,
  fde1.sk_region,
  fde1.sk_booking,
  fde1.sk_offer,
  fde1.sk_proposal,
  fde1.sk_contract,
  fde1.sk_event_date AS sk_base_event_date,
  IF(fde2.sk_event_date >= fde1.sk_event_date, fde2.sk_event_date, -1) AS sk_conversion_date,
  fde1.country_code,
  IF(fde2.sk_event_date >= fde1.sk_event_date, DATEDIFF(dd2.date, dd1.date), NULL) AS days_to_conversion,
  IF(fde2.sk_event_date >= fde1.sk_event_date, DATEDIFF(dd2.week_start, dd1.week_start)/7, NULL) AS weeks_to_conversion,
  NOW() AS ts_load
FROM
  dw_rent.fact_rent_demand_events AS fde1
JOIN 
  dw_rent.fact_rent_demand_events AS fde2 
    ON fde1.sk_rent_flow = fde2.sk_rent_flow
      AND fde1.sk_event_type < fde2.sk_event_type
      AND (
        (fde1.sk_booking > 0 AND fde1.sk_booking = fde2.sk_booking)
        OR (fde1.sk_offer > 0 AND fde1.sk_offer = fde2.sk_offer)
        OR (fde1.sk_proposal > 0 AND fde1.sk_proposal = fde2.sk_proposal)
    )
JOIN
  dw_public.dim_date AS dd1
    ON fde1.sk_event_date = dd1.sk_date
JOIN
  dw_public.dim_date AS dd2
    ON fde2.sk_event_date = dd2.sk_date