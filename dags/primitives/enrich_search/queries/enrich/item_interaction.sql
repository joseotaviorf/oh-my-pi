
WITH visit_intent_clicked AS (
  SELECT
        GET_JSON_OBJECT(
                events.event_properties, '$.house_id'
            )  AS id_item,
        'house' AS type_item,
        'visit-intent-clicked' AS interaction_type,
        search.id_search AS id_search,
        search.search_rendering_type AS search_rendering_type,
        events.ts_event AS ts_interaction,
        DATE(events.ts_event) AS dt_interaction,
        events.year AS year,
        events.month AS month,
        events.day AS day,
        COALESCE(events.id_user, events.id_amplitude) AS id_user,
        LOWER(
            GET_JSON_OBJECT(
                events.event_properties, '$.business_context'
            )
        ) AS business_context
    FROM
        datalake_amplitude_clean_staging.170698_visit_intent_clicked_events AS events
    INNER JOIN
        datalake_recommendations.recommendation_catalog AS recommendation_catalog
        ON
        recommendation_catalog.business_context
        = LOWER(GET_JSON_OBJECT(events.event_properties, '$.business_context'))
        AND recommendation_catalog.id_item
        = GET_JSON_OBJECT( events.event_properties, '$.house_id')
        AND recommendation_catalog.type_item = 'house'
    INNER JOIN datalake_search_session_event.search_session_event AS search
        ON coalesce(search.id_user, search.id_amplitude)
        = coalesce(events.id_user, events.id_amplitude)
        AND GET_JSON_OBJECT(
                events.event_properties, '$.house_id'
            ) = search.id_house
        AND LOWER(GET_JSON_OBJECT(events.event_properties, '$.business_context'))
        = LOWER(search.business_context)
        AND MAKE_DATE(search.year, search.month, search.day)
        BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
        AND search.business_context IS NOT NULL
        AND search.id_search IS NOT NULL
        AND search.search_rendering_type != "N/A"
        AND events.ts_event >= search.ts_event
    WHERE
        YEAR(events.ts_event) = {year}
        AND MONTH(events.ts_event) =  {month}
        AND DAY(events.ts_event) = {day}
        AND GET_JSON_OBJECT(events.event_properties, '$.business_context') IS NOT NULL
        AND events.ts_event BETWEEN recommendation_catalog.ts_status_started
        AND recommendation_catalog.ts_status_ended
    QUALIFY ROW_NUMBER() OVER (PARTITION BY search.id_house,
    COALESCE(events.id_user, events.id_amplitude)
        ORDER BY search.ts_event DESC) = 1
),
visitblock_alert_clicked AS (
    SELECT
        GET_JSON_OBJECT(
                event_properties, '$.house_id'
            )  AS id_item,
        'house' AS type_item,
        'visitblock-alert-clicked' AS interaction_type,
        search.id_search AS id_search,
        search.search_rendering_type AS search_rendering_type,
        events.ts_event AS ts_interaction,
        DATE(events.ts_event) AS dt_interaction,
        events.year AS year,
        events.month AS month,
        events.day AS day,
        COALESCE(events.id_user, events.id_amplitude) AS id_user,
        LOWER(
            GET_JSON_OBJECT(
                event_properties, '$.business_context'
            )
        ) AS business_context
    FROM
        datalake_amplitude_clean_staging.170698_visitblock_alert_clicked_events AS events
    INNER JOIN
        datalake_recommendations.recommendation_catalog AS recommendation_catalog
        ON
            recommendation_catalog.business_context
            = LOWER(GET_JSON_OBJECT(event_properties, '$.business_context'))
            AND recommendation_catalog.id_item
            = GET_JSON_OBJECT( event_properties, '$.house_id')
            AND recommendation_catalog.type_item = 'house'
    INNER JOIN datalake_search_session_event.search_session_event AS search
        ON coalesce(search.id_user, search.id_amplitude)
        = coalesce(events.id_user, events.id_amplitude)
        AND GET_JSON_OBJECT(
                events.event_properties, '$.house_id'
            ) = search.id_house
        AND LOWER(GET_JSON_OBJECT(events.event_properties, '$.business_context'))
        = LOWER(search.business_context)
        AND MAKE_DATE(search.year, search.month, search.day)
        BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
        AND search.business_context IS NOT NULL
        AND search.id_search IS NOT NULL
        AND search.search_rendering_type != "N/A"
        AND events.ts_event >= search.ts_event
    WHERE
        YEAR(events.ts_event) = {year}
        AND MONTH(events.ts_event) = {month}
        AND DAY(events.ts_event) =  {day}
        AND GET_JSON_OBJECT(event_properties, '$.business_context') IS NOT NULL
        AND events.ts_event BETWEEN recommendation_catalog.ts_status_started AND recommendation_catalog.ts_status_ended
    QUALIFY ROW_NUMBER() OVER (PARTITION BY search.id_house,
    COALESCE(events.id_user, events.id_amplitude)
        ORDER BY search.ts_event DESC) = 1
),
listing_favorite_intent AS (
  SELECT
        GET_JSON_OBJECT(
                event_properties, '$.house_id'
            ) AS id_item,
        'house' AS type_item,
        'listing-favorite-intent' AS interaction_type,
        search.id_search AS id_search,
        search.search_rendering_type AS search_rendering_type,
        events.ts_event AS ts_interaction,
        DATE(events.ts_event) AS dt_interaction,
        events.year AS year,
        events.month AS month,
        events.day AS day,
        COALESCE(events.id_user, events.id_amplitude) AS id_user,
        LOWER(
            GET_JSON_OBJECT(
                event_properties, '$.business_context'
            )
        ) AS business_context
    FROM
        datalake_amplitude_clean_staging.170698_listing_favorite_intent_events AS events
    INNER JOIN
        datalake_recommendations.recommendation_catalog AS recommendation_catalog
        ON
            recommendation_catalog.business_context
            = LOWER(GET_JSON_OBJECT(event_properties, '$.business_context'))
            AND recommendation_catalog.id_item
            = GET_JSON_OBJECT( event_properties, '$.house_id')
            AND recommendation_catalog.type_item = 'house'
    INNER JOIN datalake_search_session_event.search_session_event AS search
        ON coalesce(search.id_user, search.id_amplitude)
        = coalesce(events.id_user, events.id_amplitude)
        AND GET_JSON_OBJECT(
                events.event_properties, '$.house_id'
            ) = search.id_house
        AND LOWER(GET_JSON_OBJECT(events.event_properties, '$.business_context'))
        = LOWER(search.business_context)
        AND MAKE_DATE(search.year, search.month, search.day)
        BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
        AND search.business_context IS NOT NULL
        AND search.id_search IS NOT NULL
        AND search.search_rendering_type != "N/A"
        AND events.ts_event >= search.ts_event
    WHERE
        YEAR(events.ts_event) = {year}
        AND MONTH(events.ts_event) = {month}
        AND DAY(events.ts_event) = {day}
        AND GET_JSON_OBJECT(event_properties, '$.business_context') IS NOT NULL
        AND events.ts_event BETWEEN recommendation_catalog.ts_status_started AND recommendation_catalog.ts_status_ended
    QUALIFY ROW_NUMBER() OVER (PARTITION BY search.id_house,
    COALESCE(events.id_user, events.id_amplitude)
        ORDER BY search.ts_event DESC) = 1
),
 share_listing AS (
  SELECT
        GET_JSON_OBJECT(
                event_properties, '$.house_id'
            )  AS id_item,
        'house' AS type_item,
        'share-listing' AS interaction_type,
        search.id_search AS id_search,
        search.search_rendering_type AS search_rendering_type,
        events.ts_event AS ts_interaction,
        DATE(events.ts_event) AS dt_interaction,
        events.year AS year,
        events.month AS month,
        events.day AS day,
        COALESCE(events.id_user, events.id_amplitude) AS id_user,
        LOWER(
            GET_JSON_OBJECT(
                event_properties, '$.business_context'
            )
        ) AS business_context
    FROM
        datalake_amplitude_clean_staging.170698_share_listing_events AS events
    INNER JOIN
        datalake_recommendations.recommendation_catalog AS recommendation_catalog
        ON
        recommendation_catalog.business_context
        = LOWER(GET_JSON_OBJECT(event_properties, '$.business_context'))
        AND recommendation_catalog.id_item
        = GET_JSON_OBJECT( event_properties, '$.house_id')
        AND recommendation_catalog.type_item = 'house'
    INNER JOIN datalake_search_session_event.search_session_event AS search
        ON coalesce(search.id_user, search.id_amplitude)
        = coalesce(events.id_user, events.id_amplitude)
        AND GET_JSON_OBJECT(
                events.event_properties, '$.house_id'
            ) = search.id_house
        AND LOWER(GET_JSON_OBJECT(events.event_properties, '$.business_context'))
        = LOWER(search.business_context)
        AND MAKE_DATE(search.year, search.month, search.day)
        BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
        AND search.business_context IS NOT NULL
        AND search.id_search IS NOT NULL
        AND search.search_rendering_type != "N/A"
        AND events.ts_event >= search.ts_event
    WHERE
        YEAR(events.ts_event) = {year}
        AND MONTH(events.ts_event) =  {month}
        AND DAY(events.ts_event) = {day}
        AND GET_JSON_OBJECT(event_properties, '$.business_context') IS NOT NULL
        AND events.ts_event BETWEEN recommendation_catalog.ts_status_started
        AND recommendation_catalog.ts_status_ended
    QUALIFY ROW_NUMBER() OVER (PARTITION BY search.id_house,
    COALESCE(events.id_user, events.id_amplitude)
        ORDER BY search.ts_event DESC) = 1
),
visitblock_similares_clicked AS (
  SELECT
        GET_JSON_OBJECT(
                event_properties, '$.house_id'
            )  AS id_item,
        'house' AS type_item,
        'visitblock-similares-clicked' AS interaction_type,
        search.id_search AS id_search,
        search.search_rendering_type AS search_rendering_type,
        events.ts_event AS ts_interaction,
        DATE(events.ts_event) AS dt_interaction,
        events.year AS year,
        events.month AS month,
        events.day AS day,
        COALESCE(events.id_user, events.id_amplitude) AS id_user,
        LOWER(
            GET_JSON_OBJECT(
                event_properties, '$.business_context'
            )
        ) AS business_context
    FROM
        datalake_amplitude_clean_staging.170698_visitblock_similares_clicked_events AS events
    INNER JOIN
        datalake_recommendations.recommendation_catalog AS recommendation_catalog
        ON
            recommendation_catalog.business_context
            = LOWER(GET_JSON_OBJECT(event_properties, '$.business_context'))
            AND recommendation_catalog.id_item
            = GET_JSON_OBJECT( event_properties, '$.house_id')
            AND recommendation_catalog.type_item = 'house'
    INNER JOIN datalake_search_session_event.search_session_event AS search
        ON coalesce(search.id_user, search.id_amplitude)
        = coalesce(events.id_user, events.id_amplitude)
        AND GET_JSON_OBJECT(
                events.event_properties, '$.house_id'
            ) = search.id_house
        AND LOWER(GET_JSON_OBJECT(events.event_properties, '$.business_context'))
        = LOWER(search.business_context)
        AND MAKE_DATE(search.year, search.month, search.day)
        BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
        AND search.id_search IS NOT NULL
        AND search.business_context IS NOT NULL
        AND search.id_search IS NOT NULL
        AND search.search_rendering_type != "N/A"
        AND events.ts_event >= search.ts_event
    WHERE
        YEAR(events.ts_event) = {year}
        AND MONTH(events.ts_event) =  {month}
        AND DAY(events.ts_event) = {day}
        AND GET_JSON_OBJECT(event_properties, '$.business_context') IS NOT NULL
        AND events.ts_event BETWEEN recommendation_catalog.ts_status_started
        AND recommendation_catalog.ts_status_ended
    QUALIFY ROW_NUMBER() OVER (PARTITION BY search.id_house,
    COALESCE(events.id_user, events.id_amplitude)
        ORDER BY search.ts_event DESC) = 1
),
proper_offer AS (
SELECT
    rent_flow.id_house AS id_item,
    'proper-offer-submitted' AS interaction_type,
    search.id_search AS id_search,
    search.search_rendering_type AS search_rendering_type,
    'house' AS type_item,
    rent_flow.id_tenant_prospect AS id_user,
    rent_flow.ts_created AS ts_interaction,
    DATE(rent_flow.ts_created) AS dt_interaction,
    "rent" AS business_context,
    year(rent_flow.ts_created) AS year,
    month(rent_flow.ts_created) AS month,
    day(rent_flow.ts_created) AS day
    FROM  datalake_rent_flows.rent_flows AS rent_flow
    INNER JOIN  (
        SELECT id_rent_flow
        FROM datalake_ebdb_clean.offer
        WHERE DATE(ts_created) = DATE('{start_date}')
        AND (offer.original_rent - offer.rent)/ offer.original_rent  < 0.2
        )
        AS offer ON rent_flow.id_rent_flow = offer.id_rent_flow
    INNER JOIN
        datalake_recommendations.recommendation_catalog AS recommendation_catalog
        ON recommendation_catalog.business_context = 'rent'
        AND recommendation_catalog.id_item =  rent_flow.id_house
        AND recommendation_catalog.type_item = 'house'
    INNER JOIN datalake_search_session_event.search_session_event AS search
        ON search.id_user
        = rent_flow.id_tenant_prospect
        AND rent_flow.id_house = search.id_house
        AND LOWER(search.business_context) = 'rent'
        AND search.search_rendering_type != "N/A"
        AND DATE(search.ts_event)
        BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
        AND rent_flow.ts_created >= search.ts_event
    WHERE
        DATE(rent_flow.ts_created) = DATE('{start_date}')
        AND rent_flow.ts_offer_submitted IS NOT NULL
    QUALIFY  ROW_NUMBER() OVER (PARTITION BY rent_flow.id_house,
        rent_flow.id_house
        ORDER BY search.ts_event DESC) = 1
    ),
