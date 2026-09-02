WITH
  selected_and_scoped_sales_flows AS (
    SELECT
      offer.id_sales_flow
    FROM
      datalake_sales_flow_clean.offer AS offer
    LEFT JOIN
      datalake_sales_flow_clean.ccv_flow AS ccv_flow
        ON offer.id_sales_flow = ccv_flow.id_sales_flow
    WHERE
      DATE(FROM_UTC_TIMESTAMP(ccv_flow.ts_created, 'America/Sao_Paulo')) >= DATE('2025-11-11')
      AND ccv_flow.status IS NOT NULL
  ),
  buyer_counts AS (
    SELECT
      bd.id_sales_flow,
      COUNT(bd.id_buyer) AS total_buyers,
      COUNT(
        CASE
          WHEN sb.status = 'COMPLETED'
          THEN bd.id_buyer
        END
      ) AS confirmed_buyers
    FROM
      datalake_sales_flow_clean.buyer_data AS bd
    LEFT JOIN
      datalake_sales_flow_clean.screening_buyer AS sb
        ON bd.id_buyer = sb.id_buyer_data
    GROUP BY
      bd.id_sales_flow
  ),
  seller_counts AS (
    SELECT
      sd.id_sales_flow,
      COUNT(sd.id_seller) AS total_sellers,
      COUNT(
        CASE
          WHEN ss.status = 'COMPLETED'
          THEN sd.id_seller
        END
      ) AS confirmed_sellers
    FROM
      datalake_sales_flow_clean.seller_data AS sd
    LEFT JOIN
      datalake_sales_flow_clean.screening_seller AS ss
        ON sd.id_seller = ss.id_seller_data
    GROUP BY
      sd.id_sales_flow
  ),
  ebdb_listing_data AS (
    SELECT
      sales_flow.id AS id_sales_flow,
      sales_flow_house.id_external AS id_house,
      ebdb_house.parking_slots AS parking_slots
    FROM
      datalake_sales_flow_clean.sales_flow AS sales_flow
    LEFT JOIN
      datalake_sales_flow_clean.house AS sales_flow_house
        ON sales_flow.id_house = sales_flow_house.id
    LEFT JOIN
      datalake_ebdb_clean.house AS ebdb_house
        ON sales_flow_house.id_external = ebdb_house.id
  ),
  all_fields AS (
    SELECT
      o.id_sales_flow,
      h.id_external AS ScreeningCCV__property_id,
      bc.total_buyers AS ScreeningCCV__total_buyers,
      bc.confirmed_buyers AS ScreeningCCV__confirmed_buyers,
      sc.total_sellers AS ScreeningCCV__total_sellers,
      sc.confirmed_sellers AS ScreeningCCV__confirmed_sellers,
      ccvf.ts_created AS ScreeningCCV__ccv_flow_ts_created,
      CASE
        WHEN ccvf.ts_signed IS NOT NULL THEN 'Backtest - CCV Signed'
        WHEN ccvf.ts_confection_started IS NOT NULL THEN 'Backtest - CCV Generated but not Signed'
        WHEN o.id_sales_flow IN (315014) THEN 'Backtest - Manual inclusion of open contracts'
        ELSE NULL
      END AS Backtest__backtest_subgroup,
      p.payment_method AS Negotiation__payment_method,
      p.payment_model AS Negotiation__payment_model,
      n.is_seller_pj AS Conditions__is_seller_pj,
      n.is_buyer_pj AS Conditions__is_buyer_pj,
      n.is_consorcio_payment AS Conditions__is_consorcio_payment,
      ad.street AS PropertyAddress__street,
      ad.number AS PropertyAddress__number,
      ad.complement AS PropertyAddress__complement,
      ad.neighborhood AS PropertyAddress__neighborhood,
      ad.city AS PropertyAddress__city,
      ad.zip_code AS PropertyAddress__zip_code,
      ad.state AS PropertyAddress__state,
      ebdb_listing_data.parking_slots AS EBDB__ParkingSlots,
      h.has_pending_registry_update AS PropertyChecks__needs_update,
      h.land_tenure AS PropertyChecks__land_tenure,
      h.has_chattel_mortgage AS PropertyChecks__has_fiduciary_alienation,
      h.has_instituted_usufruct AS PropertyChecks__has_usufruct
    FROM
      datalake_sales_flow_clean.offer AS o
    LEFT JOIN
      datalake_sales_flow_clean.payment AS p
        ON o.id_sales_flow = p.id_sales_flow
    LEFT JOIN
      datalake_sales_flow_clean.negotiation AS n
        ON o.id_sales_flow = n.id_sales_flow
    LEFT JOIN
      datalake_sales_flow_clean.ccv_flow AS ccvf
        ON o.id_sales_flow = ccvf.id_sales_flow
    LEFT JOIN
      datalake_sales_flow_clean.sales_flow AS sf
        ON o.id_sales_flow = sf.id
    LEFT JOIN
      datalake_sales_flow_clean.house AS h
        ON sf.id_house = h.id
    LEFT JOIN
      datalake_sales_flow_clean.address_data AS ad
        ON h.id_address_data = ad.id
    LEFT JOIN
      buyer_counts AS bc
        ON o.id_sales_flow = bc.id_sales_flow
    LEFT JOIN
      seller_counts AS sc
        ON o.id_sales_flow = sc.id_sales_flow
    LEFT JOIN
      selected_and_scoped_sales_flows AS scoped_sales_flows
        ON o.id_sales_flow = scoped_sales_flows.id_sales_flow
    LEFT JOIN
      ebdb_listing_data
        ON o.id_sales_flow = ebdb_listing_data.id_sales_flow
    WHERE
      scoped_sales_flows.id_sales_flow IS NOT NULL
  )
SELECT
  id_sales_flow,
  ScreeningCCV__property_id,
  ScreeningCCV__total_buyers,
  ScreeningCCV__confirmed_buyers,
  ScreeningCCV__total_sellers,
  ScreeningCCV__confirmed_sellers,
  ScreeningCCV__ccv_flow_ts_created,
  Negotiation__payment_method,
  Conditions__is_seller_pj,
  Conditions__is_buyer_pj,
  Conditions__is_consorcio_payment,
  PropertyAddress__street,
  PropertyAddress__number,
  PropertyAddress__complement,
  PropertyAddress__neighborhood,
  PropertyAddress__city,
  PropertyAddress__zip_code,
  PropertyAddress__state,
  EBDB__ParkingSlots,
  PropertyChecks__needs_update,
  PropertyChecks__land_tenure,
  PropertyChecks__has_fiduciary_alienation,
  PropertyChecks__has_usufruct
FROM
  all_fields
WHERE
  Backtest__backtest_subgroup IS NOT NULL
  AND Negotiation__payment_model = 'CCV_ASSISTANCE'
