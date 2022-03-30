WITH conversions AS (
    SELECT DISTINCT
        id_amplitude
    FROM(
        SELECT
            id_amplitude
        FROM
            datalake_amplitude_clean.170698_visit_schedule_confirmed_events
        WHERE 
            year = {year}
            AND month = {month}
            AND day = {day}
        UNION
        SELECT
            id_amplitude
        FROM
            datalake_amplitude_clean.170698_debug_visit_schedule_confirmed_events
        WHERE 
            year = {year}
            AND month = {month}
            AND day = {day}
        UNION
        SELECT
            id_amplitude AS id_amplitude
        FROM
            datalake_amplitude_clean.170698_offer_submitted_events
        WHERE 
            year = {year}
            AND month = {month}
            AND day = {day}
    )
    WHERE
        id_amplitude IS NOT NULL
),
ids_mapped_from_conversions AS (
SELECT
    amu.id_amplitude as id_amplitude,
    cvs.id_amplitude AS merged_amplitude_id   
FROM 
    conversions AS cvs
INNER JOIN 
    datalake_amplitude_clean.170698_user_merge AS amu
ON
    cvs.id_amplitude = amu.id_amplitude_merged
GROUP BY
    amu.id_amplitude,
    cvs.id_amplitude
UNION 
SELECT
    id_amplitude,
    NULL AS merged_amplitude_id
FROM 
    conversions
),
events_filtered AS (
    SELECT
        REPLACE(event_type,"[adjust] ","adjust_") AS event_type,
        evt.ts_event,
        evt.id_user,
        COALESCE(imc.merged_amplitude_id, evt.id_amplitude) as id_amplitude,
        evt.id_session,
        evt.platform as amplitude_platform,
        FROM_JSON(evt.event_properties,'
                house_id STRING,
                offer_id STRING,
                visit_code STRING,
                uri STRING') AS event_properties,
        FROM_JSON(evt.user_properties,'
                entrance_uri STRING,
                platform STRING,
                gclid STRING,
                referrer STRING,
                utm_medium STRING,
                utm_source STRING,
                utm_campaign STRING,
                utm_content STRING,
                utm_term STRING,
                last_utm_medium STRING,
                last_utm_source STRING,
                last_utm_campaign STRING,
                last_utm_content STRING,
                last_utm_term STRING,
                `3fbf25d58c3cce92f0e6609904a37cc9` STRING,  -- app_platform column / event trigged by adjust
                `[adjust] app_version` STRING,
                `[adjust] adgroup` STRING,
                `[adjust] campaign` STRING,
                `[adjust] city` STRING,
                `[adjust] country` STRING,
                `[adjust] creative` STRING,
                `[adjust] impression_based` STRING,
                `[adjust] reattributed_at` STRING,
                `[adjust] installed_at` STRING,
                `[adjust] is_organic` STRING,
                `[adjust] tracking_enabled` STRING,
                `[adjust] tracking_limited` STRING,
                `[adjust] network` STRING') AS user_properties,
        {year} as year,
        {month} as month,
        {day} as day
    FROM
        datalake_amplitude_clean.events AS evt
    INNER JOIN
        ids_mapped_from_conversions AS imc 
    ON
        imc.id_amplitude = evt.id_amplitude
    WHERE
      id_app = 170698
      AND year >= EXTRACT(year FROM (DATE('{year}-{month}-{day}') - interval '4' month))
      AND month >= EXTRACT(month FROM (DATE('{year}-{month}-{day}') - interval '4' month))
      AND day >= EXTRACT(day FROM (DATE('{year}-{month}-{day}') - interval '4' month))
),
events_exploded_properties AS (
    SELECT
        event_type,
        ts_event,
        id_user,
        id_amplitude,
        id_session,
        TRIM(event_properties.house_id) AS id_house,
        TRIM(event_properties.offer_id) AS id_firestore,
        amplitude_platform,
        TRIM(event_properties.visit_code) AS visit_code,
        user_properties.entrance_uri AS entrance_uri,
        event_properties.uri AS uri_event_property,
        user_properties.utm_medium AS web_medium,
        user_properties.utm_source AS web_source,
        user_properties.utm_campaign AS web_campaign,
        user_properties.utm_content AS web_content,
        user_properties.utm_term AS web_term,
        user_properties.last_utm_medium AS web_last_medium,
        user_properties.last_utm_source AS web_last_source,
        user_properties.last_utm_campaign AS web_last_campaign,
        user_properties.last_utm_content AS web_last_content,
        user_properties.last_utm_term AS web_last_term,
        user_properties.`[adjust] app_version` AS adjust_app_version,
        user_properties.`[adjust] adgroup` AS adjust_adgroup,
        user_properties.`[adjust] campaign` AS adjust_campaign,
        user_properties.`[adjust] city` AS adjust_city,
        user_properties.`[adjust] country` AS adjust_country,
        user_properties.`[adjust] creative` AS adjust_creative,
        user_properties.`[adjust] impression_based` AS adjust_impression_based,
        user_properties.`[adjust] reattributed_at` AS adjust_reattributed_at,
        user_properties.`[adjust] installed_at` AS adjust_installed_at,
        user_properties.`[adjust] is_organic` AS adjust_is_organic,
        user_properties.`[adjust] tracking_enabled` AS adjust_tracking_enabled,
        user_properties.`[adjust] tracking_limited` AS adjust_tracking_limited,
        user_properties.`[adjust] network` AS adjust_network,
        user_properties.platform AS web_platform,
        user_properties.`3fbf25d58c3cce92f0e6609904a37cc9` AS app_platform,  -- app_platform column / event trigged by adjust
        user_properties.gclid AS gclid,
        user_properties.referrer AS referrer,
        year,
        month,
        day
    FROM
        events_filtered
),
events_mapped AS (
    SELECT
        event_type,
        ts_event,
        id_user,
        id_amplitude,
        id_session,
        id_house,
        id_firestore,
        amplitude_platform,
        visit_code,
        entrance_uri,
        uri_event_property,
        web_medium,
        web_source,
        web_campaign,
        web_content,
        web_term,
        web_last_medium,
        web_last_source,
        web_last_campaign,
        web_last_content,
        web_last_term,
        adjust_app_version,
        adjust_adgroup,
        adjust_campaign,
        adjust_city,
        adjust_country,
        adjust_creative,
        adjust_impression_based,
        adjust_reattributed_at,
        adjust_installed_at,
        adjust_is_organic,
        adjust_tracking_enabled,
        adjust_tracking_limited,
        adjust_network,
        web_platform,
        app_platform,
        referrer,
        gclid,
        referrer,
        IF((UPPER(web_campaign) LIKE '%BRANDED%' OR UPPER(web_campaign) LIKE '%INSTITUCIONAL%') AND UPPER(web_campaign) NOT LIKE 'NON-BRANDED', 'Branded', 'Outro' ) AS web_branded,
        adjust_network AS app_source,
        'adjust' AS app_medium,
        IF((UPPER(adjust_campaign) LIKE '%BRANDED%' OR UPPER(adjust_campaign) LIKE '%INSTITUCIONAL%') AND UPPER(adjust_campaign) NOT LIKE 'NON-BRANDED', 'Branded', 'Outro' ) AS app_branded,
        year,
        month,
        day
    FROM 
        events_exploded_properties
),
events_attribution AS (
  SELECT
      event_type,
      ts_event,
      id_user,
      id_amplitude,
      id_session,
      id_house,
      id_firestore,
      visit_code,
      amplitude_platform,
      entrance_uri,
      uri_event_property,
      web_medium,
      web_source,
      web_campaign,
      web_content,
      web_term,
      web_last_medium,
      web_last_source,
      web_last_campaign,
      web_last_content,
      web_last_term,
      adjust_app_version,
      adjust_adgroup,
      adjust_campaign,
      adjust_city,
      adjust_country,
      adjust_creative,
      adjust_impression_based,
      adjust_reattributed_at,
      adjust_installed_at,
      adjust_is_organic,
      adjust_tracking_enabled,
      adjust_tracking_limited,
      adjust_network,
      web_platform,
      app_platform,
      gclid,
      referrer,
      web_branded,
      FIRST_VALUE(ts_event) OVER (PARTITION BY id_amplitude, web_platform, web_medium, web_source, web_campaign, web_term, web_content, gclid ORDER BY ts_event) AS ts_web_attribution,
      app_source,
      app_medium,
      app_branded,
      FIRST_VALUE(ts_event) OVER (PARTITION BY id_amplitude, adjust_adgroup, adjust_app_version, adjust_campaign, adjust_city, adjust_country, adjust_creative, adjust_impression_based, adjust_installed_at, adjust_is_organic, adjust_network, adjust_reattributed_at, adjust_tracking_enabled, adjust_tracking_limited ORDER BY ts_event) AS ts_app_attribution,
      year,
      month,
      day
  FROM
      events_mapped
),
taxonomy_demand AS (
    WITH
    taxonomy_min_ids AS (
        SELECT
            MIN(id) AS id
        FROM 
            datalake_gsheets_clean.taxonomy_demand
        WHERE 
            first_update_source = 'Inquilinos'
            AND flg_via_reschedule = '0'
        GROUP BY
            LOWER(utm_source),
            LOWER(utm_medium),
            LOWER(branded),
            LOWER(app_type)
    )
    SELECT
        td.utm_source,
        td.utm_medium,
        td.branded,
        td.app_type,
        td.Flow AS mkt_flow,
        td.Completion AS mkt_completion,
        td.Origin AS mkt_origin,
        td.Channel AS mkt_channel,
        td.Medium AS mkt_medium,
        td.Source AS mkt_source,
        td.Platform AS mkt_plataform
    FROM 
        datalake_gsheets_clean.taxonomy_demand AS td
    INNER JOIN 
        taxonomy_min_ids AS td_min
    ON 
        td.id = td_min.id
),
events_online_attribution AS (
    SELECT
        event_type,
        ts_event,
        id_user,
        id_amplitude,
        id_session,
        id_house,
        id_firestore,
        visit_code,
        amplitude_platform,
        entrance_uri,
        uri_event_property,
        web_medium,
        web_source,
        web_campaign,
        web_content,
        web_term,
        web_last_medium,
        web_last_source,
        web_last_campaign,
        web_last_content,
        web_last_term,
        adjust_app_version,
        adjust_adgroup,
        adjust_campaign,
        adjust_city,
        adjust_country,
        adjust_creative,
        adjust_impression_based,
        adjust_reattributed_at,
        adjust_installed_at,
        adjust_is_organic,
        adjust_tracking_enabled,
        adjust_tracking_limited,
        adjust_network,
        CASE
          WHEN ts_app_attribution>ts_web_attribution THEN app_platform
          WHEN ts_web_attribution>ts_app_attribution THEN web_platform
          ELSE web_platform
        END AS platform,
        referrer,
        gclid,
        web_branded,
        ts_web_attribution,
        app_source,
        app_medium,
        app_branded,
        ts_app_attribution,
        CASE
          WHEN ts_app_attribution>ts_web_attribution THEN app_source
          WHEN ts_web_attribution>ts_app_attribution THEN web_source
          ELSE web_source
        END AS utm_source,
        CASE
          WHEN ts_app_attribution>ts_web_attribution THEN app_medium
          WHEN ts_web_attribution>ts_app_attribution THEN web_medium
          ELSE web_medium
        END AS utm_medium,
        CASE
          WHEN ts_app_attribution>ts_web_attribution THEN app_branded
          WHEN ts_web_attribution>ts_app_attribution THEN web_branded
          ELSE web_branded
        END AS branded,
        year,
        month,
        day
    FROM
        events_attribution
)
SELECT
    ea.event_type,
    ea.ts_event,
    ea.id_user,
    ea.id_amplitude,
    ea.id_session,
    ea.id_house,
    ea.id_firestore,
    ea.visit_code,
    ea.amplitude_platform,
    ea.entrance_uri,
    ea.uri_event_property,
    ea.web_medium,
    ea.web_source,
    ea.web_campaign,
    ea.web_content,
    ea.web_term,
    ea.web_last_medium,
    ea.web_last_source,
    ea.web_last_campaign,
    ea.web_last_content,
    ea.web_last_term,
    ea.adjust_app_version,
    ea.adjust_adgroup,
    ea.adjust_campaign,
    ea.adjust_city,
    ea.adjust_country,
    ea.adjust_creative,
    ea.adjust_impression_based,
    ea.adjust_reattributed_at,
    ea.adjust_installed_at,
    ea.adjust_is_organic,
    ea.adjust_tracking_enabled,
    ea.adjust_tracking_limited,
    ea.adjust_network,
    ea.platform,
    ea.referrer,
    ea.gclid,
    ea.web_branded,
    ea.ts_web_attribution,
    ea.app_source,
    ea.app_medium,
    ea.app_branded,
    ea.ts_app_attribution,
    td.mkt_flow,
    td.mkt_completion,
    td.mkt_origin,
    td.mkt_channel,
    td.mkt_medium,
    td.mkt_source,
    td.mkt_plataform,
    ea.utm_source,
    ea.utm_medium,
    ea.branded,
    ea.year,
    ea.month,
    ea.day
FROM
    events_online_attribution AS ea
LEFT JOIN
    taxonomy_demand AS td
ON 
    LOWER(COALESCE(ea.utm_source, '')) = LOWER(COALESCE(td.utm_source, ''))
    AND LOWER(COALESCE(ea.utm_medium, '')) = LOWER(COALESCE(td.utm_medium, ''))
    AND LOWER(COALESCE(ea.branded, '')) = LOWER(COALESCE(td.branded, ''))
    AND LOWER(COALESCE(ea.platform, '')) = LOWER(COALESCE(td.app_type, ''))