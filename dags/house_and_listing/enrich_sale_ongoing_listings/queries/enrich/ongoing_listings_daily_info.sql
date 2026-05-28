WITH lpv AS (
    SELECT
        COUNT(*) AS listing_page_viewed,
        ep_house_id AS id_house,
        year,
        month,
        day
    FROM
        datalake_amplitude_clean.170698_listing_page_viewed_events
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND ep_house_id IS NOT NULL
        AND UPPER(business_context) = 'SALE'
    GROUP BY
        id_house,
        year,
        month,
        day
),
srpv_explode AS (
    SELECT
        EXPLODE(ids_search_results_list) AS id_house,
        year,
        month,
        day
    FROM
        datalake_amplitude_clean.170698_search_results_page_viewed_events
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND ids_search_results_list IS NOT NULL
        AND UPPER(business_context) = 'SALE'
),
srpv AS (
    SELECT
        COUNT(*) AS search_results_page_viewed,
        id_house,
        year,
        month,
        day
    FROM
        srpv_explode
    GROUP BY
        id_house,
        year,
        month,
        day
),
favorite_set AS (
    SELECT
        COUNT(*) AS favorites,
        ep_house_id AS id_house,
        year,
        month,
        day
    FROM
        datalake_amplitude_clean.170698_listing_favorite_set_events
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND ep_house_id IS NOT NULL
        AND UPPER(business_context) = 'SALE'
    GROUP BY
        id_house,
        year,
        month,
        day
),
demand_data AS (
    SELECT
        id_house,
        YEAR(dt_event) AS year,
        MONTH(dt_event) AS month,
        DAY(dt_event) AS day,
        COUNT_IF(event_name = 'VISIT_BOOKED') AS visits_booked,
        COUNT_IF(event_name = 'VISIT_COMPLETED') AS visits_completed,
        COUNT_IF(event_name = 'OFFER_SUBMITTED') AS offers_submitted,
        COUNT_IF(event_name = 'OFFER_ACCEPTED') AS offers_accepted,
        COUNT_IF(event_name = 'SALE_AGREEMENT_CREATED') AS sale_agreements_created,
        COUNT_IF(event_name = 'SALE_AGREEMENT_SIGNED') AS sale_agreements_signed
    FROM
        datalake_sale_demand_events.sale_demand_events
    WHERE
        dt_event BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY
        id_house,
        year,
        month,
        day
),
status_changes_aux AS (
    SELECT
        sl.id_sale_listing,
        lbc.id_house,
        h.id_region,
        lbc.status,
        lbc.ts_first_publication,
        lbc.ts_last_publication,
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
        id_sale_listing,
        id_house,
        id_region,
        status,
        ts_first_publication,
        ts_last_publication,
        ts_revision AS ts_status_started,
        LEAD(ts_revision) OVER (PARTITION BY id_house ORDER BY ts_revision) AS ts_status_ended
    FROM
        status_changes_aux AS sc
),
daily_ongoing_listings AS (
    SELECT
        d.id_date AS id_snapshot_date,
        sc.id_sale_listing,
        sc.id_house,
        sc.id_region,
        DATEDIFF(DAY, DATE(sc.ts_last_publication), d.date) + 1 AS days_published,
        sc.ts_first_publication,
        sc.ts_last_publication,
        d.date AS dt_snapshot,
        d.year,
        d.month,
        d.day
    FROM
        status_changes AS sc
    JOIN
        datalake_quintoandar.aux_date AS d
            ON d.date >= sc.ts_status_started::DATE
            AND d.date < COALESCE(sc.ts_status_ended::DATE, NOW())
    WHERE
        MAKE_DATE(d.year, d.month, d.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND sc.status = 'PUBLISHED'
)
SELECT
    dol.id_house * 100000000 + dol.id_snapshot_date AS id_snapshot,
    dol.id_snapshot_date,
    dol.id_sale_listing,
    dol.id_house,
    dol.id_region,
    cs_supply.sk_company,
    hsc.id_suggestion_change,
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
    dol.day
FROM
    daily_ongoing_listings AS dol
LEFT JOIN
    lpv
        ON lpv.year = dol.year
        AND lpv.month = dol.month
        AND lpv.day = dol.day
        AND lpv.id_house = dol.id_house
LEFT JOIN
    srpv
        ON srpv.year = dol.year
        AND srpv.month = dol.month
        AND srpv.day = dol.day
        AND srpv.id_house = dol.id_house
LEFT JOIN
    favorite_set AS fav
        ON fav.year = dol.year
        AND fav.month = dol.month
        AND fav.day = dol.day
        AND fav.id_house = dol.id_house
LEFT JOIN
    demand_data AS dd
        ON dd.year = dol.year
        AND dd.month = dol.month
        AND dd.day = dol.day
        AND dd.id_house = dol.id_house
LEFT JOIN
    datalake_ebdb_pricing.listing_price_change AS lpc
        ON dol.id_house = lpc.id_house
        AND dol.dt_snapshot >= DATE(lpc.ts_price_started)
        AND dol.dt_snapshot < COALESCE(DATE(lpc.ts_price_ended), '2100-01-01')
        AND lpc.is_last_price_of_day
        AND lpc.business_context = 'SALE'
LEFT JOIN
    datalake_ebdb_pricing.listing_prediction_changes AS pred
        ON dol.id_house = pred.id_house
        AND dol.dt_snapshot >= DATE(pred.ts_calculator_result_started)
        AND dol.dt_snapshot < COALESCE(DATE(pred.ts_calculator_result_ended), '2100-01-01')
        AND pred.is_last_prediction_of_day
        AND pred.business_context = 'SALE'
LEFT JOIN
    datalake_ebdb_pricing.house_suggestion_changes AS hsc
        ON dol.id_house = hsc.id_house
        AND dol.dt_snapshot >= DATE(hsc.ts_suggestion_started)
        AND dol.dt_snapshot < COALESCE(DATE(hsc.ts_suggestion_ended), '2100-01-01')
        AND hsc.is_last_suggestion_of_day
        AND hsc.business_context = 'SALE'
LEFT JOIN
    datalake_ebdb_listing.house AS h
        ON dol.id_house = h.id
        AND h.is_sale_3p_supply
LEFT JOIN
    datalake_company.company_sks AS cs_supply
        ON (
            h.uuid_company IS NOT NULL
            AND h.uuid_company = cs_supply.uuid_company
        )
        OR (
            h.uuid_company IS NULL
            AND h.id_company_hubspot IS NOT NULL
            AND h.id_company_hubspot = cs_supply.id_hubspot
        )
        OR (
            h.uuid_company IS NULL
            AND h.id_company_hubspot IS NULL
            AND h.partner_3p_supply = cs_supply.extracted_3p_tag
        )
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY dol.id_sale_listing, dol.id_snapshot_date ORDER BY lpc.ts_price_started DESC) = 1
