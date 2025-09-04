WITH
    visit_log AS (
        SELECT
            id_visit,
            MAX_BY(id_schedule, ts_created) AS last_id_schedule,
            SUM(1) FILTER (WHERE event_type = 'VISIT_RESCHEDULED') AS nbr_reschedule,
            MIN(on_behalf_of) FILTER (WHERE event_type = 'VISIT_REQUESTED') AS visit_request_on_behalf_of,
            MIN(author_user_role) FILTER (WHERE event_type = 'VISIT_REQUESTED') AS visit_request_user_role,
            MIN(id_author_user) FILTER (WHERE event_type = 'VISIT_REQUESTED') AS id_user_visit_request,
            MAX(ts_created) FILTER (WHERE event_type = 'VISIT_RESCHEDULED') AS ts_visit_rescheduled,
            MIN(ts_created) FILTER (WHERE event_type = 'VISIT_RESCHEDULED') AS ts_visit_first_rescheduled,
            MIN(ts_created) FILTER (WHERE event_type = 'VISIT_DONE') AS ts_visit_done,
            MIN(ts_created) FILTER (WHERE event_type = 'VISIT_UNSUCCESSFUL') AS ts_visit_unsuccessful,
            MIN(ts_created) FILTER (WHERE event_type = 'VISIT_REGISTERED') AS ts_visit_registered,
            MIN(ts_created) FILTER (WHERE event_type = 'VISIT_FITTED') AS ts_visit_fitted,
            MIN(author_user_role) FILTER (WHERE event_type = 'VISIT_REGISTERED') AS author_role_visit_registered,
            MIN(ts_created) FILTER (WHERE event_type = 'FOLLOW_UP_COLLECTED') AS ts_visit_fup_collected,
            MIN(ts_created) FILTER (WHERE event_type = 'VISIT_STALLED') AS ts_visit_stalled,
            MIN(ts_created) FILTER (WHERE event_type = 'VISIT_CONFIRMED') AS ts_visit_first_confirmed,
            MAX(ts_created) FILTER (WHERE event_type = 'VISIT_CONFIRMED') AS ts_visit_last_confirmed,
            MIN_BY(channel, ts_created) FILTER (WHERE event_type = 'VISIT_CONFIRMED') AS visit_first_confirmed_channel,
            MIN_BY(author_user_role, ts_created) FILTER (WHERE event_type = 'VISIT_CONFIRMED') AS visit_first_confirmed_user_role,
            MIN(ts_created) FILTER (WHERE event_type IN ('ANSWER_CONFIRMED', 'ANSWER_REJECTED') AND on_behalf_of = 'SUPPLY') AS ts_visit_supply_answer,
            MIN(ts_created) FILTER (WHERE event_type IN ('ANSWER_CONFIRMED', 'ANSWER_REJECTED') AND on_behalf_of = 'DEMAND') AS ts_visit_demand_answer,
            MIN(ts_created) FILTER (WHERE event_type IN ('ANSWER_CONFIRMED', 'ANSWER_REJECTED') AND on_behalf_of = 'AGENT') AS ts_visit_agent_answer,
            MIN(ts_created) FILTER (WHERE event_type IN ('ANSWER_CONFIRMED', 'ANSWER_REJECTED') AND on_behalf_of = 'TENANT_LIVING') AS ts_visit_tenant_answer,
            MIN(ts_created) FILTER (WHERE event_type = 'ANSWER_CONFIRMED' AND on_behalf_of = 'SUPPLY') AS ts_visit_supply_confirmed,
            MIN(ts_created) FILTER (WHERE event_type = 'ANSWER_CONFIRMED' AND on_behalf_of = 'DEMAND') AS ts_visit_demand_confirmed,
            MIN(ts_created) FILTER (WHERE event_type = 'ANSWER_CONFIRMED' AND on_behalf_of = 'AGENT') AS ts_visit_agent_confirmed,
            MIN(ts_created) FILTER (WHERE event_type = 'ANSWER_CONFIRMED' AND on_behalf_of = 'TENANT_LIVING') AS ts_visit_tenant_confirmed,
            MIN(ts_created) FILTER (WHERE event_type = 'VISIT_BOOKED' OR event_type = 'VISIT_CONFIRMED') AS ts_visit_confirmed,
            MAX(ts_created) FILTER (WHERE event_type = 'ANSWER_PENDING' AND on_behalf_of = 'TENANT_LIVING') AS ts_visit_pending_tenant_answer,
            MIN(ts_created) AS ts_first_event,
            MAX(ts_created) AS ts_last_event,
            MIN_BY(event_type, ts_created) AS first_event,
            MAX_BY(event_type, ts_created) AS last_event,
            MIN_BY(event_type, ts_created) FILTER (WHERE event_type IN ('ANSWER_CONFIRMED', 'ANSWER_REJECTED') AND on_behalf_of = 'SUPPLY') AS first_supply_answer,
            MIN_BY(channel, ts_created) FILTER (WHERE event_type IN ('ANSWER_CONFIRMED', 'ANSWER_REJECTED') AND on_behalf_of = 'SUPPLY') AS first_supply_answer_channel,
            MIN_BY(event_type, ts_created) FILTER (WHERE event_type IN ('ANSWER_CONFIRMED', 'ANSWER_REJECTED') AND on_behalf_of = 'TENANT_LIVING') AS first_tenant_living_answer,
            MIN_BY(channel, ts_created) FILTER (WHERE event_type IN ('ANSWER_CONFIRMED', 'ANSWER_REJECTED') AND on_behalf_of = 'TENANT_LIVING') AS first_tenant_living_answer_channel
        FROM
            datalake_ebdb_clean.visit_status_log
        GROUP BY
            id_visit
    ),
    visit_3p_demand_agent AS (
        SELECT
            v.id AS id_visit,
            wc.id_company_hubspot AS id_company_demand,
            wc.3p_partner AS partner_3p_demand
        FROM
            datalake_ebdb_agents.agent_contract AS ac
        JOIN
            datalake_ebdb_clean.visit AS v
                ON v.ts_created BETWEEN ac.ts_work_contract_started
                AND COALESCE(ac.ts_work_contract_ended, CURRENT_TIMESTAMP)
                AND ac.id_agent = v.id_agent
        JOIN
            datalake_ebdb_work_contract.work_contract AS wc
                ON wc.id = ac.id_work_contract
        WHERE
            is_3p_contract
        GROUP BY 1,2,3
    ),
    visit_by_history AS (
        SELECT
            id_visit,
            COUNT(DISTINCT id_agent) AS nbr_agent,
            MIN_BY(id_agent, rev) AS id_first_associated_agent,
            MAX_BY(id_agent, rev) AS id_last_associated_agent,
            MIN_BY(ts_visit, rev) AS ts_first_visit
        FROM
            datalake_ebdb_clean.visit_aud
        GROUP BY 1
    )
