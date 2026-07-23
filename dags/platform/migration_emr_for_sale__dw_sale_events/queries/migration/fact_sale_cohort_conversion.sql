SELECT
  sk_sale_cohort_conversion,
  sk_base_date,
  sk_conversion_date,
  sk_cohort_type,
  sk_booking,
  sk_offer,
  sk_house,
  sk_region,
  sk_buyer,
  sk_seller,
  sk_agent,
  sk_agent_work_contract,
  sk_business_unit,
  sk_company_supply,
  sk_company_demand,
  sk_broker_supply,
  sk_broker_demand,
  sk_secretariat_booking_creator,
  sk_secretariat_on_event,
  sk_last_secretariat,
  days_to_conversion,
  week_number,
  year,
  month,
  day,
  ts_base_event,
  ts_conversion_event,
  ts_load
FROM (
  SELECT
    fee_1.sk_sale_demand_event || '-' || fee_2.sk_event_type AS sk_sale_cohort_conversion,
    fee_1.sk_event_date AS sk_base_date,
    fee_2.sk_event_date AS sk_conversion_date,
    (
      fee_1.sk_event_type || '-' || fee_2.sk_event_type || '-' || CAST(GREATEST(LEAST(DATEDIFF(TO_DATE(dd_2.week_start), TO_DATE(dd_1.week_start)) / 7, 20), 0) AS INT) || '-' || GREATEST(LEAST(DATEDIFF(TO_DATE(dd_2.date), TO_DATE(dd_1.date)), 140), 0)
    ) AS sk_cohort_type,
    fee_1.sk_booking,
    fee_1.sk_offer,
    fee_1.sk_house,
    fee_1.sk_region,
    fee_1.sk_buyer,
    fee_1.sk_seller,
    fee_1.sk_agent,
    fee_1.sk_agent_work_contract,
    fee_1.sk_business_unit,
    fee_1.sk_company_supply,
    fee_1.sk_company_demand,
    fee_1.sk_broker_supply,
    fee_1.sk_broker_demand,
    fee_1.sk_secretariat_booking_creator,
    fee_1.sk_secretariat_on_event,
    fee_1.sk_last_secretariat,
    DATEDIFF(TO_DATE(dd_2.date), TO_DATE(dd_1.date)) AS days_to_conversion,
    CAST((
      DATEDIFF(TO_DATE(dd_2.week_start), TO_DATE(dd_1.week_start)) / 7
    ) AS INT) AS week_number,
    fee_1.year,
    fee_1.month,
    fee_1.day,
    fee_1.ts_event AS ts_base_event,
    fee_2.ts_event AS ts_conversion_event,
    NOW() AS ts_load,
    ROW_NUMBER() OVER (PARTITION BY fee_1.sk_sale_demand_event, fee_2.sk_event_type ORDER BY fee_2.sk_event_date) AS _w,
    fee_1.sk_sale_demand_event,
    fee_2.sk_event_type,
    fee_2.sk_event_date
  FROM dw_sale.fact_sale_demand_event AS fee_1
  JOIN dw_public.dim_date AS dd_1
    ON fee_1.sk_event_date = dd_1.sk_date
  JOIN dw_sale.fact_sale_demand_event AS fee_2
    ON (
      (
        CAST(fee_1.sk_offer AS STRING) = '-1' AND fee_1.sk_booking = fee_2.sk_booking
      ) /* If the first event is booking related, we use booking as key */
      OR (
        CAST(fee_1.sk_offer AS STRING) <> '-1' AND fee_1.sk_offer = fee_2.sk_offer
      ) /* Otherwise, use offer as key */
    )
    AND fee_1.sk_event_type <> fee_2.sk_event_type
  JOIN dw_public.dim_date AS dd_2
    ON fee_2.sk_event_date = dd_2.sk_date
) AS _t
WHERE
  _w = 1 /* Only interested in the first conversion */