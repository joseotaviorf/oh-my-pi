SELECT 
  id_offer,
  CAST(id_client_cm AS BIGINT) AS id_client_cm,
  CAST(id_user_5a AS BIGINT) AS id_user_5a,
  CAST(id_house_cm AS BIGINT) AS id_house_cm,
  CAST(id_house_5a AS BIGINT) AS id_house_5a,
  offer_flow,
  status,
  agent,
  executive,
  CAST(sale_price_agreed AS FLOAT) AS sale_price_agreed,
  CAST(dt_offer_submitted AS DATE) AS dt_offer_submitted,
  CAST(dt_offer_accepted_dismissed AS DATE) AS dt_offer_accepted_dismissed,
  CAST(dt_sale_agreement_signed AS DATE) AS dt_sale_agreement_signed
FROM 
  datalake_gsheets_raw.offers_hub_central