SELECT
    visit.id AS id_visit,
    visit.id_agent,
    visit.id_visitor,
    lh.id_user AS id_owner,
    visit.id_house,
    COALESCE(hl.id_house_listing, -1) AS id_house_listing,
    -1 AS id_rent_flow,
    -1 AS id_sale_flow,
    lh.id_company_hubspot AS id_company_supply,
    lh.uuid_company AS uuid_company_supply,
    visit_demand.id_company_demand,
    -1 AS id_follow_up,
    -1 AS id_entrance_type,
    vbh.id_first_associated_agent,
    vbh.id_last_associated_agent,
    visit_log.id_user_visit_request,
    visit.code,
    visit.type,
    hl.country_code,
    lh.partner_3p_supply,
    visit_demand.partner_3p_demand,
    visit.status,
    visit.computed_status,
    visit.behavior,
    visit.booking_type,
    vbm.business_model,
    CASE
        WHEN SPLIT_PART(REPLACE(vbm.business_model, 'LEAD_GEN', 'LEADGEN'), '_', 2) = '1P' THEN '1P'
        WHEN SPLIT_PART(REPLACE(vbm.business_model, 'LEAD_GEN', 'LEADGEN'), '_', 5) = 'SUPPLY' THEN SPLIT_PART(REPLACE(vbm.business_model, 'LEAD_GEN', 'LEADGEN'), '_', 4)
        WHEN SPLIT_PART(REPLACE(vbm.business_model, 'LEAD_GEN', 'LEADGEN'), '_', 3) = 'SUPPLY' THEN SPLIT_PART(REPLACE(vbm.business_model, 'LEAD_GEN', 'LEADGEN'), '_', 2)
    END AS business_model_supply,
    CASE
        WHEN SPLIT_PART(REPLACE(vbm.business_model, 'LEAD_GEN', 'LEADGEN'), '_', 2) = '1P' THEN '1P'
        WHEN SPLIT_PART(REPLACE(vbm.business_model, 'LEAD_GEN', 'LEADGEN'), '_', 3) = 'DEMAND' OR SPLIT_PART(REPLACE(vbm.business_model, 'LEAD_GEN', 'LEADGEN'), '_', 3) = 'LEADGEN' THEN SPLIT_PART(REPLACE(vbm.business_model, 'LEAD_GEN', 'LEADGEN'), '_', 2)
        WHEN SPLIT_PART(REPLACE(vbm.business_model, 'LEAD_GEN', 'LEADGEN'), '_', 5) = 'DEMAND' THEN SPLIT_PART(REPLACE(vbm.business_model, 'LEAD_GEN', 'LEADGEN'), '_', 4)
    END AS business_model_demand,
    visit_log.first_event,
    CASE
        WHEN visit_log.ts_visit_fup_collected IS NOT NULL THEN 'FOLLOW_UP_COLLECTED'
        WHEN visit_log.ts_visit_fup_collected IS NULL
             AND visit_log.ts_visit_registered IS NOT NULL THEN 'VISIT_REGISTERED'
        ELSE visit_log.last_event
    END AS last_event,
    visit.slot,
    visit.slot_count,
    visit.business_context,
    COALESCE(ct.default_timezone, 'UTC') AS default_timezone,
    visit_cancellation.reason AS cancellation_reason,
    visit_cancellation.on_behalf_of AS cancellation_on_behalf_of,
    visit_cancellation.channel AS cancellation_channel,
    visit_cancellation.author_user_role AS cancellation_author_role,
    visit_unsuccessful.reason AS unsuccessful_reason,
    CASE
        WHEN visit_log.ts_visit_registered IS NOT NULL THEN 'REGISTERED'
        WHEN visit_log.ts_visit_fitted IS NOT NULL THEN 'FITTED'
        ELSE 'STANDARD'
    END AS visit_model,
    CASE
        WHEN visit.ts_visit = vbh.ts_first_visit THEN 'NOT_CHANGED'
        WHEN visit.ts_visit > vbh.ts_first_visit THEN 'POSTPONED'
        ELSE 'EARLY'
    END AS visit_schedule_type,
    v_origin.visit_request_channel,
    visit_log.visit_request_on_behalf_of,
    visit_log.visit_request_user_role,
    visit_log.first_supply_answer_channel,
    visit_log.first_supply_answer,
    visit_log.first_tenant_living_answer,
    visit_log.first_tenant_living_answer_channel,
    visit_log.visit_first_confirmed_channel,
    visit_log.visit_first_confirmed_user_role,
    CASE
      WHEN visit_log.nbr_reschedule IS NULL THEN 0
      ELSE visit_log.nbr_reschedule
    END AS nbr_reschedule,
    vbh.nbr_agent,
    DATEDIFF(DAY, visit_log.ts_first_event, visit_log.ts_last_event) AS journey_days,
    DATEDIFF(HOUR, visit_log.ts_first_event, visit_log.ts_visit_supply_answer) AS hours_waiting_for_answers,
    DATEDIFF(DAY, visit_log.ts_first_event, visit_log.ts_visit_supply_answer) AS days_waiting_for_answers,
    CASE
        WHEN vbh.nbr_agent > 1 THEN TRUE
        ELSE FALSE
    END AS has_more_one_agent,
    IF(visit_log.ts_visit_confirmed IS NOT NULL, TRUE, FALSE) AS is_confirmed,
    visit_log.ts_visit_registered IS NOT NULL AS is_registered,
    IF(visit_log.ts_visit_done IS NOT NULL, TRUE, FALSE) AS is_completed,
    IF(nbr_reschedule >= 1, TRUE, FALSE) AS is_reschedule,
    IF(visit_cancellation.ts_created IS NOT NULL, TRUE, FALSE) AS is_canceled,
    IF(visit_log.ts_visit_unsuccessful IS NOT NULL, TRUE, FALSE) AS is_unsuccessful,
    IF(visit_log.author_role_visit_registered = 'AGENT', TRUE, FALSE) AS is_registered_by_agent,
    IF(visit_log.ts_visit_fup_collected IS NOT NULL, TRUE, FALSE) AS has_fup_collected,
    IF(visit_log.ts_visit_stalled IS NOT NULL, TRUE, FALSE) AS is_stalled,
    CASE
        WHEN business_model_demand = '3P' THEN TRUE
        WHEN business_model_demand = '1P' THEN FALSE
    END AS is_3p_demand,
    CASE
        WHEN business_model_supply = '3P' THEN TRUE
        WHEN business_model_supply = '1P' THEN FALSE
    END AS is_3p_supply,
    IF(pfa.id_pfa_history IS NOT NULL, TRUE, FALSE) AS is_fixed_agent,
    IF(computed_status IN ('DONE','CANCELED','REQUEST_CANCELED','UNSUCCESSFUL','STALLED'), TRUE, FALSE) AS has_finisher_status,
    CASE
        WHEN visit_log.ts_visit_tenant_answer IS NOT NULL
             OR visit_log.ts_visit_pending_tenant_answer IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS has_tenant_living,
    visit_log.last_event = 'ANSWER_PENDING' AS is_waiting_for_response,
    FALSE AS has_entrance_problem,
    visit_log.ts_visit_supply_answer IS NOT NULL AS has_supply_answered,
    visit_log.ts_visit_supply_confirmed IS NOT NULL AS has_supply_confirmed,
    visit_log.ts_visit_tenant_answer IS NOT NULL AS has_tenant_answered,
    visit_log.ts_visit_tenant_confirmed IS NOT NULL AS has_tenant_confirmed,
    visit_cancellation.is_cancelled_by_expiration,
    visit_unsuccessful.has_demand_attended AS has_unsuccessful_demand_attended,
    visit_unsuccessful.has_agent_attended AS has_unsuccessful_agent_attended,
    visit_unsuccessful.has_supply_attended AS has_unsuccessful_supply_attended,
    visit.dt_visit,
    TO_UTC_TIMESTAMP(
        (
            CAST(visit.dt_visit AS TIMESTAMP)
            + FLOOR((visit.slot * 15 / 60)+8) * INTERVAL 1 HOURS
            + ABS(visit.slot * 15 % 60) * INTERVAL 1 MINUTES
        ),
        COALESCE(ct.default_timezone, 'UTC')
    ) AS ts_visit_local_tz,
    visit.ts_created,
    visit.ts_updated,
    visit.ts_visit,
    visit_log.ts_first_event,
    visit_log.ts_last_event,
    v_origin.ts_visit_requested,
    visit_log.ts_visit_registered,
    visit_log.ts_visit_rescheduled,
    visit_log.ts_visit_first_rescheduled,
    visit_log.ts_visit_supply_answer,
    visit_log.ts_visit_demand_answer,
    visit_log.ts_visit_agent_answer,
    visit_log.ts_visit_tenant_answer,
    visit_log.ts_visit_supply_confirmed,
    visit_log.ts_visit_demand_confirmed,
    visit_log.ts_visit_agent_confirmed,
    visit_log.ts_visit_tenant_confirmed,
    visit_log.ts_visit_confirmed,
    visit_log.ts_visit_first_confirmed,
    visit_log.ts_visit_last_confirmed,
    visit_log.ts_visit_fup_collected,
    visit_cancellation.ts_created AS ts_visit_canceled,
    visit_log.ts_visit_done,
    visit_log.ts_visit_unsuccessful,
    visit_log.ts_visit_stalled,
    vbh.ts_first_visit
