-----------------
-- Recs Impressions

WITH recs_impressions_info AS (

-- Only the recset_impression_events has the business context. So we use this as an anchor for the whole query
SELECT
    recset_id,
    recset_id_fix,
    id_user,
    id_amplitude,
    id_session,
    id_device,
    business_context,
    device_type,
    showcase,
    user_properties,
    year,
    month,
    day
FROM
    (
        SELECT
            get_json_object(event_properties, '$.recset_id') AS recset_id,
            -- This is happening because sometimes we have two user ids or more for the same recset_id
            concat(get_json_object(event_properties, '$.recset_id'), '-', id_user) AS recset_id_fix,
            get_json_object(event_properties, '$.showcase') AS showcase,
            id_user,
            id_amplitude,
            id_session,
            id_device,
            get_json_object(event_properties, '$.business_context') AS business_context,
            get_json_object(user_properties, '$.platform') AS device_type,
            user_properties,
            year,
            month,
            day
        FROM datalake_amplitude_clean_staging.170698_recset_impression_events
        WHERE MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
        AND get_json_object(user_properties, '$.country') = 'BR'
        AND id_user IS NOT NULL
        -- This carroussel only has user favourited items. We don't want to include it in our metrics
        AND get_json_object(event_properties, '$.recset_id') NOT IN ("FEED-FAVORITES-RENT", "FEED-FAVORITES-SALE")
    )
GROUP BY recset_id,
         recset_id_fix,
         id_user,
         id_amplitude,
         id_session,
         id_device,
         business_context,
         device_type,
         showcase,
         user_properties,
         year,
         month,
         day
),

recs_impressions AS (

    -- This gets the first viewed rec
    SELECT
    get_json_object(event_properties, '$.recset_id') AS recset_id,
    concat(get_json_object(event_properties, '$.recset_id'), '-', id_user) AS recset_id_fix,
    from_json(get_json_object(event_properties, '$.viewed_house_list'), 'array<string>') AS imp_viewed_houses,
    ts_event
    FROM datalake_amplitude_clean_staging.170698_recset_impression_events
    WHERE MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
    AND get_json_object(user_properties, '$.country') = 'BR'
    AND id_user IS NOT NULL

UNION ALL

    -- This gets the remaining viewed recs
    SELECT
    get_json_object(event_properties, '$.recset_id') AS recset_id,
    concat(get_json_object(event_properties, '$.recset_id'), '-', id_user) AS recset_id_fix,
    from_json(get_json_object(event_properties, '$.viewed_house_list'), 'array<string>') AS imp_viewed_houses,
    ts_event
    FROM datalake_amplitude_clean_staging.170698_recset_viewed_events
    WHERE MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
    AND get_json_object(user_properties, '$.country') = 'BR'
    AND id_user IS NOT NULL
)

SELECT  recs_impressions_info.recset_id,
        recs_impressions_info.recset_id_fix,
        recs_impressions_info.id_user,
        recs_impressions_info.id_session,
        recs_impressions_info.id_amplitude,
        recs_impressions_info.id_device,
        exploded_house_id AS id_house,
        ROW_NUMBER() OVER (PARTITION BY recs_impressions_info.recset_id_fix ORDER BY recs_impressions.ts_event ASC) AS position,
        CASE
            WHEN recs_impressions_info.business_context IN ("RENT", "rent") THEN "RENT"
            WHEN recs_impressions_info.business_context IN ("SALE", "sale") THEN "SALE"
            ELSE "Error"
        END AS business_context,
        CASE
            WHEN recs_impressions_info.device_type IN ("android", "ios") THEN "app"
            WHEN recs_impressions_info.device_type IN ("web_desktop", "web_mobile") THEN "web"
            ELSE "None"
        END AS platform,
        recs_impressions_info.showcase,
        recs_impressions_info.user_properties,
        recs_impressions.ts_event as ts_recommendation,
        recs_impressions_info.year,
        recs_impressions_info.month,
        recs_impressions_info.day
FROM recs_impressions_info
LEFT JOIN recs_impressions ON recs_impressions_info.recset_id_fix = recs_impressions.recset_id_fix
LATERAL VIEW explode(imp_viewed_houses) tmp_imp AS exploded_house_id
