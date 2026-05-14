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
        tof_event_type,
        COALESCE(CAST(ep_house_id AS STRING), top5_house_id[1]) AS id_house,
        entrance_uri,
        referrer,
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
            WHEN (UPPER(CAST(utm_campaign AS STRING)) LIKE '%BRANDED%'
                  OR UPPER(CAST(utm_campaign AS STRING)) LIKE '%INSTITUCIONAL%')
                 AND UPPER(CAST(utm_campaign AS STRING)) NOT LIKE '%NON-BRANDED%'
            THEN 'Branded'
            ELSE 'Outro'
        END AS branded,
        is_qac,
        uri,
        CAST(id_region AS STRING) AS id_region,
        year,
        month,
        day,
        ts_event,
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
        substr(CAST(house_dim.id AS STRING), 1, 9) AS id_house,
        CAST(house_dim.id_region AS STRING) AS sk_region
    FROM datalake_ebdb_clean.house AS house_dim
),
qac_region AS (
    SELECT 
        qac_plugin.house_id AS id_house,
        MAX(region_city.id) AS id_region
    FROM
        vespucio_classifieds.classifieds_house_id AS qac_plugin
    INNER JOIN
        vespucio_prod_delta.listings AS listings
            ON qac_plugin.source_id = listings.source_id
    INNER JOIN
        vespucio_prod_delta.house_compounds AS compounds
            ON listings.dejavuid = compounds.dejavuid
    INNER JOIN
        datalake_ebdb_clean.state AS state_dim
            ON state_dim.abbreviation = compounds.address.state_code
    INNER JOIN
        datalake_ebdb_clean.region AS region_city
            ON LOWER(region_city.name) = LOWER(compounds.address.city)
                AND region_city.id_state = state_dim.id
    GROUP BY 
        qac_plugin.house_id
)
SELECT
    BIGINT(year*10000 + month*100 + day || ROW_NUMBER() OVER (ORDER BY evt.dt_event)) AS id,
    evt.id_tof_user,
    COALESCE(evt.id_house, -1) AS id_house,
    CASE
        WHEN evt.is_qac = FALSE THEN dh.sk_region
        WHEN evt.is_qac = TRUE AND dh.sk_region IS NOT NULL THEN dh.sk_region -- QAC event with house region
        WHEN evt.is_qac = TRUE AND evt.id_region IS NOT NULL THEN evt.id_region -- QAC event with infered region
        WHEN evt.is_qac = TRUE AND qac_region.id_region IS NOT NULL THEN qac_region.id_region -- QAC event with infered region
        ELSE '-1'
    END AS sk_region,
    COALESCE(td.mkt_category, 'Not Mapped') AS mkt_category,
    COALESCE(td.mkt_flow, 'Not Mapped') AS mkt_flow,
    COALESCE(td.mkt_completion, 'Not Mapped') AS mkt_completion,
    COALESCE(td.mkt_origin, 'Not Mapped') AS mkt_origin,
    COALESCE(td.mkt_channel, 'Not Mapped') AS mkt_channel,
    COALESCE(td.mkt_medium, 'Not Mapped') AS mkt_medium,
    COALESCE(td.mkt_source, 'Not Mapped') AS mkt_source,
    COALESCE(td.mkt_platform, 'Not Mapped') AS mkt_platform,
    evt.tof_event_type,
    evt.business_context,
    evt.entrance_uri,
    evt.referrer,
    evt.app_type,
    evt.utm_source,
    evt.utm_medium,
    evt.branded,
    evt.utm_campaign,
    evt.utm_term,
    evt.utm_content,
    evt.is_qac,
    year,
    month,
    day,
    evt.dt_event,
    evt.ts_event
FROM
    filtered_events AS evt
LEFT JOIN 
    dim_house AS dh
        ON evt.id_house = dh.id_house
LEFT JOIN
    qac_region
        ON evt.id_house = qac_region.id_house
            AND evt.is_qac = TRUE
LEFT JOIN taxonomy_demand AS td
    ON LOWER(COALESCE(td.app_type, '')) = LOWER(COALESCE(evt.app_type, ''))
    AND LOWER(COALESCE(td.utm_source, '')) = LOWER(COALESCE(evt.utm_source, ''))
    AND LOWER(COALESCE(td.utm_medium, '')) = LOWER(COALESCE(evt.utm_medium, ''))
    AND LOWER(COALESCE(td.branded, '')) = LOWER(COALESCE(evt.branded, ''))