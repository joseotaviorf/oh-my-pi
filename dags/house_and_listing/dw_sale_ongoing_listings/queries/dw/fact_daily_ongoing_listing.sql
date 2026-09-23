WITH amplitude_data AS (
  SELECT
    sse.id_house,
    sse.year,
    sse.month,
    sse.day,
    COUNT_IF(sse.event_type = 'Search') AS qt_search_result_page_viewed,
    COUNT_IF(sse.event_type = 'Listing Page Viewed') AS qt_listing_page_viewed
  FROM datalake_search_session_event.search_session_event AS sse
  WHERE
    MAKE_DATE(sse.year, sse.month, sse.day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
    AND sse.business_context = 'sale'
  GROUP BY
    1,
    2,
    3,
    4
), demand_data AS (
  SELECT
    fsde.sk_house,
    fsde.year,
    fsde.month,
    fsde.day,
    COUNT_IF(dset.event_name = 'VISIT_BOOKED') AS qt_visits_booked,
    COUNT_IF(dset.event_name = 'VISIT_COMPLETED') AS qt_visits_completed,
    COUNT_IF(dset.event_name = 'OFFER_SUBMITTED') AS qt_offers_submitted,
    COUNT_IF(dset.event_name = 'OFFER_ACCEPTED') AS qt_offers_accepted,
    COUNT_IF(dset.event_name = 'SALE_AGREEMENT_CREATED') AS qt_sale_agreements_created,
    COUNT_IF(dset.event_name = 'SALE_AGREEMENT_SIGNED') AS qt_sale_agreements_signed
  FROM dw_sale.fact_sale_demand_event AS fsde
  JOIN dw_sale.dim_sale_event_type AS dset
    ON fsde.sk_event_type = dset.sk_event_type
  WHERE
    MAKE_DATE(fsde.year, fsde.month, fsde.day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
  GROUP BY
    1,
    2,
    3,
    4
), status_changes_aux AS (
  SELECT
    sk_sale_listing,
    sk_house,
    sk_region,
    status,
    ts_revision
  FROM (
    SELECT
      sl.id_sale_listing AS sk_sale_listing,
      lbc.id_house AS sk_house,
      h.id_region AS sk_region,
      lbc.status,
      ure.ts_revision,
      LAG(lbc.status) OVER (PARTITION BY lbc.id_house ORDER BY ure.ts_revision) AS _w,
      lbc.id_house
    FROM datalake_ebdb_clean.listing_business_context_aud AS lbc
    JOIN datalake_ebdb_user.user_revision_entity AS ure
      ON lbc.rev = ure.id
    JOIN datalake_sale_listings.sale_listing AS sl
      ON lbc.id_house = sl.id_house
    JOIN datalake_ebdb_clean.house AS h
      ON lbc.id_house = h.id
    WHERE
      lbc.business_context = 'SALE'
  ) AS _t
  WHERE
    _w IS DISTINCT FROM status
), status_changes AS (
  SELECT
    sk_sale_listing,
    sk_house,
    sk_region,
    status,
    ts_revision AS ts_status_started,
    LEAD(ts_revision) OVER (PARTITION BY sk_house ORDER BY ts_revision) AS ts_status_ended
  FROM status_changes_aux
), published_intervals AS (
  -- Clip inclusive [started, ended] to the load window, then explode days for an equi-join
  -- to dim_date (avoids BroadcastNestedLoopJoin on EMR from a pure range join).
  SELECT
    sk_sale_listing,
    sk_house,
    sk_region,
    ts_status_started,
    GREATEST(
      CAST(ts_status_started AS DATE),
      CAST('{load_start_date}' AS DATE)
    ) AS dt_from,
    LEAST(
      COALESCE(CAST(ts_status_ended AS DATE), CAST(NOW() AS DATE)),
      CAST('{load_end_date}' AS DATE)
    ) AS dt_to
  FROM status_changes
  WHERE
    status = 'PUBLISHED'
), published_days AS (
  SELECT
    sk_sale_listing,
    sk_house,
    sk_region,
    ts_status_started,
    EXPLODE(SEQUENCE(dt_from, dt_to)) AS dt_snapshot
  FROM published_intervals
  WHERE
    dt_from <= dt_to
), daily_ongoing_listings AS (
  SELECT
    sk_snapshot_date,
    sk_sale_listing,
    sk_house,
    sk_region,
    dt_snapshot,
    year,
    month,
    day
  FROM (
    SELECT
      dd.sk_date AS sk_snapshot_date,
      pd.sk_sale_listing,
      pd.sk_house,
      pd.sk_region,
      dd.date AS dt_snapshot,
      dd.year,
      dd.month,
      dd.day,
      ROW_NUMBER() OVER (
        PARTITION BY pd.sk_house, dd.`date`
        ORDER BY pd.ts_status_started DESC
      ) AS _w
    FROM published_days AS pd
    JOIN dw_public.dim_date AS dd
      ON dd.`date` = pd.dt_snapshot
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  sk_snapshot,
  sk_snapshot_date,
  sk_sale_listing,
  sk_house,
  sk_region,
  sk_broker,
  sk_sale_price_segment,
  sk_suggestion_change,
  sale_type,
  sale_price,
  lower_bound_limit,
  suggested_lower_bound_price,
  suggested_upper_bound_price,
  upper_bound_limit,
  suggestion_certainty,
  qt_search_result_page_viewed,
  qt_listing_page_viewed,
  qt_visits_booked,
  qt_visits_completed,
  qt_offers_submitted,
  qt_offers_accepted,
  qt_sale_agreements_created,
  qt_sale_agreements_signed,
  year,
  month,
  day,
  ts_load
FROM (
  SELECT
    dol.sk_house * 100000000 + dol.sk_snapshot_date AS sk_snapshot,
    dol.sk_snapshot_date,
    dol.sk_sale_listing,
    dol.sk_house,
    COALESCE(dol.sk_region, -1) AS sk_region,
    COALESCE(CASE WHEN h.is_sale_3p_supply THEN cb_supply.sk_broker END, -1) AS sk_broker,
    COALESCE(dsps.sk_sale_price_segment, -1) AS sk_sale_price_segment,
    COALESCE(hsc.id_suggestion_change, -1) AS sk_suggestion_change,
    lst.sale_type,
    slpc.sale_price,
    hsc.lower_bound_limit,
    hsc.suggested_lower_bound_price,
    hsc.suggested_upper_bound_price,
    hsc.upper_bound_limit,
    hsc.suggestion_certainty,
    COALESCE(ad.qt_search_result_page_viewed, 0) AS qt_search_result_page_viewed,
    COALESCE(ad.qt_listing_page_viewed, 0) AS qt_listing_page_viewed,
    COALESCE(dd.qt_visits_booked, 0) AS qt_visits_booked,
    COALESCE(dd.qt_visits_completed, 0) AS qt_visits_completed,
    COALESCE(dd.qt_offers_submitted, 0) AS qt_offers_submitted,
    COALESCE(dd.qt_offers_accepted, 0) AS qt_offers_accepted,
    COALESCE(dd.qt_sale_agreements_created, 0) AS qt_sale_agreements_created,
    COALESCE(dd.qt_sale_agreements_signed, 0) AS qt_sale_agreements_signed,
    dol.year,
    dol.month,
    dol.day,
    NOW() AS ts_load,
    ROW_NUMBER() OVER (PARTITION BY dol.sk_sale_listing, dol.sk_snapshot_date ORDER BY slpc.ts_price_started DESC) AS _w,
    slpc.ts_price_started
  FROM daily_ongoing_listings AS dol
  LEFT JOIN amplitude_data AS ad
    ON ad.year = dol.year
    AND ad.month = dol.month
    AND ad.day = dol.day
    AND ad.id_house = dol.sk_house
  LEFT JOIN demand_data AS dd
    ON dd.year = dol.year
    AND dd.month = dol.month
    AND dd.day = dol.day
    AND dd.sk_house = dol.sk_house
  LEFT JOIN datalake_sale_listings.sale_listing_price_changes AS slpc
    ON dol.sk_house = slpc.id_house
    AND dol.dt_snapshot BETWEEN slpc.ts_price_started AND COALESCE(slpc.ts_price_ended, NOW())
  LEFT JOIN dw_sale.dim_sale_price_segment AS dsps
    ON slpc.price_segment = dsps.price_segment
  LEFT JOIN datalake_ebdb_pricing.house_suggestion_changes AS hsc
    ON dol.sk_house = hsc.id_house
    AND dol.dt_snapshot >= CAST(hsc.ts_suggestion_started AS DATE)
    AND dol.dt_snapshot < COALESCE(CAST(hsc.ts_suggestion_ended AS DATE), '2100-01-01')
    AND hsc.is_last_suggestion_of_day
    AND hsc.business_context = 'SALE'
  LEFT JOIN datalake_sale_primary_market.listing_sale_type AS lst
    ON dol.sk_house = lst.id_house
  LEFT JOIN datalake_ebdb_listing.house AS h
    ON dol.sk_house = h.id
  LEFT JOIN core_brokers.brokers AS cb_supply
    ON cb_supply.uuid_company = h.uuid_company
) AS _t
WHERE
  _w = 1
