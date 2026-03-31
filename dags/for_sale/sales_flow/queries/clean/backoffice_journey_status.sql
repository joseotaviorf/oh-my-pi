SELECT
  id,
  sales_flow_id AS id_sales_flow,
  is_buyer_onboarded,
  is_seller_onboarded,
  buyer_onboarding_concluded_at AS ts_buyer_onboarding_concluded,
  seller_onboarding_concluded_at AS ts_seller_onboarding_concluded,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_sales_flow_raw.backoffice_journey_status
