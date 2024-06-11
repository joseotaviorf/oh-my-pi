WITH negotiation_status AS (
  SELECT DISTINCT
    lbc.id_house,
    h.id_region,
    CASE
      WHEN business_context = 'RENT' THEN SUBSTRING(f.sk_house_listing,10,12)
      WHEN business_context = 'SALE' THEN SUBSTRING(fl.sk_sale_listing,10,12)
    END AS version,
    UPPER(lbc.business_context) AS business_context,
    'NEGOTIATED' AS status,
    'NA' AS status_reason,
    dr.name AS neighborhood,
    dr.city_name AS city,
    dr.region_code,
    CASE
      WHEN LOWER(h.type) IN ('apartamento', 'studiooukitchenette') THEN 'apartamento'
      WHEN LOWER(h.type) IN ('casa', 'casacondominio') THEN 'casa'
    END AS house_type,
    'off-market' AS house_status,
    CASE
      WHEN lbc.business_context = 'RENT' THEN dc.rent
      WHEN lbc.business_context = 'SALE' THEN ds.sale_price_agreed
    END AS price,
    CASE
      WHEN lbc.business_context = 'RENT'
        THEN (
                COALESCE(dc.rent,0) +
                COALESCE(dc.condo,0) +
                COALESCE(dc.iptu,0) +
                INT(COALESCE(dc.tenant_service_fee,0) * dc.rent) +
                COALESCE(CEIL(dc.home_insurance_value),0)
              )
    END AS rent_total_value,
    CASE
      WHEN lbc.business_context = 'SALE' THEN h.sale_price/h.total_area
    END AS sale_price_m2,
    CASE
      WHEN lbc.business_context = 'RENT' AND h.condo_type = 'Normal' THEN dc.condo
      WHEN lbc.business_context = 'SALE' AND h.condo_type = 'Normal' THEN h.condo
    END AS condo,
    CASE
      WHEN lbc.business_context = 'RENT' AND h.iptu_type = 'Normal' THEN dc.iptu
      WHEN lbc.business_context = 'SALE' AND h.iptu_type = 'Normal' THEN h.iptu
    END AS iptu,
    CASE
      WHEN lbc.business_context = 'RENT' THEN f.days_listing_to_contract_signed
      WHEN lbc.business_context = 'SALE' THEN fl.days_first_publication_to_first_sale_agreement_signed
    END AS days_in_the_market,
    h.lat,
    h.lng,
    h.bedrooms,
    h.total_area,
    CASE
      WHEN lbc.business_context = 'RENT'
        AND dc.ts_signature IS NOT NULL
        THEN dc.ts_signature
      WHEN lbc.business_context = 'SALE'
        AND fo.sk_sale_agreement_signed_date > 0
        AND ds.is_ccv_canceled = False
        THEN dd.date
    END AS ts_status_started
  FROM
    datalake_ebdb_clean.listing_business_context AS lbc
  LEFT JOIN
    dw_rent.fact_house_listings AS f
      ON lbc.id_house = SUBSTRING(f.sk_house_listing,0,9)
  LEFT JOIN
    dw_rent.dim_contract AS dc
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
  LEFT JOIN
    datalake_ebdb_clean.house AS h
      ON h.id = lbc.id_house
  INNER JOIN
    dw_public.dim_region AS dr
      ON h.id_region = dr.sk_region
)
SELECT
  nt.id_house,
  nt.id_region,
  nt.version,
  nt.business_context,
  nt.status,
  nt.status_reason,
  nt.neighborhood,
  nt.city,
  nt.region_code,
  nt.house_type,
  nt.house_status,
  nt.price,
  nt.rent_total_value,
  nt.sale_price_m2,
  nt.condo,
  nt.iptu,
  nt.days_in_the_market,
  nt.lat,
  nt.lng,
  nt.bedrooms,
  nt.total_area,
  nt.ts_status_started
FROM
  negotiation_status AS nt
WHERE
  ts_status_started IS NOT NULL
