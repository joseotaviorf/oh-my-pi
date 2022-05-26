WITH conversions AS (
    SELECT
        id_amplitude,
        id_user
    FROM
        datalake_amplitude_clean.170698_visit_schedule_confirmed_events
    WHERE 
        year = {year}
        AND month = {month}
        AND day = {day}
    UNION
    SELECT
        id_amplitude,
        id_user
    FROM
        datalake_amplitude_clean.170698_debug_visit_schedule_confirmed_events
    WHERE 
        year = {year}
        AND month = {month}
        AND day = {day}
    UNION
    SELECT
        id_amplitude,
        id_user
    FROM
        datalake_amplitude_clean.170698_offer_submitted_events
    WHERE 
        year = {year}
        AND month = {month}
        AND day = {day}
),
distinct_conversions AS (
    SELECT DISTINCT
        id_amplitude,
        id_user
    FROM
        conversions
    WHERE
        id_amplitude IS NOT NULL
),
ids_mapped_from_conversions AS (
    SELECT
        cvs.id_user,
        COALESCE(amu.id_amplitude,cvs.id_amplitude) AS id_amplitude,
        COALESCE(amu.id_amplitude_merged,cvs.id_amplitude) AS merged_amplitude_id
    FROM 
        distinct_conversions AS cvs
    JOIN 
        datalake_amplitude_clean.170698_user_merge AS amu
            ON cvs.id_amplitude = amu.id_amplitude_merged
    GROUP BY 1,2,3
    UNION
    SELECT
        id_user,
        id_amplitude,
        id_amplitude AS merged_amplitude_id
    FROM
        distinct_conversions
    GROUP BY 1,2,3
),
events_filtered AS (
    SELECT DISTINCT
        event_type_sanitized,
        event_type,
        ts_event,
        COALESCE(imc.id_user, evt.id_user) AS id_user,
        COALESCE(imc.merged_amplitude_id, evt.id_amplitude) AS id_amplitude,
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
        gclid,
        referrer,
        {year} as year,
        {month} as month,
        {day} as day
    FROM
        datalake_online_attribution.events_exploded AS evt
    JOIN
        ids_mapped_from_conversions AS imc 
            ON imc.id_amplitude = evt.id_amplitude
    WHERE
      DATE(CONCAT_WS("-",evt.year, evt.month, evt.day)) > DATE('{year}-{month}-{day}') - INTERVAL '4' month
),
events_mapped AS (
    SELECT
        event_type_sanitized,
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
        FIRST_VALUE(ts_event) OVER (PARTITION BY id_amplitude, web_platform, web_medium, web_source, web_campaign, web_term, web_content, gclid ORDER BY ts_event) AS ts_web_attribution,
        FIRST_VALUE(ts_event) OVER (PARTITION BY id_amplitude, adjust_adgroup, adjust_app_version, adjust_campaign, adjust_city, adjust_country, adjust_creative, adjust_impression_based, adjust_installed_at, adjust_is_organic, adjust_network, adjust_reattributed_at, adjust_tracking_enabled, adjust_tracking_limited ORDER BY ts_event) AS ts_app_attribution,
        year,
        month,
        day
    FROM 
        events_filtered
),
events_online_attribution AS (
    SELECT
        event_type_sanitized,
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
        events_mapped
),
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
),
taxonomy_demand AS (
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
    JOIN 
        taxonomy_min_ids AS td_min
            ON td.id = td_min.id
)
SELECT
    ea.event_type_sanitized,
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
        ON LOWER(COALESCE(ea.utm_source, '')) = LOWER(COALESCE(td.utm_source, ''))
        AND LOWER(COALESCE(ea.utm_medium, '')) = LOWER(COALESCE(td.utm_medium, ''))
        AND LOWER(COALESCE(ea.branded, '')) = LOWER(COALESCE(td.branded, ''))
        AND LOWER(COALESCE(ea.platform, '')) = LOWER(COALESCE(td.app_type, ''))