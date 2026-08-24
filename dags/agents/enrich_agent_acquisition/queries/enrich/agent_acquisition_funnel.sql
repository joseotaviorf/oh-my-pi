WITH events_touchpoint AS (
    SELECT
        id_tof_user,
        id_user,
        id_device,
        sk_media_setup,
        uuid_person,
        event_type,
        campaign_naming,
        app_type,
        platform,
        campaign_business_context,
        campaign_strategy_intent,
        behavior_type,
        medium,
        campaign_landing_page,
        source,
        dict_source,
        is_logged_in,
        ROW_NUMBER() OVER (
            PARTITION BY id_tof_user, event_type
            ORDER BY
            is_lost_tracking_channel,
            is_direct_channel,
            ts_event DESC
        ) = 1 AS is_last_touchpoint_by_event,
        ROW_NUMBER() OVER (
            PARTITION BY id_tof_user
            ORDER BY
            is_lost_tracking_channel,
            is_direct_channel,
            ts_event DESC
        ) = 1 AS is_last_touchpoint,
        ts_event,
        year,
        month,
        day
    FROM
        datalake_agent_acquisition.prospect_agent_funnel_events
    WHERE
        DATE(ts_event) BETWEEN (DATE('{load_start_date}') - INTERVAL 1 DAY) AND DATE('{load_end_date}')
),
prospect_user AS (
    SELECT
        MAX(sks.id_user) AS id_user,
        pa.uuid_person,
        pa.contract_signature_status,
        pa.ts_created,
        pa.ts_contract_signed
    FROM
        datalake_agent_accreditation.prospect_agent AS pa
    LEFT JOIN
        datalake_person.person_sks AS sks
            ON pa.uuid_person = sks.uuid_person
    WHERE
        DATE(pa.ts_updated) <= DATE('{load_end_date}')
    GROUP BY 2, 3, 4, 5
),
demand_supply_acquisition AS (
    SELECT
        sfu.id_external AS id_user,
        sp.ts_created AS ts_acquisition
    FROM
        datalake_sales_flow_clean.specialist AS sp
    INNER JOIN
        datalake_sales_flow_clean.users AS sfu
            ON sp.id_user = sfu.id
    WHERE
        sp.kind = "AGENT_LEAD_REFERRAL"
        AND DATE(sp.ts_created) <= DATE('{load_end_date}')
    UNION ALL
    SELECT
        fl.id_user,
        lbc.ts_first_listing AS ts_acquisition
    FROM
        datalake_big_agent.house_listing_consultant AS fl
    JOIN
        datalake_ebdb_listing.listing_business_context AS lbc
            ON lbc.id_house = fl.id_house
            AND lbc.business_context = fl.business_context
    WHERE
        fl.id_user IS NOT NULL
        AND fl.consultant_type IN ("CIQ_FULL", "PRO_ACQUIRER")
        AND lbc.ts_first_listing IS NOT NULL
        AND DATE(lbc.ts_first_listing) <= DATE('{load_end_date}')
),
acquisition_by_user AS (
  SELECT
      id_user,
      ROW_NUMBER() OVER (PARTITION BY id_user ORDER BY ts_acquisition) = 1 AS is_first_acquisition_by_user,
      ts_acquisition
  FROM
      demand_supply_acquisition
),
capacity_activation AS (
    SELECT
        a.id_user,
        IF(
            cs.is_passive_lead_receiver IS TRUE,
            ROW_NUMBER() OVER(PARTITION BY a.id_user, cs.is_passive_lead_receiver ORDER BY cs.ts_started, cs.ts_ended) = 1,
            FALSE
        ) AS is_first_capacity_activation,
        cs.ts_started
    FROM
        datalake_ebdb_agent_events.capability_settings AS cs
    JOIN
        datalake_ebdb_agent_events.agent_unified_identity AS a
            ON a.id_agent = cs.id_agent
    WHERE
        DATE(cs.ts_started) <= DATE('{load_end_date}')
)
SELECT -- ToF – Landing page viewed
    events.id_user,
    events.id_tof_user,
    events.id_device,
    events.uuid_person,
    "ToF" AS funnel_step,
    "Landing page viewed" AS substep,
    events.event_type,
    events.campaign_naming,
    events.app_type,
    events.platform,
    events.campaign_business_context,
    events.campaign_strategy_intent,
    events.behavior_type,
    events.medium,
    events.campaign_landing_page,
    events.source,
    events.dict_source,
    events.is_logged_in,
    events.ts_event,
    events.year,
    events.month,
    events.day
FROM
    events_touchpoint AS events
WHERE
    events.is_last_touchpoint_by_event IS TRUE
    AND events.event_type = 'ub_page_view'

UNION ALL

SELECT -- MoF – Logged in completed
    events.id_user,
    events.id_tof_user,
    events.id_device,
    events.uuid_person,
    "MoF" AS funnel_step,
    "Logged in completed" AS substep,
    events.event_type,
    events.campaign_naming,
    events.app_type,
    events.platform,
    events.campaign_business_context,
    events.campaign_strategy_intent,
    events.behavior_type,
    events.medium,
    events.campaign_landing_page,
    events.source,
    events.dict_source,
    events.is_logged_in,
    events.ts_event,
    events.year,
    events.month,
    events.day
FROM
    events_touchpoint AS events
LEFT JOIN
    events_touchpoint AS excp
        ON excp.id_tof_user = events.id_tof_user
        AND excp.event_type IN ("partner_agent_active_status_viewed", "agent_pending_status_viewed", "agent_inactive_status_viewed")