FROM
    datalake_ebdb_clean.visit AS visit
LEFT JOIN
    datalake_visit.visit_origin_unified AS v_origin
        ON visit.id = v_origin.id_visit
LEFT JOIN
    visit_log
        ON visit.id = visit_log.id_visit
LEFT JOIN
    datalake_ebdb_listing.house AS lh
        ON lh.id = visit.id_house
LEFT JOIN
    datalake_ebdb_listing.house_listing AS hl
      ON visit.id_house = hl.id_house
      AND DATE(visit.ts_created) >= DATE(hl.ts_listing_version_start)
      AND (DATE(visit.ts_created) < DATE(hl.ts_listing_version_end) OR hl.ts_listing_version_end IS NULL)
LEFT JOIN
    visit_3p_demand_agent AS visit_demand
        ON visit.id = visit_demand.id_visit
LEFT JOIN
    datalake_visit.visit_cancellation_unified AS visit_cancellation
        ON visit.id = visit_cancellation.id_visit
LEFT JOIN
    datalake_visit.visit_unsuccessful_unified AS visit_unsuccessful
        ON visit.id = visit_unsuccessful.id_visit
LEFT JOIN
    datalake_ebdb_clean.country AS ct
        ON ct.code = hl.country_code
LEFT JOIN
    visit_by_history AS vbh
        ON visit.id = vbh.id_visit
LEFT JOIN
    datalake_visit.visit_business_model AS vbm
        ON visit.id = vbm.id_visit
LEFT JOIN
    datalake_visit.preferred_fixed_agent_history AS pfa
        ON visit.id_agent = pfa.id_user_agent
        AND visit.id_visitor = pfa.id_visitor
        AND visit.ts_created >= pfa.ts_started
        AND visit.ts_created < COALESCE(pfa.ts_ended, NOW())
        AND pfa.is_enabled
WHERE
    DATE(visit.ts_created) >= '2024-11-01'
