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
        sse.business_context = 'sale'
        AND sse.year = {year}
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
status_changes_aux AS (
    SELECT
        sl.id_sale_listing AS sk_sale_listing,
        lbc.id_house AS sk_house,
        h.id_region AS sk_region,
        lbc.status,
        ure.ts_revision
    FROM
        datalake_ebdb_clean.listing_business_context_aud AS lbc
    JOIN
        datalake_ebdb_user.user_revision_entity AS ure
            ON lbc.rev = ure.id
    JOIN
        datalake_sale_listings.sale_listing AS sl
            ON lbc.id_house = sl.id_house
    JOIN
        datalake_ebdb_clean.house AS h
            ON lbc.id_house = h.id
    WHERE
        lbc.business_context = 'SALE'
    QUALIFY
        LAG(lbc.status) OVER (PARTITION BY lbc.id_house ORDER BY ure.ts_revision) IS DISTINCT FROM lbc.status
),
status_changes AS (
    SELECT
        sk_sale_listing,
        sk_house,
        sk_region,
        status,
        ts_revision AS ts_status_started,
        LEAD(ts_revision) OVER (PARTITION BY sk_house ORDER BY ts_revision) AS ts_status_ended
    FROM
        status_changes_aux
),
daily_ongoing_listings AS (
    SELECT
        dd.sk_date AS sk_snapshot_date,
        sc.sk_sale_listing,
        sc.sk_house,
        sc.sk_region,
        dd.date AS dt_snapshot,
        dd.year,
        dd.month,
        dd.day
    FROM
        status_changes AS sc
    JOIN
        dw_public.dim_date AS dd
            ON dd.`date` BETWEEN sc.ts_status_started::DATE AND COALESCE(sc.ts_status_ended::DATE, NOW())
    WHERE
        sc.status = 'PUBLISHED'
        AND dd.year = {year}
        AND dd.month = {month}
        AND dd.day = {day}
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY sc.sk_house, dd.`date` ORDER BY sc.ts_status_started DESC)
)
SELECT
    dol.sk_house * 100000000 + dol.sk_snapshot_date AS sk_snapshot, 
    dol.sk_snapshot_date,
    dol.sk_sale_listing,
    dol.sk_house,
    COALESCE(dol.sk_region, -1) AS sk_region,
    COALESCE(cs_supply.sk_company, -1) AS sk_company,
    COALESCE(dsps.sk_sale_price_segment, -1) AS sk_sale_price_segment,
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
    dw_sale.dim_sale_price_segment AS dsps
        ON slpc.price_segment = dsps.price_segment
LEFT JOIN
    datalake_rede_house_history.rede_house_history AS rhh
        ON dol.sk_house = rhh.id_house
        AND rhh.is_3p_supply
        AND rhh.business_context = 'SALE'
        AND dol.dt_snapshot BETWEEN rhh.ts_status_started AND COALESCE(rhh.ts_status_ended, NOW())
LEFT JOIN
    datalake_company.company_sks AS cs_supply
        ON (
            rhh.uuid_company IS NOT NULL
            AND rhh.uuid_company = cs_supply.uuid_company
        ) OR (
            rhh.uuid_company IS NULL
            AND rhh.id_company_hubspot IS NOT NULL
            AND rhh.id_company_hubspot = cs_supply.id_hubspot
        ) OR (
             rhh.uuid_company IS NULL
             AND rhh.id_company_hubspot IS NULL
             AND rhh.partner_3p_supply = cs_supply.extracted_3p_tag
        )
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY dol.sk_sale_listing, dol.sk_snapshot_date ORDER BY slpc.ts_price_started DESC, rhh.ts_status_started DESC) = 1