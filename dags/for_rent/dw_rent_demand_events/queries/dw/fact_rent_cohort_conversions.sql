SELECT DISTINCT
  BIGINT(CONCAT(fde1.sk_event, 0, fde1.sk_event_type, 0, fde2.sk_event, 0, fde2.sk_event_type)) AS sk_cohort_conversion,
  INT(CONCAT(fde1.sk_event_type, 0, fde2.sk_event_type)) AS sk_cohort_type,
  fde1.sk_event AS sk_base_event,
  fde1.sk_event_type AS sk_base_event_type,
  fde2.sk_event AS sk_conversion_event,
  fde2.sk_event_type AS sk_conversion_event_type,
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
        (fde1.sk_booking > 0 AND fde1.sk_booking = fde2.sk_booking AND fde1.sk_offer = fde2.sk_offer AND fde1.sk_proposal = fde2.sk_proposal)
        OR (fde1.sk_offer > 0 AND fde1.sk_offer = fde2.sk_offer AND fde1.sk_booking = fde2.sk_booking AND fde1.sk_proposal = fde2.sk_proposal)
        OR (fde1.sk_proposal > 0 AND fde1.sk_proposal = fde2.sk_proposal AND fde1.sk_booking = fde2.sk_booking AND fde1.sk_offer = fde2.sk_offer)
    )
JOIN
  dw_public.dim_date AS dd1
    ON fde1.sk_event_date = dd1.sk_date
JOIN
  dw_public.dim_date AS dd2
    ON fde2.sk_event_date = dd2.sk_date