WITH
-------------------------------
-- MARKETING DEMAND TAXONOMY --
-------------------------------
taxonomy_demand AS (
    WITH taxonomy_min_ids AS (
        SELECT
            MIN(id) AS id
        FROM
            datalake_gsheets_clean.taxonomy_demand
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
        datalake_gsheets_clean.taxonomy_demand AS td
    JOIN taxonomy_min_ids AS td_min
        ON td.id = td_min.id
),
----------------------
-- AMPLITUDE EVENTS --
----------------------
filtered_events AS (
    SELECT DISTINCT
    COALESCE(business_context, 'rent') AS business_context,
    COALESCE(CAST(ep_house_id AS STRING), top5_house_id[1]) AS id_house,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_term,
    utm_content,
    CAST(up_platform AS STRING) AS app_type,
    COALESCE(
        CAST(id_user AS STRING),
        CAST(id_device AS STRING)
    ) AS id_tof_user,
    CASE
        WHEN UPPER(CAST(utm_campaign AS STRING)) LIKE '%BRANDED%'
            OR UPPER(CAST(utm_campaign AS STRING)) LIKE '%INSTITUCIONAL%'
        THEN 'Branded'
        ELSE 'Outro'
    END AS branded,
    CAST(ts_event AS DATE) AS dt_event
FROM
    datalake_amplitude_page_viewed_events.schedule_search_listing_events
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
),
-------------------
-- HOUSE REGIONS --
-------------------
dim_house AS (
    SELECT DISTINCT
        substr(CAST(h.id AS STRING), 1, 9) AS id_house,
        CAST(h.id_region AS STRING) AS sk_region
    from datalake_ebdb_clean.house h
)
SELECT
    evt.id_tof_user,
    COALESCE(NULLIF(dr.city_group, ''), 'Not Mapped') AS city_group,
    COALESCE(td.mkt_channel, 'Not Mapped') AS mkt_channel,
    COALESCE(td.mkt_medium, 'Not Mapped') AS mkt_medium,
    COALESCE(td.mkt_source, 'Not Mapped') AS mkt_source,
    evt.business_context,
    evt.app_type,
    evt.utm_source,
    evt.utm_medium,
    evt.branded,
    evt.utm_campaign,
    evt.utm_term,
    evt.utm_content,
    evt.dt_event
FROM
    filtered_events AS evt
LEFT JOIN dim_house AS dh
    ON evt.id_house = dh.id_house
LEFT JOIN datalake_region.region AS dr
    ON dh.sk_region = dr.id
LEFT JOIN taxonomy_demand AS td
    ON LOWER(COALESCE(td.app_type, '')) = LOWER(COALESCE(evt.app_type, ''))
    AND LOWER(COALESCE(td.utm_source, '')) = LOWER(COALESCE(evt.utm_source, ''))
    AND LOWER(COALESCE(td.utm_medium, '')) = LOWER(COALESCE(evt.utm_medium, ''))
    AND LOWER(COALESCE(td.branded, '')) = LOWER(COALESCE(evt.branded, ''))