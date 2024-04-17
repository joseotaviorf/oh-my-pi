WITH negotiation_status AS (
  SELECT DISTINCT
    lbc.id_house,
    CASE
      WHEN business_context = 'RENT' THEN SUBSTRING(f.sk_house_listing,10,12)
      WHEN business_context = 'SALE' THEN SUBSTRING(fl.sk_sale_listing,10,12)
    END AS version,
    UPPER(lbc.business_context) AS business_context,
    'NEGOTIATED' AS status,
    'NA' AS status_reason,
    CASE
      WHEN lbc.business_context = 'RENT' AND dc.ts_signature IS NOT NULL THEN dc.ts_signature
      WHEN lbc.business_context = 'SALE' AND fo.sk_sale_agreement_signed_date > 0 THEN dd.date
    END AS ts_status_started,
    CASE
      WHEN lbc.business_context = 'RENT' AND dc.ts_signature IS NOT NULL THEN dc.rent
      WHEN lbc.business_context = 'SALE' AND fo.sk_sale_agreement_signed_date > 0 THEN ds.sale_price_agreed
    END AS price
  FROM
    datalake_ebdb_clean.listing_business_context AS lbc
  LEFT JOIN
    dw_public.fact_house_listings AS f
      ON lbc.id_house = SUBSTRING(f.sk_house_listing,0,9)
  LEFT JOIN
    dw_public.dim_contract AS dc
      ON f.sk_contract = dc.sk_contract
      AND dc.ts_signature IS NOT NULL
  LEFT JOIN
    dw_sale.fact_offers AS fo
      ON fo.sk_house = lbc.id_house
      AND fo.sk_sale_agreement_signed_date > 0
  LEFT JOIN
    dw_sale.dim_sale_agreement AS ds
      ON fo.sk_offer = ds.sk_offer
  LEFT JOIN
    dw_public.dim_date AS dd
      ON dd.sk_date = fo.sk_sale_agreement_signed_date
  LEFT JOIN
    dw_sale.fact_listings AS fl
      ON fl.sk_house = fo.sk_house
)
SELECT
  nt.id_house,
  nt.version,
  nt.business_context,
  nt.status,
  nt.status_reason,
  nt.price,
  nt.ts_status_started
FROM
  negotiation_status AS nt
WHERE
  ts_status_started IS NOT NULL
