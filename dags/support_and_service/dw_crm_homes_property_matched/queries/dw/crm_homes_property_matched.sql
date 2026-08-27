-- Incremental hourly load. The run window is [{load_start_date}, {load_end_date}),
-- so re-running the same interval reproduces exactly the same rows (idempotent);
-- no CURRENT_TIMESTAMP is used anywhere.
--
-- The source partition filter uses MAKE_DATE(year, month, day) against the window
-- dates so Spark prunes to the one or two calendar-day partitions the window spans.
-- Those source partitions are read in full so daily_entry_count stays a true
-- per-day counter; the hour window is only applied afterwards, in window_events.
-- Ranking ascending by ts_event means an earlier event's rank never changes when
-- later events arrive, which keeps the counter stable across reruns.
WITH ranked_events AS (
    SELECT
        transactional.id_event,
        transactional.id_person,
        transactional.id_user,
        transactional.id_entity,
        transactional.id_house,
        transactional.application,
        transactional.journey_step,
        transactional.event_name,
        transactional.ts_event,
        transactional.event_properties,
        ROW_NUMBER() OVER (
            PARTITION BY
                transactional.id_user,
                DATE(transactional.ts_event)
            ORDER BY
                transactional.ts_event ASC
        ) AS daily_entry_count
    FROM
        datalake_cdp_clean.transactional AS transactional
    WHERE
        transactional.event_name = 'homes_property_matched'
        AND MAKE_DATE(transactional.year, transactional.month, transactional.day)
            BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
window_events AS (
    SELECT
        ranked_events.*
    FROM
        ranked_events AS ranked_events
    WHERE
        ranked_events.ts_event >= TIMESTAMP('{load_start_date}')
        AND ranked_events.ts_event < TIMESTAMP('{load_end_date}')
),
extracted_data AS (
    SELECT
        window_events.id_event,
        window_events.id_person,
        window_events.id_user,
        window_events.id_entity,
        window_events.id_house,
        window_events.application,
        window_events.journey_step,
        window_events.event_name,
        window_events.ts_event,
        window_events.daily_entry_count,
        GET_JSON_OBJECT(window_events.event_properties, '$.listingUrl') AS url_base,
        GET_JSON_OBJECT(window_events.event_properties, '$.businessContext') AS b_context,
        GET_JSON_OBJECT(window_events.event_properties, '$.alertId') AS alert_id,
        GET_JSON_OBJECT(window_events.event_properties, '$.houseId') AS event_house_id,
        GET_JSON_OBJECT(window_events.event_properties, '$.area') AS event_area,
        GET_JSON_OBJECT(window_events.event_properties, '$.bedrooms') AS event_bedrooms,
        GET_JSON_OBJECT(window_events.event_properties, '$.bathrooms') AS event_bathrooms,
        GET_JSON_OBJECT(window_events.event_properties, '$.suites') AS event_suites,
        GET_JSON_OBJECT(window_events.event_properties, '$.parkingSpaces') AS event_parking_spaces,
        GET_JSON_OBJECT(window_events.event_properties, '$.totalCost') AS event_total_cost,
        GET_JSON_OBJECT(window_events.event_properties, '$.city') AS event_city,
        GET_JSON_OBJECT(window_events.event_properties, '$.regionName') AS event_region_name,
        GET_JSON_OBJECT(window_events.event_properties, '$.address') AS event_address,
        GET_JSON_OBJECT(window_events.event_properties, '$.iosListingDeeplink') AS event_ios_listing_deeplink,
        GET_JSON_OBJECT(window_events.event_properties, '$.coverImage') AS event_cover_image,
        GET_JSON_OBJECT(window_events.event_properties, '$.shortId') AS event_short_id,
        GET_JSON_OBJECT(window_events.event_properties, '$.rent') AS event_rent,
        GET_JSON_OBJECT(window_events.event_properties, '$.salePrice') AS event_sale_price,
        GET_JSON_OBJECT(window_events.event_properties, '$.condoIptu') AS event_condo_iptu,
        GET_JSON_OBJECT(window_events.event_properties, '$.propertyType') AS event_property_type,
        GET_JSON_OBJECT(window_events.event_properties, '$.searchWithFiltersUrl') AS event_search_with_filters_url,
        GET_JSON_OBJECT(window_events.event_properties, '$.alertRegionName') AS event_alert_region_name,
        GET_JSON_OBJECT(window_events.event_properties, '$.conditions.priceMax') AS event_conditions_price_max,
        GET_JSON_OBJECT(window_events.event_properties, '$.conditions.areaMin') AS event_conditions_area_min,
        GET_JSON_OBJECT(window_events.event_properties, '$.conditions.areaMax') AS event_conditions_area_max,
        GET_JSON_OBJECT(window_events.event_properties, '$.conditions.houseType') AS event_conditions_house_type,
        GET_JSON_OBJECT(window_events.event_properties, '$.conditions.bedrooms') AS event_conditions_bedrooms,
        GET_JSON_OBJECT(window_events.event_properties, '$.conditions.parkingSpaces') AS event_conditions_parking_spaces,
        GET_JSON_OBJECT(window_events.event_properties, '$.conditions.amenities') AS event_conditions_amenities,
        GET_JSON_OBJECT(window_events.event_properties, '$.subscriptions.whatsapp') AS event_subs_whatsapp,
        GET_JSON_OBJECT(window_events.event_properties, '$.subscriptions.email') AS event_subs_email,
        GET_JSON_OBJECT(window_events.event_properties, '$.subscriptions.push') AS event_subs_push,
        GET_JSON_OBJECT(window_events.event_properties, '$.egw_device_id') AS event_egw_device_id,
        GET_JSON_OBJECT(window_events.event_properties, '$.egw_session_id') AS event_egw_session_id,
        GET_JSON_OBJECT(window_events.event_properties, '$.egw_user_agent') AS event_egw_user_agent,
        GET_JSON_OBJECT(window_events.event_properties, '$.egw_ip') AS event_egw_ip,
        GET_JSON_OBJECT(window_events.event_properties, '$.egw_platform') AS event_egw_platform,
        GET_JSON_OBJECT(window_events.event_properties, '$.egw_apps_flyer_id') AS event_egw_apps_flyer_id,
        GET_JSON_OBJECT(window_events.event_properties, '$.egw_referrer_domain') AS event_egw_referrer_domain,
        GET_JSON_OBJECT(window_events.event_properties, '$.egw_initial_referrer_domain') AS event_egw_initial_referrer_domain,
        GET_JSON_OBJECT(window_events.event_properties, '$.egw_utm_source') AS event_egw_utm_source,
        GET_JSON_OBJECT(window_events.event_properties, '$.egw_utm_medium') AS event_egw_utm_medium,
        GET_JSON_OBJECT(window_events.event_properties, '$.egw_utm_campaign') AS event_egw_utm_campaign,
        GET_JSON_OBJECT(window_events.event_properties, '$.egw_initial_utm_source') AS event_egw_initial_utm_source,
        GET_JSON_OBJECT(window_events.event_properties, '$.egw_initial_utm_medium') AS event_egw_initial_utm_medium,
        GET_JSON_OBJECT(window_events.event_properties, '$.egw_initial_utm_campaign') AS event_egw_initial_utm_campaign,
        GET_JSON_OBJECT(window_events.event_properties, '$.egw_gclid') AS event_egw_gclid,
        GET_JSON_OBJECT(window_events.event_properties, '$.egw_fbclid') AS event_egw_fbclid,
        GET_JSON_OBJECT(window_events.event_properties, '$.alertCreationDate') AS alert_creation_date
    FROM
        window_events AS window_events
),
matched_users AS (
    SELECT
        extracted_data.*,
        REGEXP_REPLACE(users.telefone_principal, '^\\+', '') AS telefone_principal,
        users.email
    FROM
        extracted_data AS extracted_data
    INNER JOIN
        dw_public.dim_user AS users
        ON extracted_data.id_user = users.sk_user
    WHERE
        users.telefone_principal IS NOT NULL
),
urls AS (
    SELECT
        matched_users.*,
        CONCAT(
            matched_users.url_base,
            '?utm_medium=push&utm_source=salesforce&utm_campaign=ZEBRA.',
            LOWER(matched_users.b_context),
            '.eng.org.na.d.push.salesforce.Homes.Salesforce.Push1&utm_term=Push1.24.07&id=',
            CAST(matched_users.id_user AS STRING),
            '&alert=',
            matched_users.alert_id
        ) AS listing_url_push1,
        CONCAT(
            matched_users.url_base,
            '?utm_medium=push&utm_source=salesforce&utm_campaign=ZEBRA.',
            LOWER(matched_users.b_context),
            '.eng.org.na.d.push.salesforce.Homes.Salesforce.Push2&utm_term=Push2.24.07&id=',
            CAST(matched_users.id_user AS STRING),
            '&alert=',
            matched_users.alert_id
        ) AS listing_url_push2,
        CONCAT(
            matched_users.url_base,
            '?utm_medium=push&utm_source=salesforce&utm_campaign=ZEBRA.',
            LOWER(matched_users.b_context),
            '.eng.org.na.d.push.salesforce.Homes.Salesforce.Push3&utm_term=Push3.24.07&id=',
            CAST(matched_users.id_user AS STRING),
            '&alert=',
            matched_users.alert_id
        ) AS listing_url_push3,
        CONCAT(
            matched_users.url_base,
            '?utm_medium=whatsapp&utm_source=salesforce&utm_campaign=ZEBRA.',
            LOWER(matched_users.b_context),
            '.eng.org.na.d.whatsapp.salesforce.Homes.Salesforce.whatsapp_sfmc.24.07&utm_term=whatsapp_sfmc&id=',
            CAST(matched_users.id_user AS STRING),
            '&alert=',
            matched_users.alert_id
        ) AS listing_url_wppsfmc,
        CONCAT(
            matched_users.url_base,
            '?utm_medium=whatsapp&utm_source=salesforce&utm_campaign=ZEBRA.',
            LOWER(matched_users.b_context),
            '.eng.org.na.d.whatsapp.salesforce.Homes.Salesforce.whatsapp_twilio.24.07&utm_term=whatsapp_twilio&id=',
            CAST(matched_users.id_user AS STRING),
            '&alert=',
            matched_users.alert_id
        ) AS listing_url_wpp
    FROM
        matched_users AS matched_users
)
SELECT
    urls.id_event,
    urls.id_person,
    urls.id_user,
    urls.telefone_principal,
    urls.email,
    urls.id_entity,
    urls.id_house,
    urls.application,
    urls.journey_step,
    urls.event_name,
    urls.event_house_id,
    urls.alert_id AS event_alert_id,
    urls.b_context AS event_business_context,
    urls.event_area,
    urls.event_bedrooms,
    urls.event_bathrooms,
    urls.event_suites,
    urls.event_parking_spaces,
    urls.event_total_cost,
    urls.event_city,
    urls.event_region_name,
    urls.event_address,
    urls.url_base AS event_listing_url,
    urls.event_ios_listing_deeplink,
    urls.event_cover_image,
    urls.event_short_id,
    urls.event_rent,
    urls.event_sale_price,
    urls.event_condo_iptu,
    urls.event_property_type,
    urls.event_search_with_filters_url,
    urls.event_alert_region_name,
    urls.event_conditions_price_max,
    urls.event_conditions_area_min,
    urls.event_conditions_area_max,
    urls.event_conditions_house_type,
    urls.event_conditions_bedrooms,
    urls.event_conditions_parking_spaces,
    urls.event_conditions_amenities,
    urls.listing_url_push1 AS event_listing_url_push1,
    urls.listing_url_push2 AS event_listing_url_push2,
    urls.listing_url_push3 AS event_listing_url__push3,
    urls.listing_url_wppsfmc AS event_listing_url_wppsfmc,
    urls.listing_url_wpp AS event_listing_url_wpp,
    REGEXP_REPLACE(urls.listing_url_wppsfmc, '^https://quin.to/', '') AS event_listing_url_wppsfmc_cta,
    REGEXP_REPLACE(urls.listing_url_wpp, '^https://quin.to/', '') AS event_listing_url_wpp_cta,
    urls.event_subs_whatsapp,
    urls.event_subs_email,
    urls.event_subs_push,
    urls.event_egw_device_id,
    urls.event_egw_session_id,
    urls.event_egw_user_agent,
    urls.event_egw_ip,
    urls.event_egw_platform,
    urls.event_egw_apps_flyer_id,
    urls.event_egw_referrer_domain,
    urls.event_egw_initial_referrer_domain,
    urls.event_egw_utm_source,
    urls.event_egw_utm_medium,
    urls.event_egw_utm_campaign,
    urls.event_egw_initial_utm_source,
    urls.event_egw_initial_utm_medium,
    urls.event_egw_initial_utm_campaign,
    urls.event_egw_gclid,
    urls.event_egw_fbclid,
    DATE_FORMAT(urls.ts_event, 'yyyy-MM-dd HH:mm:ss') AS ts_event,
    urls.daily_entry_count,
    DATE_FORMAT(TO_TIMESTAMP(urls.alert_creation_date), 'yyyy-MM-dd HH:mm:ss') AS alert_creation_date,
    DATE(urls.ts_event) AS partition_date,
    HOUR(urls.ts_event) AS partition_hour
FROM
    urls AS urls