item_interaction AS(
select
  id_item,
  interaction_type,
  id_search,
  search_rendering_type,
  type_item,
  id_user,
  ts_interaction,
  dt_interaction,
  business_context,
  year,
  month,
  day
FROM visit_intent_clicked
UNION ALL
SELECT
  id_item,
  interaction_type,
  id_search,
  search_rendering_type,
  type_item,
  id_user,
  ts_interaction,
  dt_interaction,
  business_context,
  year,
  month,
  day
FROM visitblock_alert_clicked
UNION ALL
SELECT
  id_item,
  interaction_type,
  id_search,
  search_rendering_type,
  type_item,
  id_user,
  ts_interaction,
  dt_interaction,
  business_context,
  year,
  month,
  day
FROM listing_favorite_intent
UNION ALL
SELECT
  id_item,
  interaction_type,
  id_search,
  search_rendering_type,
  type_item,
  id_user,
  ts_interaction,
  dt_interaction,
  business_context,
  year,
  month,
  day
FROM share_listing
UNION ALL
SELECT
  id_item,
  interaction_type,
  id_search,
  search_rendering_type,
  type_item,
  id_user,
  ts_interaction,
  dt_interaction,
  business_context,
  year,
  month,
  day
FROM  visitblock_similares_clicked
UNION ALL
SELECT
  id_item,
  interaction_type,
  id_search,
  search_rendering_type,
  type_item,
  id_user,
  ts_interaction,
  dt_interaction,
  business_context,
  year,
  month,
  day
FROM proper_offer
)
select * from item_interaction
