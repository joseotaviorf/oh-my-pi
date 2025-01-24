WITH
  brazil_houses AS (
    SELECT
      id_house
    FROM
      dw_public.dim_house_listing
    WHERE
      country_code = 'BR'
    GROUP BY
      1
  ),
  rent_visits AS (
    SELECT
      Id_visitor,
      MAX(dt_scheduling) AS dt_visit_rent
    FROM
      dw_public.dim_booking
    WHERE
      visit_intent = 'RENT'
      AND TYPE = 'Visita'
      AND visit_follow_up = 'VaiNegociar'
      AND country_code = 'BR'
    GROUP BY
      1
  ),
  ccv AS (
    SELECT
      sk_buyer,
      TO_DATE(MAX(sk_sale_agreement_signed_date), 'yyyyMMdd') AS dt_last_sale_agreement_signed
    FROM
      dw_sale.fact_sale_flows fs
    WHERE
      sk_sale_agreement_signed_date <> -1
    GROUP BY
      1
  ),
  final AS (
    SELECT
      fo.ts_offer_submitted,
      fo.ts_offer_accepted,
      fo.ts_offer_dismissed,
      fo.ts_offer_rescued,
      dof.offer_status,
      sf.sk_house,
      fo.sk_offer,
      sf.sk_seller,
      sf.sk_buyer,
      ccv.dt_last_sale_agreement_signed,
      ROW_NUMBER() OVER (
        PARTITION BY
          sf.sk_buyer
        ORDER BY
          fo.ts_offer_submitted DESC
      ) rn,
      CASE
        WHEN rv.id_visitor IS NULL THEN 'Sale'
        ELSE 'Híbrido'
      END AS business_context
    FROM
      dw_sale.fact_sale_flows sf
    INNER JOIN 
      brazil_houses dh 
        ON sf.sk_house = dh.id_house
    LEFT JOIN 
      dw_sale.fact_offers fo 
        ON sf.sk_sale_flow = fo.sk_sale_flow
    LEFT JOIN 
      dw_sale.dim_offer dof 
        ON dof.sk_offer = fo.sk_offer
    LEFT JOIN 
      ccv 
        ON ccv.sk_buyer = sf.sk_buyer
        AND dt_last_sale_agreement_signed >= fo.ts_offer_submitted
    LEFT JOIN 
      rent_visits rv 
        ON rv.id_visitor = sf.sk_buyer
        AND rv.dt_visit_rent BETWEEN (fo.ts_offer_dismissed - INTERVAL '30' DAY) AND (fo.ts_offer_dismissed + INTERVAL '30' DAY)
    WHERE
      fo.ts_offer_submitted IS NOT NULL
  ),
  first_ AS (
    SELECT
      *
    FROM
      final
    WHERE
      rn = 1
      AND offer_status = 'OFFER_REJECTED'
      AND date_diff (CURRENT_DATE, DATE(ts_offer_dismissed)) = 17
  ),
  second_ AS (
    SELECT
      *
    FROM
      final
    WHERE
      rn = 1
      AND offer_status = 'OFFER_ACCEPTED'
      AND dt_last_sale_agreement_signed IS NULL
      AND date_diff (CURRENT_DATE, DATE(ts_offer_accepted)) = 11
  ),
  third_ AS (
    SELECT
      *
    FROM
      final
    WHERE
      rn = 1
      AND ts_offer_accepted IS NULL
      AND ts_offer_dismissed IS NULL
      AND dt_last_sale_agreement_signed IS NULL
      AND date_diff (CURRENT_DATE, DATE(ts_offer_submitted)) = 18
  ),
  union_ AS (
    SELECT
      *
    FROM
      first_
    UNION ALL
    SELECT
      *
    FROM
      second_
    UNION ALL
    SELECT
      *
    FROM
      third_
  )
SELECT
  du.nome AS customer_name,
  du.email AS customer_email,
  du.telefone_principal AS customer_phone,
  'Oferta' AS campaign_step,
  'Buyer' AS customer_type,
  du.cpf AS customer_cpf,
  v.sk_buyer AS id_user,
  'lost' AS campaign_type,
  'offer' AS driver_type,
  v.sk_offer AS id_driver,
  v.business_context
FROM
  union_ v
JOIN 
  dw_public.dim_user du 
    ON du.sk_user = v.sk_buyer