WHERE
    events.is_last_touchpoint_by_event IS TRUE
    AND events.event_type IN ('welcome_screen_viewed', 'personal_data_screen_viewed')
    AND excp.id_tof_user IS NULL

UNION ALL

SELECT -- MoF – Sign-up completed
    pu.id_user,
    COALESCE(events.id_tof_user, events_except.id_tof_user) AS id_tof_user,
    COALESCE(events.id_device, events_except.id_device) AS id_device,
    pu.uuid_person,
    "MoF" AS funnel_step,
    "Sign-up completed" AS substep,
    COALESCE(events.event_type, events_except.event_type) AS event_type,
    COALESCE(events.campaign_naming, events_except.campaign_naming) AS campaign_naming,
    COALESCE(events.app_type, events_except.app_type) AS app_type,
    COALESCE(events.platform, events_except.platform) AS platform,
    COALESCE(events.campaign_business_context, events_except.campaign_business_context) AS campaign_business_context,
    COALESCE(events.campaign_strategy_intent, events_except.campaign_strategy_intent) AS campaign_strategy_intent,
    COALESCE(events.behavior_type, events_except.behavior_type) AS behavior_type,
    COALESCE(events.medium, events_except.medium) AS medium,
    COALESCE(events.campaign_landing_page, events_except.campaign_landing_page) AS campaign_landing_page,
    COALESCE(events.source, events_except.source) AS source,
    COALESCE(events.dict_source, events_except.dict_source) AS dict_source,
    COALESCE(events.is_logged_in, events_except.is_logged_in) AS is_logged_in,
    pu.ts_created AS ts_event,
    YEAR(pu.ts_created) AS year,
    MONTH(pu.ts_created) AS month,
    DAY(pu.ts_created) AS day
FROM
    prospect_user AS pu
LEFT JOIN
    events_touchpoint AS events
        ON pu.uuid_person = events.uuid_person
        AND events.is_last_touchpoint_by_event IS TRUE
        AND events.event_type IN ('pending_analysis_success_screen_viewed')
        AND events.ts_event <= pu.ts_created
LEFT JOIN
    events_touchpoint AS events_except
        ON pu.uuid_person = events_except.uuid_person
        AND events.uuid_person IS NULL
        AND events_except.is_last_touchpoint IS TRUE
        AND events_except.ts_event <= pu.ts_created
WHERE
    DATE(pu.ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT -- EoF – Contract signed
    pu.id_user,
    events.id_tof_user,
    events.id_device,
    pu.uuid_person,
    "EoF" AS funnel_step,
    "Contract signed" AS substep,
    events.event_type,
    events.campaign_naming,
    events.app_type,
    events.platform,
    events.campaign_business_context,
    events.campaign_strategy_intent,
    events.behavior_type,
    events.medium,
    events.campaign_landing_page,
    events.source,
    events.dict_source,
    events.is_logged_in,
    pu.ts_contract_signed AS ts_event,
    YEAR(pu.ts_contract_signed) AS year,
    MONTH(pu.ts_contract_signed) AS month,
    DAY(pu.ts_contract_signed) AS day
FROM
    prospect_user AS pu
LEFT JOIN
    events_touchpoint AS events
        ON pu.uuid_person = events.uuid_person
        AND events.is_last_touchpoint IS TRUE
WHERE
    pu.contract_signature_status = "COMPLETED"
    AND DATE(pu.ts_contract_signed) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT -- First acquisition (FL/TQC)
    pu.id_user,
    events.id_tof_user,
    events.id_device,
    pu.uuid_person,
    "EoF" AS funnel_step,
    "First Acquisition (FL/TQC)" AS substep,
    events.event_type,
    events.campaign_naming,
    events.app_type,
    events.platform,
    events.campaign_business_context,
    events.campaign_strategy_intent,
    events.behavior_type,
    events.medium,
    events.campaign_landing_page,
    events.source,
    events.dict_source,
    events.is_logged_in,
    acq.ts_acquisition AS ts_event,
    YEAR(acq.ts_acquisition) AS year,
    MONTH(acq.ts_acquisition) AS month,
    DAY(acq.ts_acquisition) AS day
FROM
    prospect_user AS pu
JOIN
    acquisition_by_user AS acq
        ON acq.id_user = pu.id_user
        AND acq.is_first_acquisition_by_user IS TRUE
LEFT JOIN
    events_touchpoint AS events
        ON pu.uuid_person = events.uuid_person
        AND events.is_last_touchpoint IS TRUE
WHERE
    DATE(acq.ts_acquisition) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT -- First capacity activation
    pu.id_user,
    events.id_tof_user,
    events.id_device,
    pu.uuid_person,
    "EoF" AS funnel_step,
    "First capacity activation" AS substep,
    events.event_type,
    events.campaign_naming,
    events.app_type,
    events.platform,
    events.campaign_business_context,
    events.campaign_strategy_intent,
    events.behavior_type,
    events.medium,
    events.campaign_landing_page,
    events.source,
    events.dict_source,
    events.is_logged_in,
    ca.ts_started AS ts_event,
    YEAR(ca.ts_started) AS year,
    MONTH(ca.ts_started) AS month,
    DAY(ca.ts_started) AS day
FROM
    prospect_user AS pu
JOIN
    capacity_activation AS ca
        ON ca.id_user = pu.id_user
LEFT JOIN
    events_touchpoint AS events
        ON pu.uuid_person = events.uuid_person
        AND events.is_last_touchpoint IS TRUE
WHERE
    ca.is_first_capacity_activation IS TRUE
    AND DATE(ca.ts_started) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
