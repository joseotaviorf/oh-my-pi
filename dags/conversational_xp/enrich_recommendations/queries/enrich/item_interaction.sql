/*
User interactions for recommendation metrics calculation

Assumptions:
  - Interactions can be of listing page views or similar house clicked
  - We only consider listing page views for houses that are active at
    interaction time. This logic happens on the recommendations_catalog
    inner join.
*/
WITH listing_page_views AS (
    SELECT
        ep_house_id AS id_item,
        'house' AS type_item,
        'listing-page-viewed' AS interaction_type,
        ts_event AS ts_interaction,
        DATE(ts_event) AS dt_interaction,
        year,
        month,
        day,
        COALESCE(id_user, id_amplitude) AS id_user,
        LOWER(
            GET_JSON_OBJECT(
                event_properties, '$.business_context'
            )
        ) AS business_context
    FROM
        datalake_amplitude_clean.170698_listing_page_viewed_events AS events
    INNER JOIN
        datalake_recommendations.recommendation_catalog AS recommendation_catalog
        ON
            recommendation_catalog.business_context
            = LOWER(GET_JSON_OBJECT(event_properties, '$.business_context'))
            AND recommendation_catalog.id_item = ep_house_id
            AND recommendation_catalog.type_item = 'house'
    WHERE
        GET_JSON_OBJECT(event_properties, '$.business_context') IS NOT NULL
        AND ts_event BETWEEN recommendation_catalog.ts_status_started AND recommendation_catalog.ts_status_ended
        AND MAKE_DATE(events.year, events.month, events.day)
          BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
        AND YEAR(ts_event) = year
        AND MONTH(ts_event) = month
        AND DAY(ts_event) = day
),

similar_carousel_house_clicks AS (
    SELECT
        'house' AS type_item,
        'similar-house-clicked' AS interaction_type,
        ts_event AS ts_interaction,
        DATE(ts_event) AS dt_interaction,
        year,
        month,
        day,
        COALESCE(id_user, id_amplitude) AS id_user,
        CAST(
            GET_JSON_OBJECT(event_properties, '$.house_id_target') AS INT
        ) AS id_item,
        LOWER(
            GET_JSON_OBJECT(
                event_properties, '$.business_context'
            )
        ) AS business_context
    FROM
        datalake_amplitude_clean.events AS events
    WHERE
        event_type IN (
            'listing_similar_clicked',
            'listing_similar_clicked_native'
        )
        AND id_app = 170698
        AND GET_JSON_OBJECT(event_properties, '$.business_context') IS NOT NULL
        AND GET_JSON_OBJECT(event_properties, '$.house_id_target') IS NOT NULL
        AND MAKE_DATE(events.year, events.month, events.day)
            BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
        AND YEAR(ts_event) = year
        AND MONTH(ts_event) = month
        AND DAY(ts_event) = day
),

house_favorited AS (
    SELECT
        'house' AS type_item,
        'house-favorited' AS interaction_type,
        ts_event AS ts_interaction,
        DATE(ts_event) AS dt_interaction,
        year,
        month,
        day,
        COALESCE(id_user, id_amplitude) AS id_user,
        CAST(
            GET_JSON_OBJECT(event_properties, '$.house_id') AS INT
        ) AS id_item,
        LOWER(
            GET_JSON_OBJECT(
                event_properties, '$.business_context'
            )
        ) AS business_context
    FROM datalake_amplitude_clean.events AS events
    WHERE
        event_type = 'listing_favorite_set'
        AND id_app = 170698
        AND GET_JSON_OBJECT(event_properties, '$.business_context') IS NOT NULL
        AND MAKE_DATE(events.year, events.month, events.day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
        AND YEAR(ts_event) = year
        AND MONTH(ts_event) = month
        AND DAY(ts_event) = day
),

rent_flows AS (
    SELECT
        'house' AS type_item,
        'rent-flow-created' AS interaction_type,
        id_house AS id_item,
        id_client AS id_user,
        'rent' AS business_context,
        ts_created AS ts_interaction,
        DATE(ts_created) AS dt_interaction,
        EXTRACT(YEAR FROM ts_created) AS year,
        EXTRACT(MONTH FROM ts_created) AS month,
        EXTRACT(DAY FROM ts_created) AS day
    FROM datalake_ebdb_clean.rent_flow
    WHERE
        ts_created BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
),

sale_flows AS (
    SELECT
        'house' AS type_item,
        'sale-flow-created' AS interaction_type,
        id_house AS id_item,
        id_buyer AS id_user,
        'sale' AS business_context,
        ts_first_event AS ts_interaction,
        DATE(ts_first_event) AS dt_interaction,
        EXTRACT(YEAR FROM ts_first_event) AS year,
        EXTRACT(MONTH FROM ts_first_event) AS month,
        EXTRACT(DAY FROM ts_first_event) AS day
    FROM datalake_sale_flows.sale_flow
    WHERE
        ts_first_event BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
)

SELECT
    id_user,
    id_item,
    type_item,
    interaction_type,
    business_context,
    ts_interaction,
    dt_interaction,
    year,
    month,
    day
FROM listing_page_views
UNION ALL
SELECT
    id_user,
    id_item,
    type_item,
    interaction_type,
    business_context,
    ts_interaction,
    dt_interaction,
    year,
    month,
    day
FROM similar_carousel_house_clicks
UNION ALL
SELECT
    id_user,
    id_item,
    type_item,
    interaction_type,
    business_context,
    ts_interaction,
    dt_interaction,
    year,
    month,
    day
FROM house_favorited
UNION ALL
SELECT
    id_user,
    id_item,
    type_item,
    interaction_type,
    business_context,
    ts_interaction,
    dt_interaction,
    year,
    month,
    day
FROM rent_flows
UNION ALL
SELECT
    id_user,
    id_item,
    type_item,
    interaction_type,
    business_context,
    ts_interaction,
    dt_interaction,
    year,
    month,
    day
FROM sale_flows
