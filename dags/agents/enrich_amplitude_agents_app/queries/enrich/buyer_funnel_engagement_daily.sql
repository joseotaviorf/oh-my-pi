WITH utms AS (
    SELECT DISTINCT
        TRIM(LOWER(utd.behavior_type)) AS behavior,
        TRIM(LOWER(utd.medium)) AS medium,
        TRIM(LOWER(utd.utm_source)) AS utm_source,
        TRIM(LOWER(utd.utm_medium)) AS utm_medium
    FROM
        datalake_growth_taxonomy.unified_taxonomy_dictionary utd
    WHERE
        NULLIF(TRIM(utd.medium), '') IS NOT NULL
        AND NOT TRIM(LOWER(utd.medium)) IN ('other', 'none', 'null')
)
SELECT /*+ BROADCAST(utm) */
    evt.id_amplitude,
    MODE(evt.id_region) FILTER(WHERE evt.id_region IS NOT NULL) AS id_region,
    MIN_BY(utm.medium, evt.ts_event) FILTER(WHERE utm.medium IS NOT NULL) AS first_utm_medium,
    COUNT(*) AS total_events,
    COUNT_IF(evt.business_context = 'sale') AS total_sale_events,
    COUNT_IF(evt.business_context = 'sale' AND evt.event_type IN ('search_page_viewed', 'search_results_page_viewed')) AS total_sale_events_search_page_viewed,
    COUNT_IF(evt.business_context = 'sale' AND evt.event_type IN ('search_page_viewed', 'search_results_page_viewed') AND evt.search_type RLIKE 'map_') AS total_sale_events_search_page_viewed_map,
    COUNT_IF(evt.business_context = 'sale' AND evt.event_type IN ('search_page_viewed', 'search_results_page_viewed') AND evt.search_type RLIKE 'search_bar_') AS total_sale_events_search_page_viewed_bar,
    COUNT_IF(evt.business_context = 'sale' AND evt.event_type IN ('search_page_viewed', 'search_results_page_viewed') AND evt.search_type RLIKE 'deeplink') AS total_sale_events_search_page_viewed_deeplink,
    COUNT_IF(evt.business_context = 'sale' AND evt.event_type IN ('search_page_viewed', 'search_results_page_viewed') AND evt.search_type RLIKE 'copilot') AS total_sale_events_search_page_viewed_copilot,
    COUNT_IF(evt.business_context = 'sale' AND evt.event_type = 'alert_subscription_confirmed') AS total_sale_events_search_subscription,
    COUNT_IF(evt.business_context = 'sale' AND evt.event_type = 'listing_page_viewed') AS total_sale_events_listing_page_viewed,
    COUNT_IF(evt.business_context = 'sale' AND evt.event_type = 'listing_page_viewed' AND evt.lpv_origin = 'search_results') AS total_sale_events_listing_page_viewed_from_search,
    COUNT_IF(evt.business_context = 'sale' AND evt.event_type = 'listing_page_viewed' AND evt.lpv_origin = 'deeplink') AS total_sale_events_listing_page_viewed_from_deeplink,
    COUNT_IF(evt.business_context = 'sale' AND evt.event_type = 'listing_page_viewed' AND evt.lpv_origin = 'house details') AS total_sale_events_listing_page_viewed_from_house,
    COUNT_IF(evt.business_context = 'sale' AND evt.event_type = 'listing_page_viewed' AND evt.lpv_origin = 'condominium_page') AS total_sale_events_listing_page_viewed_from_condo,
    COUNT_IF(evt.business_context = 'sale' AND evt.event_type = 'listing_page_viewed' AND evt.lpv_origin RLIKE 'feed_list_') AS total_sale_events_listing_page_viewed_from_feed,
    COUNT_IF(evt.business_context = 'sale' AND evt.event_type = 'listing_page_viewed' AND evt.lpv_origin = 'similar_carousel') AS total_sale_events_listing_page_viewed_from_similar,
    COUNT_IF(evt.business_context = 'sale' AND evt.event_type = 'listing_page_viewed' AND evt.lpv_origin = 'favorites') AS total_sale_events_listing_page_viewed_from_favorite,
    COUNT_IF(evt.business_context = 'sale' AND evt.event_type = 'listing_sectionexpanded_viewed') AS total_sale_events_listing_section_expanded,
    COUNT_IF(evt.business_context = 'sale' AND evt.event_type = 'listing_sectionexpanded_viewed' AND evt.listing_section = 'condominium') AS total_sale_events_listing_section_expanded_condo,
    COUNT_IF(evt.business_context = 'sale' AND evt.event_type = 'listing_sectionexpanded_viewed' AND evt.listing_section = 'values_and_taxes') AS total_sale_events_listing_section_expanded_taxes,
    COUNT_IF(evt.business_context = 'sale' AND evt.event_type = 'listing_sectionexpanded_viewed' AND evt.listing_section = 'neighborhood') AS total_sale_events_listing_section_expanded_neighborhood,
    COUNT_IF(evt.business_context = 'sale' AND evt.event_type = 'tts_form_page_viewed') AS total_sale_events_listing_tts_form,
    APPROX_COUNT_DISTINCT(DATE_TRUNC("MINUTE", evt.ts_event)) AS total_minutes_active,
    APPROX_COUNT_DISTINCT(DATE_TRUNC("MINUTE", evt.ts_event)) FILTER(WHERE evt.business_context = 'sale') AS total_sale_minutes_active,
    APPROX_COUNT_DISTINCT(XXHASH64(
        '_', evt.event_type, evt.user_platform, evt.current_page, evt.business_context,
        evt.search_type, evt.type_property, evt.listing_section, evt.lpv_origin,
        evt.gallery_mode, evt.gallery_tab_room, evt.total_filters_applied
    )) AS total_distinct_events,
    APPROX_COUNT_DISTINCT(XXHASH64(
        '_', evt.event_type, evt.user_platform, evt.current_page, evt.search_type,
        evt.type_property, evt.listing_section, evt.lpv_origin, evt.gallery_mode,
        evt.gallery_tab_room, evt.total_filters_applied
    )) FILTER(WHERE evt.business_context = 'sale') AS total_distinct_sale_events,
    APPROX_COUNT_DISTINCT(evt.id_session) AS total_sessions,
    APPROX_COUNT_DISTINCT(evt.id_session) FILTER(WHERE evt.business_context = 'sale') AS total_sale_sessions,
    APPROX_COUNT_DISTINCT(evt.id_session) FILTER(WHERE evt.user_platform IN ("android", "ios")) AS total_sessions_app,
    APPROX_COUNT_DISTINCT(evt.id_session) FILTER(WHERE evt.user_platform = "web_mobile") AS total_sessions_web_mobile,
    APPROX_COUNT_DISTINCT(evt.id_session) FILTER(WHERE evt.user_platform = "web_desktop") AS total_sessions_web_desktop,
    APPROX_COUNT_DISTINCT(evt.id_session) FILTER(WHERE utm.behavior = "organic") AS total_sessions_organic,
    APPROX_COUNT_DISTINCT(evt.id_house) AS total_listings,
    APPROX_COUNT_DISTINCT(evt.current_page) FILTER(WHERE evt.event_type = "condo_page_viewed") AS total_listings_condo,
    APPROX_COUNT_DISTINCT(evt.id_house) FILTER(WHERE evt.business_context = 'sale') AS total_sale_listings,
    APPROX_COUNT_DISTINCT(evt.id_house) FILTER(WHERE evt.business_context = 'sale' AND evt.type_property = 'casa') AS total_sale_listings_house,
    APPROX_COUNT_DISTINCT(evt.id_house) FILTER(WHERE evt.business_context = 'sale' AND evt.type_property = 'apartamento') AS total_sale_listings_apartment,
    APPROX_COUNT_DISTINCT(evt.id_house) FILTER(WHERE evt.business_context = 'sale' AND evt.is_sale_good_price) AS total_sale_listings_good_price,
    APPROX_COUNT_DISTINCT(evt.id_house) FILTER(WHERE evt.business_context = 'sale' AND evt.event_type = 'listing_open_gallery_view') AS total_sale_listings_gallery_viewed,
    APPROX_COUNT_DISTINCT(evt.id_house) FILTER(WHERE evt.business_context = 'sale' AND evt.event_type = 'listing_open_gallery_view'AND evt.gallery_mode = 'full_screen') AS total_sale_listings_gallery_viewed_full_screen,
    APPROX_COUNT_DISTINCT(evt.id_house) FILTER(WHERE evt.business_context = 'sale' AND evt.event_type = 'listing_tab_room_categories_clicked'AND evt.gallery_tab_room IS NOT NULL) AS total_sale_listings_room_clicked,
    APPROX_COUNT_DISTINCT(evt.id_house) FILTER(WHERE evt.business_context = 'sale' AND evt.event_type = 'listing_video_started') AS total_sale_listings_video_started,
    APPROX_COUNT_DISTINCT(evt.id_house) FILTER(WHERE evt.business_context = 'sale' AND evt.event_type = 'pricing_report_section_viewed') AS total_sale_listings_price_report,
    APPROX_COUNT_DISTINCT(evt.id_house) FILTER(WHERE evt.business_context = 'sale' AND evt.event_type = 'pricing_report_section_viewed' AND evt.price_tier = 'dark_green') AS total_sale_listings_price_tier_dark_green,
    APPROX_COUNT_DISTINCT(evt.id_house) FILTER(WHERE evt.business_context = 'sale' AND evt.event_type = 'pricing_report_section_viewed' AND evt.price_tier = 'green') AS total_sale_listings_price_tier_green,
    APPROX_COUNT_DISTINCT(evt.id_house) FILTER(WHERE evt.business_context = 'sale' AND evt.event_type = 'pricing_report_section_viewed' AND evt.price_tier = 'yellow') AS total_sale_listings_price_tier_yellow,
    APPROX_COUNT_DISTINCT(evt.id_house) FILTER(WHERE evt.business_context = 'sale' AND evt.event_type = 'pricing_report_section_viewed' AND evt.price_tier = 'red') AS total_sale_listings_price_tier_red,
    APPROX_COUNT_DISTINCT(evt.id_house) FILTER(WHERE evt.business_context = 'sale' AND evt.event_type = 'mtgsimulator_initial_page_viewed') AS total_sale_listings_payment_simulation,
    APPROX_COUNT_DISTINCT(evt.id_house) FILTER(WHERE evt.business_context = 'sale' AND evt.event_type IN ('listing_favorite_intent', 'listing_favorite_set')) AS total_sale_listings_liked,
    APPROX_COUNT_DISTINCT(evt.id_house) FILTER(WHERE evt.business_context = 'sale' AND evt.event_type = 'share_listing') AS total_sale_listings_shared,
    APPROX_COUNT_DISTINCT(evt.id_house) FILTER(WHERE evt.business_context = 'sale' AND evt.event_type = 'visit_intent_clicked') AS total_sale_listings_visit_intent,
    SUM(COALESCE(evt.total_filters_applied, 0)) FILTER(WHERE evt.business_context = 'sale' AND evt.event_type = 'apply_filters') AS total_sale_events_filter_applied,
    CAST(ROUND(APPROX_PERCENTILE(evt.sale_price, 0.5, 100) FILTER(WHERE evt.business_context = 'sale' AND evt.sale_price BETWEEN 10000 AND 20000000 AND evt.sale_price IS NOT NULL), 0) AS DOUBLE) AS price,
    CAST(ROUND(APPROX_PERCENTILE(evt.sale_price_maximum, 0.5, 100) FILTER(WHERE evt.business_context = 'sale' AND evt.is_sale_price_filtered AND evt.sale_price_maximum BETWEEN 10000 AND 20000000), 0) AS DOUBLE) AS price_filtered,
    CAST(ROUND(APPROX_PERCENTILE(evt.area_m2, 0.5, 100) FILTER(WHERE evt.business_context = 'sale' AND evt.area_m2 BETWEEN 5 AND 5000), 0) AS DOUBLE) AS area_m2,
    MAKE_DATE(evt.year, evt.month, evt.day) AS dt_snapshot,
    evt.year,
    evt.month,
    evt.day
