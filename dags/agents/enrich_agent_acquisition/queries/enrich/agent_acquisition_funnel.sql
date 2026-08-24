WITH pre_conversion_device AS (
    SELECT DISTINCT
        id_tof_user
    FROM
        datalake_agent_acquisition.prospect_agent_funnel_events
    WHERE
        DATE(ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
prospect_user AS (
    SELECT
        CAST(MAX(sks.id_user) AS BIGINT) AS id_user,
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
pre_conversion_events_touchpoint AS (
    SELECT
        e.id_tof_user,
        CAST(e.id_user AS BIGINT) AS id_user,
        e.id_device,
        e.sk_media_setup,
        e.uuid_person,
        e.event_type,
        e.campaign_naming,
        e.app_type,
        e.platform,
        e.campaign_business_context,
        e.campaign_strategy_intent,
        e.behavior_type,
        e.medium,
        e.campaign_landing_page,
        e.source,
        e.dict_source,
        e.is_logged_in,
        e.is_lost_tracking_channel,
        e.is_direct_channel,
        e.ts_event,
        e.year,
        e.month,
        e.day
    FROM
        pre_conversion_device AS u
    JOIN
        datalake_agent_acquisition.prospect_agent_funnel_events AS e
            ON u.id_tof_user = e.id_tof_user
),
prospect_events_touchpoint AS (
    SELECT
        e.id_tof_user,
        u.id_user,
        e.id_device,
        e.sk_media_setup,
        u.uuid_person,
        e.event_type,
        e.campaign_naming,
        e.app_type,
        e.platform,
        e.campaign_business_context,
        e.campaign_strategy_intent,
        e.behavior_type,
        e.medium,
        e.campaign_landing_page,
        e.source,
        e.dict_source,
        e.is_logged_in,
        ROW_NUMBER() OVER (
            PARTITION BY u.id_user
            ORDER BY
                IF(e.event_type IN ('pending_analysis_success_screen_viewed'), 1, 0) DESC,
                e.is_lost_tracking_channel,
                e.is_direct_channel,
                e.ts_event DESC
        ) = 1 AS is_last_touchpoint,
        u.ts_created AS ts_event,
        YEAR(u.ts_created) AS year,
        MONTH(u.ts_created) AS month,
        DAY(u.ts_created) AS day
    FROM
        prospect_user AS u
    JOIN
        datalake_agent_acquisition.prospect_agent_funnel_events AS e
            ON u.uuid_person = e.uuid_person
            AND e.ts_event <= u.ts_created
),
demand_supply_acquisition AS (
    SELECT
        CAST(sfu.id_external AS BIGINT) AS id_user,
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
        CAST(fl.id_user AS BIGINT) AS id_user,
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
),
union_funnel_events AS (
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
        ROW_NUMBER() OVER (
            PARTITION BY events.id_tof_user
            ORDER BY
                events.is_lost_tracking_channel,
                events.is_direct_channel,
                events.ts_event DESC
        ) = 1 AS is_last_touchpoint,
        events.ts_event,
        events.year,
        events.month,
        events.day
    FROM
        pre_conversion_events_touchpoint AS events
    WHERE
        events.event_type = 'ub_page_view'

    UNION

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
        ROW_NUMBER() OVER (
            PARTITION BY events.id_tof_user
            ORDER BY
                events.is_lost_tracking_channel,
                events.is_direct_channel,
                events.ts_event DESC
        ) = 1 AS is_last_touchpoint,
        events.ts_event,
        events.year,
        events.month,
        events.day
    FROM
        pre_conversion_events_touchpoint AS events
    LEFT JOIN
        pre_conversion_events_touchpoint AS excp
            ON excp.id_tof_user = events.id_tof_user
            AND excp.event_type IN ("partner_agent_active_status_viewed", "agent_pending_status_viewed", "agent_inactive_status_viewed")
    WHERE
        events.event_type IN ('welcome_screen_viewed', 'personal_data_screen_viewed')
        AND excp.id_tof_user IS NULL

    UNION

    SELECT -- MoF – Sign-up completed
        events.id_user,
        events.id_tof_user,
        events.id_device,
        events.uuid_person,
        "MoF" AS funnel_step,
        "Sign-up completed" AS substep,
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
        events.is_last_touchpoint,
        events.ts_event,
        events.year,
        events.month,
        events.day
    FROM
        prospect_events_touchpoint AS events

    UNION

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
        events.is_last_touchpoint,
        pu.ts_contract_signed AS ts_event,
        YEAR(pu.ts_contract_signed) AS year,
        MONTH(pu.ts_contract_signed) AS month,
        DAY(pu.ts_contract_signed) AS day
    FROM
        prospect_user AS pu
    LEFT JOIN
        prospect_events_touchpoint AS events
            ON pu.uuid_person = events.uuid_person
    WHERE
        pu.contract_signature_status = "COMPLETED"

    UNION

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
        events.is_last_touchpoint,
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
        prospect_events_touchpoint AS events
            ON pu.uuid_person = events.uuid_person

    UNION

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
        events.is_last_touchpoint,
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
        prospect_events_touchpoint AS events
            ON pu.uuid_person = events.uuid_person
    WHERE
        ca.is_first_capacity_activation IS TRUE
)
SELECT
    COALESCE(events.id_tof_user, CAST(events.id_user AS STRING)) AS id_tof_user,
    events.id_user,
    events.id_device,
    events.uuid_person,
    events.funnel_step,
    events.substep,
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
    union_funnel_events AS events
WHERE
    events.is_last_touchpoint IS TRUE
    AND DATE(events.ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')