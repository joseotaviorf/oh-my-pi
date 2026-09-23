WITH lpv AS (
  SELECT
    COUNT(*) AS listing_page_viewed,
    ep_house_id AS id_house,
    year,
    month,
    day
  FROM datalake_amplitude_clean.170698_listing_page_viewed_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
    AND NOT ep_house_id IS NULL
    AND UPPER(business_context) = 'SALE'
  GROUP BY
    id_house,
    year,
    month,
    day
), srpv_explode AS (
  SELECT
    EXPLODE(ids_search_results_list) AS id_house,
    year,
    month,
    day
  FROM datalake_amplitude_clean.170698_search_results_page_viewed_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
    AND NOT ids_search_results_list IS NULL
    AND UPPER(business_context) = 'SALE'
), srpv AS (
  SELECT
    COUNT(*) AS search_results_page_viewed,
    id_house,
    year,
    month,
    day
  FROM srpv_explode
  GROUP BY
    id_house,
    year,
    month,
    day
), favorite_set AS (
  SELECT
    COUNT(*) AS favorites,
    ep_house_id AS id_house,
    year,
    month,
    day
  FROM datalake_amplitude_clean.170698_listing_favorite_set_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
    AND NOT ep_house_id IS NULL
    AND UPPER(business_context) = 'SALE'
  GROUP BY
    id_house,
    year,
    month,
    day
), demand_data AS (
  SELECT
    id_house,
    YEAR(TO_DATE(dt_event)) AS year,
    MONTH(TO_DATE(dt_event)) AS month,
    DAY(TO_DATE(dt_event)) AS day,
    COUNT_IF(event_name = 'VISIT_BOOKED') AS visits_booked,
    COUNT_IF(event_name = 'VISIT_COMPLETED') AS visits_completed,
    COUNT_IF(event_name = 'OFFER_SUBMITTED') AS offers_submitted,
    COUNT_IF(event_name = 'OFFER_ACCEPTED') AS offers_accepted,
    COUNT_IF(event_name = 'SALE_AGREEMENT_CREATED') AS sale_agreements_created,
    COUNT_IF(event_name = 'SALE_AGREEMENT_SIGNED') AS sale_agreements_signed
  FROM datalake_sale_demand_events.sale_demand_events
  WHERE
    dt_event BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
  GROUP BY
    id_house,
    year,
    month,
    day
), status_changes_aux AS (
  SELECT
    id_sale_listing,
    id_house,
    id_region,
    status,
    ts_first_publication,
    ts_last_publication,
    ts_revision
  FROM (
    SELECT
      sl.id_sale_listing,
      lbc.id_house,
      h.id_region,
      lbc.status,
      lbc.ts_first_publication,
      lbc.ts_last_publication,
      ure.ts_revision,
      LAG(lbc.status) OVER (PARTITION BY lbc.id_house ORDER BY ure.ts_revision) AS _w
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
    id_sale_listing,
    id_house,
    id_region,
    status,
    ts_first_publication,
    ts_last_publication,
    ts_revision AS ts_status_started,
    LEAD(ts_revision) OVER (PARTITION BY id_house ORDER BY ts_revision) AS ts_status_ended
  FROM status_changes_aux AS sc
), published_intervals AS (
  -- Clip [started, ended) to the load window, then explode days for an equi-join to aux_date
  -- (avoids BroadcastNestedLoopJoin on EMR from a pure range join).
  SELECT
    id_sale_listing,
    id_house,
    id_region,
    ts_first_publication,
    ts_last_publication,
    GREATEST(
      CAST(ts_status_started AS DATE),
      CAST('{load_start_date}' AS DATE)
    ) AS dt_from,
    LEAST(
      CASE
        WHEN ts_status_ended IS NULL THEN CAST(NOW() AS DATE)
        ELSE DATE_SUB(CAST(ts_status_ended AS DATE), 1)
      END,
      CAST('{load_end_date}' AS DATE)
    ) AS dt_to
  FROM status_changes
  WHERE
    status = 'PUBLISHED'
), published_days AS (
  SELECT
    id_sale_listing,
    id_house,
    id_region,
    ts_first_publication,
    ts_last_publication,
    EXPLODE(SEQUENCE(dt_from, dt_to)) AS dt_snapshot
  FROM published_intervals
  WHERE
    dt_from <= dt_to
), daily_ongoing_listings AS (
  SELECT
    d.id_date AS id_snapshot_date,
    pd.id_sale_listing,
    pd.id_house,
    pd.id_region,
    CAST(
      DATEDIFF(TO_DATE(d.date), TO_DATE(CAST(pd.ts_last_publication AS DATE))) + 1 AS BIGINT
    ) AS days_published,
    pd.ts_first_publication,
    pd.ts_last_publication,
    d.date AS dt_snapshot,
    d.year,
    d.month,
    d.day
  FROM published_days AS pd
  JOIN datalake_quintoandar.aux_date AS d
    ON d.date = pd.dt_snapshot
)
SELECT
  id_snapshot,
  id_snapshot_date,
  id_sale_listing,
  id_house,
  id_region,
  id_suggestion_change,
  sale_type,
  sale_price,
  calculator_min_price,
  calculator_p20_price,
  calculator_p30_price,
  calculator_p40_price,
  calculator_price,
  calculator_p60_price,
  calculator_p70_price,
  calculator_p80_price,
  calculator_max_price,
  lower_bound_limit,
  suggested_lower_bound_price,
  suggested_upper_bound_price,
  upper_bound_limit,
  suggestion_certainty,
  qt_search_results_page_viewed,
  qt_listing_page_viewed,
  qt_favorites,
  qt_visits_booked,
  qt_visits_completed,
  qt_offers_submitted,
  qt_offers_accepted,
  qt_sale_agreements_created,
  qt_sale_agreements_signed,
  days_published,
  ts_first_publication,
  ts_last_publication,
  year,
  month,
  day
FROM (
  SELECT
    dol.id_house * 100000000 + dol.id_snapshot_date AS id_snapshot,
    dol.id_snapshot_date,
    dol.id_sale_listing,
    dol.id_house,
    dol.id_region,
    hsc.id_suggestion_change,
    lst.sale_type,
    lpc.price AS sale_price,
    pred.calculator_min_price,
    pred.calculator_p20_price,
    pred.calculator_p30_price,
    pred.calculator_p40_price,
    pred.calculator_price,
    pred.calculator_p60_price,
    pred.calculator_p70_price,
    pred.calculator_p80_price,
    pred.calculator_max_price,
    hsc.lower_bound_limit,
    hsc.suggested_lower_bound_price,
    hsc.suggested_upper_bound_price,
    hsc.upper_bound_limit,
    hsc.suggestion_certainty,
    srpv.search_results_page_viewed AS qt_search_results_page_viewed,
    lpv.listing_page_viewed AS qt_listing_page_viewed,
    fav.favorites AS qt_favorites,
    dd.visits_booked AS qt_visits_booked,
    dd.visits_completed AS qt_visits_completed,
    dd.offers_submitted AS qt_offers_submitted,
    dd.offers_accepted AS qt_offers_accepted,
    dd.sale_agreements_created AS qt_sale_agreements_created,
    dd.sale_agreements_signed AS qt_sale_agreements_signed,
    dol.days_published,
    dol.ts_first_publication,
    dol.ts_last_publication,
    dol.year,
    dol.month,
    dol.day,
    ROW_NUMBER() OVER (PARTITION BY dol.id_sale_listing, dol.id_snapshot_date ORDER BY lpc.ts_price_started DESC) AS _w,
    lpc.ts_price_started
  FROM daily_ongoing_listings AS dol
  LEFT JOIN lpv
    ON lpv.year = dol.year
    AND lpv.month = dol.month
    AND lpv.day = dol.day
    AND lpv.id_house = dol.id_house
  LEFT JOIN srpv
    ON srpv.year = dol.year
    AND srpv.month = dol.month
    AND srpv.day = dol.day
    AND srpv.id_house = dol.id_house
  LEFT JOIN favorite_set AS fav
    ON fav.year = dol.year
    AND fav.month = dol.month
    AND fav.day = dol.day
    AND fav.id_house = dol.id_house
  LEFT JOIN demand_data AS dd
    ON dd.year = dol.year
    AND dd.month = dol.month
    AND dd.day = dol.day
    AND dd.id_house = dol.id_house
  LEFT JOIN datalake_ebdb_pricing.listing_price_change AS lpc
    ON dol.id_house = lpc.id_house
    AND dol.dt_snapshot >= CAST(lpc.ts_price_started AS DATE)
    AND dol.dt_snapshot < COALESCE(CAST(lpc.ts_price_ended AS DATE), '2100-01-01')
    AND lpc.is_last_price_of_day
    AND lpc.business_context = 'SALE'
  LEFT JOIN datalake_ebdb_pricing.listing_prediction_changes AS pred
    ON dol.id_house = pred.id_house
    AND dol.dt_snapshot >= CAST(pred.ts_calculator_result_started AS DATE)
    AND dol.dt_snapshot < COALESCE(CAST(pred.ts_calculator_result_ended AS DATE), '2100-01-01')
    AND pred.is_last_prediction_of_day
    AND pred.business_context = 'SALE'
  LEFT JOIN datalake_ebdb_pricing.house_suggestion_changes AS hsc
    ON dol.id_house = hsc.id_house
    AND dol.dt_snapshot >= CAST(hsc.ts_suggestion_started AS DATE)
    AND dol.dt_snapshot < COALESCE(CAST(hsc.ts_suggestion_ended AS DATE), '2100-01-01')
    AND hsc.is_last_suggestion_of_day
    AND hsc.business_context = 'SALE'
  LEFT JOIN datalake_sale_primary_market.listing_sale_type AS lst
    ON dol.id_house = lst.id_house
) AS _t
WHERE
  _w = 1