FROM
  datalake_amplitude_agents_app.agents_search_events AS evt
LEFT JOIN
  utms utm
    ON utm.utm_source = evt.utm_source
    AND utm.utm_medium = evt.utm_medium
WHERE
    MAKE_DATE(evt.year, evt.month, evt.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND evt.event_type IN (
        'home_page_viewed',
        'home_3rd_section_viewed',
        'home_4th_section_viewed',
        'home_5th_section_viewed',
        'appbar_link_clicked',
        'search_page_viewed',
        'search_results_page_viewed',
        'listing_page_viewed',
        'listing_sectionexpanded_viewed',
        'apply_filters',
        'login_confirmation_viewed',
        'listing_favorite_intent',
        'listing_favorite_set',
        'share_listing',
        'alert_subscription_confirmed',
        'visit_intent_clicked',
        'schedule_page_viewed',
        'tts_form_page_viewed',
        'pricing_report_section_viewed',
        'mtgsimulator_initial_page_viewed',
        'listing_open_gallery_view',
        'listing_tab_room_categories_clicked',
        'listing_video_started',
        'condo_page_viewed',
        'consorcio_banner_cta_clicked',
        'mtgsimulator_simulationresult_viewed',
        'mortgage_calculator.consorcio_banner_cta_clicked',
        'consorcio.page_viewed',
        'consorcio.cta_clicked',
        'consorcio.specialist_form_viewed'
    )
GROUP BY ALL