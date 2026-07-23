WITH event_type_adjustment AS (
  /** As we have created the event type number as something fixed so people can easily filter it, when creating an event type later,
    we had to assign to it the last number possible.
    In cases that the new event type happens before other event, it might be an issue to assure the right "natural conversion".
    Because of that, we need to create an adjusted event type, so it won't break the logic of the query.
    Real case as example:
      We created the CC (contract created) event later. The CS (contract signed) was already created as event type 9, so CC got event type 10.
      In order to fix the join here, we're creating an adjusted event type for both of them, in order that the adjusted event type of CC is
      smaller than the CS.
  **/
  SELECT
    sk_event,
    sk_event_type,
    CASE
      WHEN sk_event_type = 10 THEN 99 -- Contract Created (event type 10) is a metric that happens before Contract Signed (event type 9)
      WHEN sk_event_type = 9 THEN 100
      ELSE sk_event_type
    END AS sk_event_type_adjusted,
    sk_rent_flow,
    sk_booking,
    sk_offer,
    sk_proposal,
    sk_contract,
    sk_event_date,
    country_code
  FROM
    dw_rent.fact_rent_demand_events
  WHERE
    sk_rent_flow > 0
)
/** Events that weren't converted receives sk_convertion_event and sk_conversion_event_type as 0.
  sk_conversion_date, days_to_conversion and weeks_to_conversion will be -1.
**/
SELECT DISTINCT
  CONCAT(fde1.sk_event, '-', fde1.sk_event_type, '-', COALESCE(fde2.sk_event, 0), '-', COALESCE(fde2.sk_event_type, 0)) AS sk_cohort_conversion,
  INT(CONCAT(fde1.sk_event_type, 0, COALESCE(fde2.sk_event_type, 0))) AS sk_cohort_type,
  fde1.sk_event AS sk_base_event,
  fde1.sk_event_type AS sk_base_event_type,
  COALESCE(fde2.sk_event, 0) AS sk_conversion_event,
  COALESCE(fde2.sk_event_type, 0) AS sk_conversion_event_type,
  fde1.sk_event_date AS sk_base_event_date,
  COALESCE(fde2.sk_event_date, -1) AS sk_conversion_date,
  fde1.country_code,
  IF(fde2.sk_event_date >= fde1.sk_event_date, DATEDIFF(dd2.date, dd1.date), 0) AS days_to_conversion,
  IF(fde2.sk_event_date >= fde1.sk_event_date, DATEDIFF(dd2.week_start, dd1.week_start)/7, 0) AS weeks_to_conversion,
  NOW() AS ts_load
FROM
  event_type_adjustment AS fde1
LEFT JOIN
  event_type_adjustment AS fde2
    ON fde1.sk_rent_flow = fde2.sk_rent_flow
      AND fde1.sk_event_type_adjusted < fde2.sk_event_type_adjusted
      AND (
        (fde1.sk_booking > 0 AND fde1.sk_booking = fde2.sk_booking AND fde1.sk_offer = fde2.sk_offer AND fde1.sk_proposal = fde2.sk_proposal AND fde1.sk_contract = fde2.sk_contract)
        OR (fde1.sk_offer > 0 AND fde1.sk_offer = fde2.sk_offer AND fde1.sk_booking = fde2.sk_booking AND fde1.sk_proposal = fde2.sk_proposal AND fde1.sk_contract = fde2.sk_contract)
        OR (fde1.sk_proposal > 0 AND fde1.sk_proposal = fde2.sk_proposal AND fde1.sk_booking = fde2.sk_booking AND fde1.sk_offer = fde2.sk_offer AND fde1.sk_contract = fde2.sk_contract)
        OR (fde1.sk_contract > 0 AND fde1.sk_contract = fde2.sk_contract AND fde1.sk_booking = fde2.sk_booking AND fde1.sk_offer = fde2.sk_offer AND fde1.sk_proposal = fde2.sk_proposal)
    )
INNER JOIN
  dw_public.dim_date AS dd1
    ON fde1.sk_event_date = dd1.sk_date
LEFT JOIN
  dw_public.dim_date AS dd2
    ON fde2.sk_event_date = dd2.sk_date
