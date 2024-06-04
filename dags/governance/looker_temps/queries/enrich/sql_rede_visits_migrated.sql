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
  SELECT DISTINCT
    db.id_booking,
    fv.sk_house,
    fv.sk_agent,
    du.id AS sk_user_agent,
    du.nome,
    DATE(db.ts_created_local) AS ts_created_local,
    DATE(db.ts_scheduling_local) AS ts_scheduling_local,
    DATE(db.ts_cancel_local) AS ts_cancel_local,
    TO_DATE(
      CAST(NULLIF(fl.sk_last_depublication_date, -1) AS STRING),
      CAST('yyyymmdd' AS STRING)
    ) AS last_depublication_date,
    db.partner_3p_supply,
    db.partner_3p_demand,
    db.is_3p_supply,
    db.is_3p_demand,
    db.user_sale_booking_creator,
    db.first_update_source,
    db.cancelled_by,
    db.owner_arrived,
    db.status AS booking_status,
    sdl.status AS listing_status,
    db.cancellation_reason,
    hl.house_unpublished_reason,
    fl.price,
    CASE
      WHEN sdl.status = 'UNPUBLISHED'
      THEN DATEDIFF(
        DAY,
        ts_created_local,
        CAST(TO_DATE(
          CAST(NULLIF(fl.sk_last_depublication_date, -1) AS STRING),
          CAST('yyyymmdd' AS STRING)
        ) AS TIMESTAMP)
      )
      ELSE NULL
    END AS days_vb2unp
  FROM dw_sale.fact_visits AS fv
  JOIN dw_public.dim_booking AS db
    USING (sk_booking)
  JOIN dw_rent.dim_house_listing AS hl
    ON fv.sk_house = hl.id_house
  JOIN dw_public.dim_user AS dub
    ON fv.sk_buyer = dub.sk_user
  JOIN dw_sale.fact_listings AS fl
    ON fv.sk_house = fl.sk_house
  JOIN dw_public.dim_user AS du
    ON du.dados_agente_id = fv.sk_agent
  JOIN dw_public.dim_user AS dus
    ON fl.sk_owner = dus.sk_user
  JOIN dw_sale.dim_listing AS sdl
    ON fv.sk_house = sdl.sk_house
  WHERE
    (
      db.is_3p_supply = TRUE OR db.is_3p_demand = TRUE
    )
  ORDER BY
    1 NULLS LAST
)
SELECT
  id_booking,
  report.sk_house,
  sk_agent,
  sk_user_agent,
  nome,
  ts_created_local,
  ts_scheduling_local,
  ts_cancel_local,
  last_depublication_date,
  partner_3p_supply,
  partner_3p_demand,
  is_3p_supply,
  is_3p_demand,
  user_sale_booking_creator,
  first_update_source,
  cancelled_by,
  owner_arrived,
  booking_status,
  listing_status,
  cancellation_reason,
  house_unpublished_reason,
  days_vb2unp,
  CASE WHEN days_vb2unp <= 10 THEN report.sk_house ELSE NULL END AS `UNPUBLISHED_LESS_THAN_10_DAYS`,
  CASE WHEN days_vb2unp > 10 AND days_vb2unp <= 20 THEN report.sk_house ELSE NULL END AS `UNPUBLISHED_BETWEEN_10_AND_20_DAYS`,
  CASE WHEN sold_or_rented.sk_house IS NULL THEN FALSE ELSE TRUE END AS sold_or_rented_by_5A
FROM report
LEFT JOIN sold_or_rented
  ON report.sk_house = sold_or_rented.sk_house