WITH sold_or_rented AS (
  SELECT
    fc.sk_house
  FROM dw_sale.dim_sale_agreement AS sa
  LEFT JOIN dw_sale.fact_offers AS fc
    ON sa.sk_offer = fc.sk_offer
  WHERE
    sa.is_ccv_canceled = FALSE
  UNION
  SELECT
    sk_house
  FROM dw_sale.dim_listing
  WHERE
    has_active_rental_contract = TRUE
), report AS (
  SELECT
    fc.sk_offer,
    fc.sk_house,
    sdl.status AS status_imovel,
    dof.partner_3p_supply,
    dof.partner_3p_demand,
    dof.is_3p_supply,
    dof.is_3p_demand,
    TO_TIMESTAMP(CAST(NULLIF(fl.sk_last_depublication_date, -1) AS STRING), 'yyyyMMdd') AS last_depublication_date,
    TO_TIMESTAMP(CAST(NULLIF(fc.sk_offer_submitted_date, -1) AS STRING), 'yyyyMMdd') AS offer_submitted_date,
    TO_TIMESTAMP(CAST(NULLIF(fc.sk_offer_accepted_date, -1) AS STRING), 'yyyyMMdd') AS offer_accepted_date,
    TO_TIMESTAMP(CAST(NULLIF(fc.sk_offer_dismissed_date, -1) AS STRING), 'yyyyMMdd') AS offer_dismissed_date,
    TO_TIMESTAMP(CAST(NULLIF(fc.sk_sale_agreement_signed_date, -1) AS STRING), 'yyyyMMdd') AS sale_agreement_signed_date,
    CASE
      WHEN NOT (
        TO_TIMESTAMP(CAST(NULLIF(fc.sk_offer_submitted_date, -1) AS STRING), 'yyyyMMdd')
      ) IS NULL
      THEN 1
      ELSE 0
    END AS OS,
    CASE
      WHEN NOT (
        TO_TIMESTAMP(CAST(NULLIF(fc.sk_offer_accepted_date, -1) AS STRING), 'yyyyMMdd')
      ) IS NULL
      THEN 1
      ELSE 0
    END AS OA,
    CASE
      WHEN NOT (
        TO_TIMESTAMP(CAST(NULLIF(fc.sk_offer_dismissed_date, -1) AS STRING), 'yyyyMMdd')
      ) IS NULL
      THEN 1
      ELSE 0
    END AS OD,
    CASE
      WHEN NOT (
        TO_TIMESTAMP(CAST(NULLIF(fc.sk_sale_agreement_signed_date, -1) AS STRING), 'yyyyMMdd')
      ) IS NULL
      THEN 1
      ELSE 0
    END AS CCV,
    fc.first_discount_proposed,
    fc.last_discount_proposed,
    fl.price,
    fc.first_price_offered_by_buyer,
    fc.last_price_offered_by_buyer,
    fc.sk_agent,
    os.id_user_agent,
    os.id_agent,
    os.team_lead_name,
    os.consultant_name,
    os.agent_name
  FROM dw_sale.fact_offers AS fc
  LEFT JOIN datalake_sale_offer_flows.offer_specialists AS os
    ON fc.sk_offer = os.id_offer
  JOIN dw_public.dim_user AS dub
    ON fc.sk_buyer = dub.sk_user
  JOIN dw_sale.fact_listings AS fl
    ON fc.sk_house = fl.sk_house
  JOIN dw_sale.dim_listing AS sdl
    ON fc.sk_house = sdl.sk_house
  JOIN dw_sale.dim_offer AS dof
    ON dof.sk_offer = fc.sk_offer
  WHERE
    (
      dof.is_3p_supply = TRUE OR dof.is_3p_demand = TRUE
    )
)
SELECT
  sk_offer,
  report.sk_house,
  status_imovel,
  partner_3p_supply,
  partner_3p_demand,
  is_3p_supply,
  is_3p_demand,
  last_depublication_date,
  offer_submitted_date,
  offer_accepted_date,
  offer_dismissed_date,
  sale_agreement_signed_date,
  OS,
  OA,
  OD,
  CCV,
  first_discount_proposed,
  last_discount_proposed,
  price,
  first_price_offered_by_buyer,
  last_price_offered_by_buyer,
  sk_agent,
  id_user_agent,
  id_agent,
  team_lead_name,
  consultant_name,
  agent_name,
  CASE WHEN sold_or_rented.sk_house IS NULL THEN FALSE ELSE TRUE END AS sold_or_rented_by_5A
FROM report
LEFT JOIN sold_or_rented
  ON report.sk_house = sold_or_rented.sk_house