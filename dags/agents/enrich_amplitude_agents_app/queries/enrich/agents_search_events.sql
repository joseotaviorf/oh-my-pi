WITH events AS (
    SELECT
        CAST(e.id_user AS BIGINT) AS id_user,
        e.id_app,
        e.city,
        GET_JSON_OBJECT(e.user_properties, '$.platform') AS platform,
        GET_JSON_OBJECT(e.event_properties, '$.webview_origin') AS web_view_origin,
        e.os_name,
        e.event_type,
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
        AND e.id_user IS NOT NULL
        AND e.event_type in (
            'login_page_viewed',
            'login_form_submitted',
            'login_confirmation_viewed',
            'search_page_viewed',
            'listing_page_viewed',
            'share_listing',
            'favorites_list_page_viewed'
        )
)
SELECT
    e.id_user,
    e.id_app,
    e.city,
    e.platform,
    e.os_name,
    e.event_type,
    e.user_properties,
    e.event_properties,
    adbcs.business_context = 'SALE' AS is_sale_agent,
    adbcs.business_context = 'RENT' AS is_rent_agent,
    e.ts_event,
    e.year,
    e.month,
    e.day
FROM  
    events AS e
JOIN
    datalake_ebdb_agents.business_context AS adbcs
        ON adbcs.id_user = e.id_user
        AND e.ts_event BETWEEN adbcs.dt_started AND adbcs.dt_ended
WHERE
    e.web_view_origin = 'Agents App'