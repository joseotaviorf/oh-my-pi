WITH events AS (
    SELECT
        CAST(e.id_user AS BIGINT) AS id_user,
        e.id_app,
        e.id_session,
        e.id_amplitude,
        e.id_event,
        e.city,
        e.os_name,
        e.event_type,
        e.platform,
        e.device_type,
        e.user_properties,
        e.event_properties,
        e.ts_event,
        e.year,
        e.month,
        e.day
    FROM
        datalake_amplitude_clean.events AS e
    WHERE
        MAKE_DATE(e.year, e.month, e.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND e.id_app = 170698
        AND e.event_type in (
            'login_page_viewed',
            'login_form_submitted',
            'login_confirmation_viewed',
            'search_page_viewed',
            'listing_page_viewed',
            'share_listing',
            'favorites_list_page_viewed',
            'shopwindow_onboarding_viewed',
            'shopwindow_onboarding_step_completed',
            'shopwindow_share_listing_onboarding_viewed',
            'shopwindow_share_listing_onboarding_action_button_clicked',
            'shopwindow_add_to_list_onboarding_viewed',
            'shopwindow_add_to_list_onboarding_action_button_clicked',
            'shopwindow_listing_shared',
            'add_to_shopwindow_intent_page_view',
            'add_to_shopwindow_success_page_view',
            'create_new_shopwindow_button_clicked',
            'key_holder_lock_drawer_viewed',
            'home_page_viewed',
            'home_3rd_section_viewed',
            'home_4th_section_viewed',
            'home_5th_section_viewed',
            'appbar_link_clicked',
            'search_results_page_viewed',
            'listing_sectionexpanded_viewed',
            'apply_filters',
            'listing_favorite_intent',
            'listing_favorite_set',
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
),
business_context AS (
    SELECT
        CAST(bc.id_user AS BIGINT) AS id_user,
        MAX(CASE WHEN bc.business_context = 'SALE' THEN true ELSE false END) AS is_sale_agent,
        MAX(CASE WHEN bc.business_context = 'RENT' THEN true ELSE false END) AS is_rent_agent,
        ax.year AS year,
        ax.month AS month,
        ax.day AS day
    FROM
        datalake_ebdb_agents.business_context AS bc
    JOIN 
        datalake_quintoandar.aux_date AS ax
            ON ax.date BETWEEN bc.dt_started AND bc.dt_ended
    WHERE 
        ax.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY ALL
)
SELECT
    e.id_app,
    e.id_session,
    e.id_amplitude,
    e.id_event,
    COALESCE(e.id_user, TRY_CAST(GET_JSON_OBJECT(e.user_properties, '$.user_id') AS BIGINT)) AS id_user,
    TRY_CAST(GET_JSON_OBJECT(e.event_properties, '$.house_id') AS BIGINT) AS id_house,
    TRY_CAST(GET_JSON_OBJECT(e.event_properties, '$.sub_region_id') AS BIGINT) AS id_region,
    e.city,
    e.os_name,
    e.event_type,
    e.device_type AS device,
    e.platform,
    GET_JSON_OBJECT(e.user_properties, '$.platform') AS user_platform,
    TRIM(LOWER(COALESCE(
        GET_JSON_OBJECT(e.user_properties, '$.utm_source'), 
        GET_JSON_OBJECT(e.user_properties, '$.initial_utm_source')
    ))) AS utm_source,
    TRIM(LOWER(COALESCE(
        GET_JSON_OBJECT(e.user_properties, '$.utm_medium'), 
        GET_JSON_OBJECT(e.user_properties, '$.initial_utm_medium')
    ))) AS utm_medium,
    TRIM(LOWER(COALESCE(
        GET_JSON_OBJECT(e.user_properties, '$.utm_campaign'), 
        GET_JSON_OBJECT(e.user_properties, '$.initial_utm_campaign')
    ))) AS utm_campaign,
    LOWER(GET_JSON_OBJECT(e.event_properties, '$.webview_origin')) AS web_view_origin,
    LOWER(GET_JSON_OBJECT(e.event_properties, '$.gallery_mode')) AS gallery_mode,
    LOWER(GET_JSON_OBJECT(e.event_properties, '$.tab_name')) AS gallery_tab_room,
    LOWER(GET_JSON_OBJECT(e.event_properties, '$.from_route')) AS lpv_origin,
    LOWER(GET_JSON_OBJECT(e.event_properties, '$.business_context')) AS business_context,
    LOWER(GET_JSON_OBJECT(e.event_properties, '$.search_type')) AS search_type,
    COALESCE(
        GET_JSON_OBJECT(e.event_properties, '$.type_property'), 
        GET_JSON_OBJECT(e.event_properties, '$.initial_type_property')
    ) AS type_property,
    LOWER(GET_JSON_OBJECT(e.event_properties, '$.listing_section')) AS listing_section,
    LOWER(GET_JSON_OBJECT(e.event_properties, '$.current_page')) AS current_page,
    e.user_properties,
    e.event_properties,
    GET_JSON_OBJECT(e.event_properties, '$.color') AS price_tier,
    NULLIF(COALESCE(
        TRY_CAST(GET_JSON_OBJECT(e.event_properties, '$.valor_venda') AS DOUBLE), 
        TRY_CAST(GET_JSON_OBJECT(e.event_properties, '$.sale_price') AS DOUBLE)
    ), 0) AS sale_price,
    NULLIF(COALESCE(
        TRY_CAST(GET_JSON_OBJECT(e.event_properties, '$.filters.salePrice.selectedMin') AS DOUBLE),
        TRY_CAST(GET_JSON_OBJECT(e.event_properties, '$.filter_sale_value_valor_min') AS DOUBLE)
    ), 0) AS sale_price_minimum,
    NULLIF(COALESCE(
        TRY_CAST(GET_JSON_OBJECT(e.event_properties, '$.filters.salePrice.selectedMax') AS DOUBLE),
        TRY_CAST(GET_JSON_OBJECT(e.event_properties, '$.filter_sale_value_valor_max') AS DOUBLE)
    ), 0) AS sale_price_maximum,
    TRY_CAST(GET_JSON_OBJECT(e.event_properties, '$.m2') AS DOUBLE) AS area_m2,
    TRY_CAST(GET_JSON_OBJECT(e.event_properties, '$.nbr_of_categories_applied') AS BIGINT) AS total_filters_applied,
    TRY_CAST(GET_JSON_OBJECT(e.event_properties, '$.filters.salePrice.filterUpdated') AS BOOLEAN) AS is_sale_price_filtered,
    IF(TRIM(LOWER(GET_JSON_OBJECT(e.event_properties, '$.house_tags'))) RLIKE 'issalegoodprice', TRUE, FALSE) AS is_sale_good_price,
    bc.is_sale_agent,
    bc.is_rent_agent,
    e.ts_event,
    e.year,
    e.month,
    e.day
FROM
    events AS e
LEFT JOIN
    business_context AS bc
        ON bc.id_user = e.id_user
        AND bc.year = e.year
        AND bc.month = e.month
        AND bc.day = e.day