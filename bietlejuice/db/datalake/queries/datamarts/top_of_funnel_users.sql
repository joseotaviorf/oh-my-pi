WITH
-------------------------------
-- MARKETING DEMAND TAXONOMY --
-------------------------------
taxonomy_demand AS (
    WITH taxonomy_min_ids AS (
        SELECT
            MIN(id) AS id
        FROM
            datalake_raw.gsheets_taxonomy_demand
        WHERE
            first_update_source = 'Inquilinos'
            AND flg_via_reschedule = '0'
        GROUP BY
            LOWER(app_type),
            LOWER(utm_source),
            LOWER(utm_medium),
            LOWER(branded),
            LOWER(first_update_source),
            flg_via_reschedule
    )
    SELECT
        CAST(td.id AS BIGINT) AS id,
        td.app_type,
        td.utm_source,
        td.utm_medium,
        td.branded,
        td.first_update_source,
        CAST(td.flg_via_reschedule AS BOOLEAN) AS flg_via_reschedule ,
        td.Category AS mkt_category,
        td.Flow AS mkt_flow,
        td.Completion AS mkt_completion,
        td.Channel AS mkt_channel,
        td.Medium AS mkt_medium,
        td.Origin AS mkt_origin,
        td.Source AS mkt_source,
        td.Platform AS mkt_platform
    FROM
        datalake_raw.gsheets_taxonomy_demand AS td
    JOIN taxonomy_min_ids AS td_min
        ON td.id = td_min.id
),
----------------------
-- AMPLITUDE EVENTS --
----------------------
filtered_events AS (
    SELECT DISTINCT
        CAST(ts_event AS DATE) AS dt_event,
        COALESCE(UPPER(JSON_EXTRACT_SCALAR(event_properties, '$.business_context')), 'RENT') AS business_context,
        COALESCE(
            CAST(id_amplitude AS VARCHAR),
            CAST(id_user AS VARCHAR),
            CAST(id_device AS VARCHAR)
        ) AS id_tof_user,
        COALESCE(
            CAST(json_extract(event_properties, '$.house_id') AS VARCHAR),
            ELEMENT_AT(CAST(json_extract(event_properties, '$.top5_house_id') AS ARRAY(VARCHAR)), 1)
        ) AS id_house,
        JSON_EXTRACT_SCALAR(user_properties, '$.utm_source') AS utm_source,
        JSON_EXTRACT_SCALAR(user_properties, '$.utm_medium') AS utm_medium,
        CASE
            WHEN UPPER(CAST(JSON_EXTRACT_SCALAR(user_properties, '$.utm_campaign') AS VARCHAR)) LIKE '%BRANDED%'
                        OR UPPER(CAST(JSON_EXTRACT_SCALAR(user_properties, '$.utm_campaign') AS VARCHAR)) LIKE '%INSTITUCIONAL%'
                THEN 'Branded'
            ELSE 'Outro'
        END AS branded,
        CAST(JSON_EXTRACT_SCALAR(user_properties , '$.platform') AS VARCHAR) AS app_type,
        JSON_EXTRACT_SCALAR(user_properties, '$.utm_campaign') AS utm_campaign,
        JSON_EXTRACT_SCALAR(user_properties, '$.utm_term') AS utm_term,
        JSON_EXTRACT_SCALAR(user_properties, '$.utm_content') AS utm_content,
        ROW_NUMBER() OVER(
                        PARTITION BY COALESCE(UPPER(JSON_EXTRACT_SCALAR(event_properties, '$.business_context')), 'RENT'),
                                     COALESCE(CAST(id_amplitude as varchar),
                                               CAST(id_user as varchar),
                                               CAST(id_device as varchar))
                        ORDER BY CAST(ts_event AS TIMESTAMP)
        ) AS user_interactions_order
    FROM
        datalake_amplitude_clean_prod.events
    WHERE
        id_app = 170698
        AND DATE(ts_event) BETWEEN
                    CURRENT_DATE - INTERVAL '120' DAY
                    AND CURRENT_DATE - INTERVAL '1' DAY
        AND event_type IN (
            'search_page_viewed',
            'listing_page_viewed', 
            'schedule_page_viewed'
            )
),
-------------------
-- HOUSE REGIONS --
-------------------
dim_house AS (
    SELECT DISTINCT
        SUBSTR(fhl.sk_house_listing, 1, 9) AS id_house,
        fhl.sk_region
    FROM
        datalake_clean.ods_fact_house_listings AS fhl
)
SELECT
    evt.dt_event,
    evt.id_tof_user,
    COALESCE(NULLIF(dr.city_group, ''), 'Not Mapped') AS city_group,
    COALESCE(td.mkt_channel, 'Not Mapped') AS mkt_channel,
    COALESCE(td.mkt_medium, 'Not Mapped') AS mkt_medium,
    COALESCE(td.mkt_source, 'Not Mapped') AS mkt_source,
    evt.business_context,
    evt.user_interactions_order = 1 AS flg_is_first_interaction,
    evt.app_type,
    evt.utm_source,
    evt.utm_medium,
    evt.branded,
    evt.utm_campaign,
    evt.utm_term,
    evt.utm_content
FROM
    filtered_events AS evt
LEFT JOIN dim_house AS dh
    USING(id_house)
LEFT JOIN datalake_clean.ods_dim_region AS dr
    USING(sk_region)
LEFT JOIN taxonomy_demand AS td
    ON LOWER(COALESCE(td.app_type, '')) = LOWER(COALESCE(evt.app_type, ''))
    AND LOWER(COALESCE(td.utm_source, '')) = LOWER(COALESCE(evt.utm_source, ''))
    AND LOWER(COALESCE(td.utm_medium, '')) = LOWER(COALESCE(evt.utm_medium, ''))
    AND LOWER(COALESCE(td.branded, '')) = LOWER(COALESCE(evt.branded, ''))