WITH signup_events AS (
    SELECT
        e.id_user,
        e.id_device,
        e.uuid_person,
        e.uuid_amplitude_event,
        e.event_type,
        e.up_platform,
        e.up_utm_source,
        e.up_utm_medium,
        e.up_utm_campaign,
        e.up_utm_content,
        e.up_utm_term,
        e.app_type,
        e.login_status,
        e.ts_event,
        e.year,
        e.month,
        e.day
    FROM
        datalake_amplitude_agents_app.agents_sign_up_events AS e
    WHERE
        DATE(e.ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND e.is_prod_event IS TRUE
        AND e.event_type IN (
            'ub_page_view',
            'welcome_screen_viewed',
            'partner_agent_active_status_viewed',
            'agent_pending_status_viewed',
            'agent_inactive_status_viewed',
            'personal_data_screen_viewed',
            'pending_analysis_success_screen_viewed'
        )
),
user_device AS (
    SELECT
        se.id_device,
        MAX(e.id_user) AS id_user,
        MAX(COALESCE(sks.uuid_person, e.uuid_person)) AS uuid_person
    FROM
        signup_events AS se
    JOIN
        datalake_amplitude_agents_app.agents_sign_up_events AS e
            ON e.id_device = se.id_device
            AND e.is_prod_event IS TRUE
    LEFT JOIN
        datalake_person.person_sks AS sks
            ON sks.id_user = e.id_user
    GROUP BY 1
),
utm_adhoc_rule AS (
    SELECT
        COALESCE(e.id_user, ue.id_user, e.id_device) AS id_tof_user,
        COALESCE(e.id_user, ue.id_user) AS id_user,
        e.id_device,
        COALESCE(e.uuid_person, ue.uuid_person) AS uuid_person,
        e.uuid_amplitude_event,
        CASE
          WHEN COALESCE(tbd.utm_campaign, e.up_utm_campaign) IS NULL
            AND COALESCE(tbd.utm_source, e.up_utm_source) IS NULL
            AND COALESCE(tbd.utm_medium, e.up_utm_medium) IS NULL
            AND e.up_platform IS NULL
            THEN "lost.los.lostra.lostra.l.losttracking.losttracking"
          WHEN COALESCE(tbd.utm_campaign, e.up_utm_campaign) IS NULL
            AND COALESCE(tbd.utm_source, e.up_utm_source) IS NULL
            AND COALESCE(tbd.utm_medium, e.up_utm_medium) IS NULL
            AND e.up_platform IS NOT NULL
          THEN "na.acq.org.na.d.direct.na"
        END AS utm_adhoc_rule,
        tbd.utm_hash,
        e.event_type,
        COALESCE(e.up_platform, 'N/A') AS platform,
        COALESCE(tbd.utm_source, e.up_utm_source, 'N/A') AS utm_source,
        COALESCE(tbd.utm_medium, e.up_utm_medium, 'N/A') AS utm_medium,
        COALESCE(tbd.utm_campaign, e.up_utm_campaign, 'N/A') AS utm_campaign,
        COALESCE(tbd.utm_content, e.up_utm_content, 'N/A') AS utm_content,
        COALESCE(tbd.utm_term, e.up_utm_term, 'N/A') AS utm_term,
        e.app_type,
        e.login_status AS is_logged_in,
        e.ts_event,
        e.year,
        e.month,
        e.day
    FROM
        signup_events AS e
    JOIN
        user_device AS ue
            ON ue.id_device = e.id_device
    LEFT JOIN
        datalake_attribution.tracking_by_device AS tbd
            ON tbd.id_device = e.id_device
            AND e.ts_event BETWEEN tbd.ts_utm_attribution_start AND COALESCE(tbd.ts_utm_attribution_end, NOW())
),
taxonomy_naming_convention AS (
  SELECT
      events.uuid_amplitude_event,
      LOWER(
          COALESCE(
              events.utm_adhoc_rule,
              dict.naming_convention_sufix,
              REGEXP_REPLACE(ef.correct_utm_campaign, '^[^.]+\.', ''),
              IF(
                  LOWER(events.utm_campaign) RLIKE '^(zebra|[0-9]+)\.',
                  REGEXP_REPLACE(events.utm_campaign, '^[^.]+\.', ''),
                  events.utm_campaign
              )
          )
      ) AS campaign_naming
  FROM
      utm_adhoc_rule AS events
  LEFT JOIN
      datalake_growth_taxonomy.unified_taxonomy_dictionary AS dict
          ON LOWER(events.utm_campaign) = LOWER(COALESCE(dict.utm_campaign, 'N/A'))
          AND LOWER(events.utm_source) = LOWER(COALESCE(dict.utm_source, 'N/A'))
          AND LOWER(events.utm_medium) = LOWER(COALESCE(dict.utm_medium, 'N/A'))
  LEFT JOIN
      datalake_gsheets_clean.taxonomy_demand_exception_flow AS ef
          ON LOWER(events.utm_campaign) = LOWER(COALESCE(ef.utm_campaign, 'N/A'))
          AND LOWER(events.utm_source) = LOWER(COALESCE(ef.utm_source, 'N/A'))
          AND LOWER(events.utm_medium) = LOWER(COALESCE(ef.utm_medium, 'N/A'))
),
taxonomy_dimensions AS (
    SELECT
        events.uuid_amplitude_event,
        dict.sk_media_setup,
        tx.campaign_naming,
        dict.campaign_business_context,
        dict.campaign_strategy_intent,
        dict.behavior_type,
        dict.medium,
        dict.campaign_landing_page,
        dict.source,
        dict.dict_source,
        ROW_NUMBER() OVER (
            PARTITION BY events.uuid_amplitude_event
            ORDER BY dict.dict_source = 'demand' DESC
        ) AS rn
    FROM
        utm_adhoc_rule AS events
    LEFT JOIN
        taxonomy_naming_convention AS tx
            ON tx.uuid_amplitude_event = events.uuid_amplitude_event
    LEFT JOIN
        datalake_growth_taxonomy.unified_taxonomy_dictionary AS dict
            ON dict.naming_convention_sufix = tx.campaign_naming
)
SELECT
    events.id_tof_user,
    events.id_user,
    events.id_device,
    td.sk_media_setup,
    events.uuid_person,
    events.event_type,
    td.campaign_naming,
    events.app_type,
    events.platform,
    td.campaign_business_context,
    td.campaign_strategy_intent,
    td.behavior_type,
    td.medium,
    td.campaign_landing_page,
    td.source,
    td.dict_source,
    events.utm_source,
    events.utm_medium,
    events.utm_campaign,
    events.utm_content,
    events.utm_term,
    events.is_logged_in,
    COALESCE(events.utm_adhoc_rule = "lost.los.lostra.lostra.l.losttracking.losttracking", FALSE) AS is_lost_tracking_channel,
    COALESCE(events.utm_adhoc_rule = "na.acq.org.na.d.direct.na", FALSE) AS is_direct_channel,
    events.ts_event,
    events.year,
    events.month,
    events.day
FROM
    utm_adhoc_rule AS events
LEFT JOIN
    taxonomy_dimensions AS td
        ON td.uuid_amplitude_event = events.uuid_amplitude_event
        AND td.rn = 1
