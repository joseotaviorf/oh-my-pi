WITH amplitude_data AS (
  SELECT
      sse.id_house,
      sse.year,
      sse.month,
      sse.day,
      COUNT_IF(sse.event_type = 'Search') AS qt_search_result_page_viewed,
      COUNT_IF(sse.event_type = 'Listing Page Viewed') AS qt_listing_page_viewed
  FROM
      datalake_search_session_event.search_session_event AS sse
  WHERE
    sse.year = {year}
    AND sse.month = {month}
    AND sse.day = {day}
  GROUP BY
      1, 2, 3, 4
),
demand_data AS (
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
    FROM
        dw_sale.fact_sale_demand_event AS fsde
    JOIN
        dw_sale.dim_sale_event_type AS dset
            ON fsde.sk_event_type = dset.sk_event_type
    WHERE
        fsde.year = {year}
        AND fsde.month = {month}
        AND fsde.day = {day}
    GROUP BY 1, 2, 3, 4
),
daily_ongoing_listings AS (
    SELECT
        dd.sk_date AS sk_snapshot_date,
        sls.id_sale_listing AS sk_sale_listing,
        sls.id_house AS sk_house,
        sls.id_region AS sk_region,
        dd.date AS dt_snapshot,
        dd.year,
        dd.month,
        dd.day
    FROM
        datalake_sale_listings.sale_listing_status AS sls
    JOIN
        dw_public.dim_date AS dd
            ON dd.`date` BETWEEN sls.ts_status_started::DATE AND COALESCE(sls.ts_status_ended::DATE, NOW())
    WHERE
        sls.status_history = 'PUBLISHED'
        AND dd.year = {year}
        AND dd.month = {month}
        AND dd.day = {day}
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY sls.id_house, dd.`date` ORDER BY sls.ts_status_started DESC)
)
SELECT
    dol.sk_house * 100000000 + dol.sk_snapshot_date AS sk_snapshot, 
    dol.sk_snapshot_date,
    dol.sk_sale_listing,
    dol.sk_house,
    COALESCE(dol.sk_region, -1) AS sk_region,
    COALESCE(cs_supply.sk_company, -1) AS sk_company,
    slpc.sale_price,
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
    NOW() AS ts_load
FROM
    daily_ongoing_listings AS dol
LEFT JOIN
    amplitude_data AS ad
        ON ad.year = dol.year
        AND ad.month = dol.month
        AND ad.day = dol.day
        AND ad.id_house = dol.sk_house
LEFT JOIN
    demand_data AS dd
        ON dd.year = dol.year
        AND dd.month = dol.month
        AND dd.day = dol.day
        AND dd.sk_house = dol.sk_house
LEFT JOIN
    datalake_sale_listings.sale_listing_price_changes AS slpc
        ON dol.sk_house = slpc.id_house
        AND dol.dt_snapshot BETWEEN slpc.ts_price_started AND COALESCE(slpc.ts_price_ended, NOW())
LEFT JOIN
    datalake_rede_house_history.rede_house_history AS rhh
        ON dol.sk_house = rhh.id_house
        AND rhh.is_3p_supply
        AND rhh.business_context = 'SALE'
        AND dol.dt_snapshot BETWEEN rhh.ts_status_started AND COALESCE(rhh.ts_status_ended, NOW())
LEFT JOIN
    datalake_rede_company.company_sks AS cs_supply
        ON (rhh.id_company_hubspot IS NOT NULL
        AND rhh.id_company_hubspot = cs_supply.id_hubspot)
        OR (rhh.id_company_hubspot IS NULL
        AND rhh.partner_3p_supply = cs_supply.extracted_3p_tag)
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY dol.sk_sale_listing, dol.sk_snapshot_date ORDER BY slpc.ts_price_started DESC, rhh.ts_status_started DESC) = 1