WITH bp_status AS (
  SELECT
    bps.id_buyer_prospect,
    bps.prospect_event_name,
    bps.status_trigger_event_name,
    CASE
      WHEN bps.prospect_event_name = 'USER RECOVERY' THEN 'RBP'
      WHEN bps.prospect_event_name IN (
        'USER FIRST ACTIVATION',
        'USER FIRST ACTIVATION IN CITY GROUP'
      ) THEN 'NBP'
    END AS bp_type,
    bps.city_group,
    bps.status_detail,
    bps.status,
    bps.ts_status_started AS ts_activation,
    COALESCE(
      bps.ts_status_ended,
      LEAD(bps.ts_status_started) OVER (PARTITION BY bps.id_buyer_prospect ORDER BY bps.ts_status_started)
     ) AS ts_activation_end
  FROM
    datalake_demand_flows.buyer_prospect_status AS bps
),
bookings AS (
  SELECT
    id_visitor,
    id_visit,
    id_house,
    ts_created AS ts_booking_created
  FROM
    datalake_booking.booking
  WHERE
    visit_intent = 'SALE'
)
SELECT
  bp_status.id_buyer_prospect AS id_prospect,
  h.id_region,
  bookings.id AS id_first_booking,
  bookings.id_house AS id_house_first_booking,
  CASE
    WHEN bp_type = 'NBP' THEN 1
    WHEN bp_type = 'RBP' THEN 2
  END AS sk_buyer_prospect_type,
  bp_status.bp_type,
  bp_status.city_group,
  slpc.price_segment,
  bp_status.ts_activation,
  bp_status.ts_activation_end,
  bookings.ts_created AS ts_first_booking
FROM
  bp_status
  INNER JOIN 
    datalake_booking.booking AS bookings 
      ON bp_status.id_buyer_prospect = bookings.id_visitor
      AND bookings.ts_created BETWEEN bp_status.ts_activation
      AND COALESCE(bp_status.ts_activation_end, NOW())
  LEFT JOIN
    datalake_ebdb_clean.house AS h
      ON bookings.id_house = h.id
  LEFT JOIN 
    datalake_sale_listings.sale_listing_price_changes AS slpc 
      ON bookings.id_house = slpc.id_house
      AND bookings.ts_created BETWEEN slpc.ts_price_started
      AND COALESCE(slpc.ts_price_ended, NOW())
WHERE
    bp_status.status = 'ACTIVE'
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY bp_status.id_buyer_prospect,
    bp_status.ts_activation_end,
    bp_status.bp_type,
    bp_status.city_group,
    bp_status.status
    ORDER BY
      bookings.ts_created ASC
  ) = 1