SELECT 
  buyer_id AS id_buyer,
  external_house_id AS id_external_house,
  house_id AS id_house,
  offer_id AS id_offer,
  pre_analysis_id AS id_pre_analysis,
  sales_flow_id AS id_sales_flow,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_risk_and_mortgage_raw.offer_pre_analysis
WHERE
  year = {year}
  AND month = {month}
  AND day = {day}