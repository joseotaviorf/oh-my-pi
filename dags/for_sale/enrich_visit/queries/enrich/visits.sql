WITH
    visit_log AS (
        WITH vsl AS (
            SELECT
                vse.id_visit,
                MAX(vse.id_schedule) AS id_last_schedule,
                SUM(1) FILTER (WHERE vse.event_type = 'VISIT_RESCHEDULED') AS nbr_reschedule,
                MIN(vse.ts_created) FILTER (WHERE vse.event_type IN ('VISIT_RESCHEDULED', 'VISIT_REQUESTED') AND vse.channel IN ('AGENT_PWA', 'AGENT_NATIVE')) AS ts_visit_scheduled_by_agent,
                MIN_BY(vse.id_user_agent_by_event, vse.ts_created) FILTER (WHERE vse.event_type IN ('VISIT_RESCHEDULED', 'VISIT_REQUESTED') AND vse.channel IN ('AGENT_PWA', 'AGENT_NATIVE')) AS id_user_agent_scheduled_by_agent,
                MIN(vse.on_behalf_of) FILTER (WHERE vse.event_type = 'VISIT_REQUESTED') AS visit_request_on_behalf_of,
                MIN(vse.author_user_role) FILTER (WHERE vse.event_type = 'VISIT_REQUESTED') AS visit_request_user_role,
                MIN(vse.id_author_user) FILTER (WHERE vse.event_type = 'VISIT_REQUESTED') AS id_user_visit_request,
                MAX(vse.ts_created) FILTER (WHERE vse.event_type = 'VISIT_RESCHEDULED') AS ts_visit_rescheduled,
                MIN(vse.ts_created) FILTER (WHERE vse.event_type = 'VISIT_RESCHEDULED') AS ts_visit_first_rescheduled,
                MIN(vse.ts_created) FILTER (WHERE vse.event_type = 'VISIT_REGISTERED') AS ts_visit_registered,
                MIN(vse.ts_created) FILTER (WHERE vse.event_type = 'VISIT_FITTED') AS ts_visit_fitted,
                MIN(vse.ts_created) FILTER (WHERE vse.event_type = 'VISIT_STALLED') AS ts_visit_stalled,
                MIN(vse.ts_created) FILTER (WHERE vse.event_type = 'VISIT_CONFIRMED') AS ts_visit_first_confirmed,
                MAX(vse.ts_created) FILTER (WHERE vse.event_type = 'VISIT_CONFIRMED') AS ts_visit_last_confirmed,
                MIN_BY(vse.channel, vse.ts_created) FILTER (WHERE vse.event_type = 'VISIT_CONFIRMED') AS visit_first_confirmed_channel,
                MIN_BY(vse.author_user_role, vse.ts_created) FILTER (WHERE vse.event_type = 'VISIT_CONFIRMED') AS visit_first_confirmed_user_role,
                MIN(vse.ts_created) FILTER (WHERE vse.event_type IN ('ANSWER_CONFIRMED', 'ANSWER_REJECTED') AND vse.on_behalf_of = 'SUPPLY') AS ts_visit_supply_answer,
                MIN(vse.ts_created) FILTER (WHERE vse.event_type IN ('ANSWER_CONFIRMED', 'ANSWER_REJECTED') AND vse.on_behalf_of = 'DEMAND') AS ts_visit_demand_answer,
                MIN(vse.ts_created) FILTER (WHERE vse.event_type IN ('ANSWER_CONFIRMED', 'ANSWER_REJECTED') AND vse.on_behalf_of = 'AGENT') AS ts_visit_agent_answer,
                MIN(vse.ts_created) FILTER (WHERE vse.event_type IN ('ANSWER_CONFIRMED', 'ANSWER_REJECTED') AND vse.on_behalf_of = 'TENANT_LIVING') AS ts_visit_tenant_answer,
                MIN(vse.ts_created) FILTER (WHERE vse.event_type = 'ANSWER_CONFIRMED' AND vse.on_behalf_of = 'SUPPLY') AS ts_visit_supply_confirmed,
                MIN(vse.ts_created) FILTER (WHERE vse.event_type = 'ANSWER_CONFIRMED' AND vse.on_behalf_of = 'DEMAND') AS ts_visit_demand_confirmed,
                MIN(vse.ts_created) FILTER (WHERE vse.event_type = 'ANSWER_CONFIRMED' AND vse.on_behalf_of = 'AGENT') AS ts_visit_agent_confirmed,
                MIN(vse.ts_created) FILTER (WHERE vse.event_type = 'ANSWER_CONFIRMED' AND vse.on_behalf_of = 'TENANT_LIVING') AS ts_visit_tenant_confirmed,
                MIN(vse.ts_created) FILTER (WHERE vse.event_type = 'VISIT_BOOKED' OR vse.event_type = 'VISIT_CONFIRMED') AS ts_visit_confirmed,
                MAX(vse.ts_created) FILTER (WHERE vse.event_type = 'ANSWER_PENDING' AND vse.on_behalf_of = 'TENANT_LIVING') AS ts_visit_pending_tenant_answer,
                MIN(vse.ts_created) AS ts_first_event,
                MAX(vse.ts_created) AS ts_last_event,
                MIN_BY(vse.event_type, struct(vse.ts_created, vse.id_visit_status_log)) AS first_event,
                MAX_BY(vse.event_type, struct(vse.ts_created, vse.id_visit_status_log)) AS last_event,
                MIN_BY(vse.event_type, vse.ts_created) FILTER (WHERE vse.event_type IN ('ANSWER_CONFIRMED', 'ANSWER_REJECTED') AND vse.on_behalf_of = 'SUPPLY') AS first_supply_answer,
                MIN_BY(vse.channel, vse.ts_created) FILTER (WHERE vse.event_type IN ('ANSWER_CONFIRMED', 'ANSWER_REJECTED') AND vse.on_behalf_of = 'SUPPLY') AS first_supply_answer_channel,
                MIN_BY(vse.event_type, vse.ts_created) FILTER (WHERE vse.event_type IN ('ANSWER_CONFIRMED', 'ANSWER_REJECTED') AND vse.on_behalf_of = 'TENANT_LIVING') AS first_tenant_living_answer,
                MIN_BY(vse.channel, vse.ts_created) FILTER (WHERE vse.event_type IN ('ANSWER_CONFIRMED', 'ANSWER_REJECTED') AND vse.on_behalf_of = 'TENANT_LIVING') AS first_tenant_living_answer_channel,
                MAX_BY(vse.reason, vse.ts_created) FILTER (WHERE vse.event_type IN ('VISIT_CONTESTED')) AS reason_visit_contested
            FROM
                datalake_visit.visit_status_events AS vse
            JOIN
                datalake_ebdb_clean.visit AS v
                    ON vse.id_visit = v.id
            WHERE
                DATE(v.ts_created) >= '2024-11-01'
            GROUP BY 1
        ),
        bsc AS (
            SELECT
                b.id_visit,
                MAX(bsc.id_booking) AS id_last_schedule,
                MIN_BY(bsc.id_user, struct(bsc.ts_created, bsc.id)) AS id_user_visit_request,
                SUM(1) FILTER (WHERE bsc.reason = 'SCHEDULE_CHANGE') AS nbr_reschedule,
                MAX(bsc.ts_created) FILTER (WHERE bsc.reason = 'SCHEDULE_CHANGE') AS ts_visit_rescheduled,
                MIN(bsc.ts_created) FILTER (WHERE bsc.reason = 'SCHEDULE_CHANGE') AS ts_visit_first_rescheduled,
                MIN(bsc.ts_created) FILTER (WHERE bsc.reason = 'Visita extra de encaixe') AS ts_visit_fitted,
                MIN(bsc.ts_created) FILTER (WHERE bsc.reason = 'AGENT_SCHEDULE_REALIZED') AS ts_visit_registered,
                MIN(bsc.ts_created) FILTER (WHERE bsc.status = 'Marcado') AS ts_visit_first_confirmed,
                MAX(bsc.ts_created) FILTER (WHERE bsc.status = 'Marcado') AS ts_visit_last_confirmed,
                IF(MIN(fup.id_visit) IS NULL AND MIN(vcu.id_visit) IS NULL AND DATEDIFF(NOW(), MIN(v.ts_visit)) >= 3, DATEADD(DAY, 2, MIN(v.ts_visit)), NULL) AS ts_visit_stalled,
                MIN(bsc.ts_created) AS ts_first_event,
                MAX(bsc.ts_created) AS ts_last_event
            FROM
                datalake_ebdb_clean.booking_status_change AS bsc
            LEFT JOIN
                datalake_ebdb_clean.booking AS b
                    ON bsc.id_booking = b.id
            LEFT JOIN
                datalake_ebdb_clean.visit AS v
                    ON b.id_visit = v.id
            LEFT JOIN
                datalake_visit.post_visit_agent_unified AS fup
                    ON fup.id_visit = v.id
            LEFT JOIN
                datalake_visit.visit_cancellation_unified AS vcu
                    ON vcu.id_visit = v.id
            WHERE
                b.type = 'Visita'
                AND DATE(v.ts_created) < '2024-11-01'
            GROUP BY 1
        )
        SELECT
            id_visit,
            id_last_schedule,
            nbr_reschedule,
            ts_visit_scheduled_by_agent,
            id_user_agent_scheduled_by_agent,
            visit_request_on_behalf_of,
            visit_request_user_role,
            id_user_visit_request,
            ts_visit_rescheduled,
            ts_visit_first_rescheduled,
            ts_visit_registered,
            ts_visit_fitted,
            ts_visit_stalled,
            ts_visit_first_confirmed,
            ts_visit_last_confirmed,
            visit_first_confirmed_channel,
            visit_first_confirmed_user_role,
            ts_visit_supply_answer,
            ts_visit_demand_answer,
            ts_visit_agent_answer,
            ts_visit_tenant_answer,
            ts_visit_supply_confirmed,
            ts_visit_demand_confirmed,
            ts_visit_agent_confirmed,
            ts_visit_tenant_confirmed,
            ts_visit_confirmed,
            ts_visit_pending_tenant_answer,
            ts_first_event,
            ts_last_event,
            first_event,
            last_event,
            first_supply_answer,
            first_supply_answer_channel,
            first_tenant_living_answer,
            first_tenant_living_answer_channel,
            reason_visit_contested
        FROM
            vsl
        UNION ALL
        SELECT
            id_visit,
            id_last_schedule,
            nbr_reschedule,
            NULL AS ts_visit_scheduled_by_agent,
            NULL AS id_user_agent_scheduled_by_agent,
            NULL AS visit_request_on_behalf_of,
            NULL AS visit_request_user_role,
            id_user_visit_request,
            ts_visit_rescheduled,
            ts_visit_first_rescheduled,
            ts_visit_registered,
            ts_visit_fitted,
            ts_visit_stalled,
            ts_visit_first_confirmed,
            ts_visit_last_confirmed,
            NULL AS visit_first_confirmed_channel,
            NULL AS visit_first_confirmed_user_role,
            NULL AS ts_visit_supply_answer,
            NULL AS ts_visit_demand_answer,
            NULL AS ts_visit_agent_answer,
            NULL AS ts_visit_tenant_answer,
            NULL AS ts_visit_supply_confirmed,
            NULL AS ts_visit_demand_confirmed,
            NULL AS ts_visit_agent_confirmed,
            NULL AS ts_visit_tenant_confirmed,
            NULL AS ts_visit_confirmed,
            NULL AS ts_visit_pending_tenant_answer,
            ts_first_event,
            ts_last_event,
            NULL AS first_event,
            NULL AS last_event,
            NULL AS first_supply_answer,
            NULL AS first_supply_answer_channel,
            NULL AS first_tenant_living_answer,
            NULL AS first_tenant_living_answer_channel,
            NULL AS reason_visit_contested
        FROM
            bsc
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
    ),
    last_booking_status AS (
        SELECT
            b.id_visit,
            MAX_BY(b.status, b.ts_created) AS last_status
        FROM
            datalake_ebdb_clean.booking AS b
        LEFT JOIN
            datalake_ebdb_clean.visit AS v
                ON v.id = b.id_visit
        WHERE
            DATE(v.ts_created) < '2024-11-01'
            AND b.type = 'Visita'
        GROUP BY 1
    ),
window_visits AS (
    SELECT
        visit.id AS id_visit,
        visit_log.id_last_schedule,
        visit.id_agent,
        visit.id_visitor,
        lh.id_user AS id_owner,
        visit.id_house,
        COALESCE(hl.id_house_listing, -1) AS id_house_listing,
        -1 AS id_rent_flow,
        -1 AS id_sale_flow,
        vbm.sk_broker_supply,
        vbm.sk_broker_demand,
        vbm.id_company_supply,
        lh.uuid_company AS uuid_company_supply,
        vbm.id_company_demand,
        -1 AS id_follow_up,
        vbh.id_first_associated_agent,
        vbh.id_last_associated_agent,
        CASE
            WHEN v_origin.visit_request_application_source = 'AGENT_SCHEDULING_LINK' OR visit_log.ts_visit_registered IS NOT NULL THEN vbh.id_first_associated_agent
            WHEN visit_log.ts_visit_scheduled_by_agent IS NOT NULL THEN COALESCE(visit_log.id_user_agent_scheduled_by_agent, vbh.id_first_associated_agent)
            ELSE NULL
        END AS id_user_agent_vbba,
        visit_log.id_user_visit_request,
        visit.code,
        visit.type,
        hl.country_code,
        vbm.partner_3p_supply,
        vbm.partner_3p_demand,
        vbm.is_3p_supply,
        vbm.is_3p_demand,
        vbm.is_3p_lead_gen,
        vbm.has_3p_access_control,
        visit.status,
        CASE
            WHEN DATE(visit.ts_created) >= '2024-11-01' THEN visit.computed_status
            WHEN DATE(visit.ts_created) < '2024-11-01' AND pva.event_type = 'VISIT_DONE' THEN 'DONE'
            WHEN DATE(visit.ts_created) < '2024-11-01' AND pva.event_type = 'VISIT_UNSUCCESSFUL' THEN 'UNSUCCESSFUL'
            WHEN DATE(visit.ts_created) < '2024-11-01' AND visit_cancellation.id_visit IS NOT NULL THEN 'CANCELED'
            WHEN DATE(visit.ts_created) < '2024-11-01' AND visit_log.ts_visit_stalled IS NOT NULL THEN 'STALLED'
            WHEN DATE(visit.ts_created) < '2024-11-01' AND lbs.last_status = 'AguardandoConfirmacao' THEN 'REQUESTED'
            WHEN DATE(visit.ts_created) < '2024-11-01' AND lbs.last_status = 'Marcado' THEN 'CONFIRMED'
        END AS computed_status_unified,
        computed_status_unified AS computed_status,
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
        visit_log.last_event,
        visit.slot,
        visit.slot_count,
        visit.business_context,
        COALESCE(ct.default_timezone, 'UTC') AS default_timezone,
        visit_cancellation.reason AS cancellation_reason,
        visit_cancellation.on_behalf_of AS cancellation_on_behalf_of,
        visit_cancellation.channel AS cancellation_channel,
        visit_cancellation.type AS cancellation_type,
        visit_cancellation.author_user_role AS cancellation_author_role,
        pva.unsuccessful_reason,
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
        v_origin.visit_request_application_source,
        NULLIF(CONCAT_WS(' - ', v_origin.visit_request_channel, v_origin.visit_request_application_source),'') AS visit_request_source_unified,
        visit_log.first_supply_answer_channel,
        visit_log.first_supply_answer,
        visit_log.first_tenant_living_answer,
        visit_log.first_tenant_living_answer_channel,
        visit_log.visit_first_confirmed_channel,
        visit_log.visit_first_confirmed_user_role,
        pva.channel AS visit_finalization_agent_channel,
        CASE
        WHEN visit_log.nbr_reschedule IS NULL THEN 0
        ELSE visit_log.nbr_reschedule
        END AS nbr_reschedule,
        vbh.nbr_agent,
        DATEDIFF(visit_log.ts_last_event, visit_log.ts_first_event) AS journey_days,
        TIMESTAMPDIFF(HOUR, visit_log.ts_first_event, visit_log.ts_visit_supply_answer) AS hours_waiting_for_answers,
        DATEDIFF(visit_log.ts_visit_supply_answer, visit_log.ts_first_event) AS days_waiting_for_answers,
        CASE
            WHEN vbh.nbr_agent > 1 THEN TRUE
            ELSE FALSE
        END AS has_more_one_agent,
        IF(visit_log.ts_visit_first_confirmed IS NOT NULL, TRUE, FALSE) AS is_confirmed,
        IF(visit_log.ts_visit_last_confirmed >= COALESCE(visit_log.ts_visit_rescheduled, v_origin.ts_visit_requested), TRUE, FALSE) AS is_confirmed_last_schedule,
        visit_log.ts_visit_registered IS NOT NULL AS is_registered,
        visit_log.ts_visit_fitted IS NOT NULL AS is_fitted,
        IF(pva.event_type = 'VISIT_DONE', TRUE, FALSE) AS is_completed,
        IF(nbr_reschedule >= 1, TRUE, FALSE) AS is_reschedule,
        IF(visit_cancellation.ts_created IS NOT NULL, TRUE, FALSE) AS is_canceled,
        IF(pva.event_type = 'VISIT_UNSUCCESSFUL', TRUE, FALSE) AS is_unsuccessful,
        IF(pva.id_visit IS NOT NULL, TRUE, FALSE) AS has_fup_collected,
        IF(visit_log.ts_visit_stalled IS NOT NULL, TRUE, FALSE) AS is_stalled,
        IF(computed_status_unified IN ('DONE','CANCELED','REQUEST_CANCELED','UNSUCCESSFUL','STALLED'), TRUE, FALSE) AS has_finisher_status,
        IF(visit_log.ts_visit_tenant_answer IS NOT NULL OR visit_log.ts_visit_pending_tenant_answer IS NOT NULL, TRUE, NULL) AS has_tenant_living,
        visit_log.last_event = 'ANSWER_PENDING' AS is_waiting_for_response,
        IF(visit_log.ts_visit_scheduled_by_agent IS NOT NULL OR v_origin.visit_request_channel IN ('AGENT_PWA', 'AGENT_NATIVE') OR v_origin.visit_request_application_source = 'AGENT_SCHEDULING_LINK' OR visit_log.ts_visit_registered IS NOT NULL, TRUE, FALSE) AS is_vbba,
        FALSE AS has_entrance_problem,
        IF(visit_log.ts_visit_supply_answer IS NOT NULL, TRUE, NULL) AS has_supply_answered,
        IF(visit_log.ts_visit_supply_confirmed IS NOT NULL, TRUE, NULL) AS has_supply_confirmed,
        IF(visit_log.ts_visit_tenant_answer IS NOT NULL, TRUE, NULL) AS has_tenant_answered,
        IF(visit_log.ts_visit_tenant_confirmed IS NOT NULL, TRUE, NULL) AS has_tenant_confirmed,
        visit_cancellation.is_cancelled_by_expiration,
        pva.has_unsuccessful_demand_not_attended,
        pva.has_unsuccessful_agent_not_attended,
        pva.has_unsuccessful_supply_not_attended,
        DATE(visit.ts_created) = DATE(visit.ts_visit) AS is_visit_same_day_first_schedule,
        COALESCE(DATE(visit_log.ts_visit_rescheduled), DATE(visit.ts_created)) = DATE(visit.ts_visit) AS is_visit_same_day_last_schedule,
        IF(visit_log.reason_visit_contested = 'WRONG_VISIT_DONE_STATUS', TRUE, FALSE) AS is_completed_visit_contested_by_demand,
        IF(visit_log.reason_visit_contested = 'WRONG_CANCELLATION_REASON', TRUE, FALSE) AS is_canceled_visit_contested_by_demand,
        IF(visit_log.reason_visit_contested IS NOT NULL, TRUE, FALSE) AS is_visit_contested_by_demand,
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
        pva.ts_post_visit_agent AS ts_visit_fup_collected,
        visit_cancellation.ts_created AS ts_visit_canceled,
        IF(pva.event_type = 'VISIT_DONE', pva.ts_post_visit_agent, NULL) AS ts_visit_done,
        IF(pva.event_type = 'VISIT_UNSUCCESSFUL', pva.ts_post_visit_agent, NULL) AS ts_visit_unsuccessful,
        visit_log.ts_visit_stalled,
        vbh.ts_first_visit,
        LAG(CASE WHEN pva.event_type = 'VISIT_DONE' THEN visit.ts_visit END, 1) IGNORE NULLS OVER(PARTITION BY visit.id_house ORDER BY visit.ts_visit, visit.ts_created) AS ts_visit_last_visit_done_of_house,
        LAG(CASE WHEN pva.event_type = 'VISIT_DONE' THEN visit.ts_visit END, 1) IGNORE NULLS OVER(PARTITION BY visit.id_visitor ORDER BY visit.ts_visit, visit.ts_created) AS ts_visit_last_visit_done_of_visitor,
        LAG(CASE WHEN pva.event_type = 'VISIT_DONE' THEN visit.ts_visit ELSE NULL END, 1) IGNORE NULLS OVER(PARTITION BY visit.id_house, visit.id_visitor ORDER BY visit.ts_visit, visit.ts_created) AS ts_visit_last_visit_done_of_house_and_visitor,
        LAG(CASE WHEN visit_cancellation.ts_created IS NOT NULL OR pva.event_type = 'VISIT_UNSUCCESSFUL' THEN COALESCE(visit_cancellation.ts_created, pva.ts_post_visit_agent) END, 1) OVER(PARTITION BY visit.id_house, visit.id_visitor ORDER BY visit.ts_created) AS ts_last_frustrated_visit_house_and_visitor,
        DATEDIFF(visit.ts_created, ts_last_frustrated_visit_house_and_visitor) AS days_between_frustration_and_retry,
        IF(ts_last_frustrated_visit_house_and_visitor IS NOT NULL AND days_between_frustration_and_retry <= 2, 0, 1) AS new_cycle
    FROM
        datalake_ebdb_clean.visit AS visit
    LEFT JOIN
        datalake_visit.visit_origin_unified AS v_origin
            ON visit.id = v_origin.id_visit
    LEFT JOIN
        visit_log
            ON visit.id = visit_log.id_visit
    LEFT JOIN
        last_booking_status AS lbs
            ON visit.id = lbs.id_visit
    LEFT JOIN
        datalake_ebdb_listing.house AS lh
            ON lh.id = visit.id_house
    LEFT JOIN
        datalake_ebdb_listing.house_listing AS hl
        ON visit.id_house = hl.id_house
        AND DATE(visit.ts_created) >= DATE(hl.ts_listing_version_start)
        AND (DATE(visit.ts_created) < DATE(hl.ts_listing_version_end) OR hl.ts_listing_version_end IS NULL)
    LEFT JOIN
        datalake_visit.visit_business_model AS vbm
            ON visit.id = vbm.id_visit
    LEFT JOIN
        datalake_visit.visit_cancellation_unified AS visit_cancellation
            ON visit.id = visit_cancellation.id_visit
    LEFT JOIN
        datalake_visit.post_visit_agent_unified AS pva
            ON visit.id = pva.id_visit
    LEFT JOIN
        datalake_ebdb_clean.country AS ct
            ON ct.code = hl.country_code
    LEFT JOIN
        visit_by_history AS vbh
            ON visit.id = vbh.id_visit
)
SELECT
    id_visit,
    id_last_schedule,
    SUM(new_cycle) OVER(
        PARTITION BY id_house, id_visitor
        ORDER BY ts_created
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS id_visit_cycle,
    CONCAT_WS('-', id_house, id_visitor, id_visit_cycle) AS id_visit_attempt_cycle,
    id_agent,
    id_visitor,
    id_owner,
    id_house,
    id_house_listing,
    id_rent_flow,
    id_sale_flow,
    sk_broker_supply,
    sk_broker_demand,
    id_company_supply,
    uuid_company_supply,
    id_company_demand,
    id_follow_up,
    id_first_associated_agent,
    id_last_associated_agent,
    id_user_agent_vbba,
    id_user_visit_request,
    code,
    type,
    country_code,
    partner_3p_supply,
    partner_3p_demand,
    is_3p_supply,
    is_3p_demand,
    is_3p_lead_gen,
    has_3p_access_control,
    status,
    computed_status_unified,
    computed_status,
    behavior,
    booking_type,
    business_model,
    business_model_supply,
    business_model_demand,
    first_event,
    last_event,
    slot,
    slot_count,
    business_context,
    default_timezone,
    cancellation_reason,
    cancellation_on_behalf_of,
    cancellation_channel,
    cancellation_type,
    cancellation_author_role,
    unsuccessful_reason,
    visit_model,
    visit_schedule_type,
    visit_request_channel,
    visit_request_on_behalf_of,
    visit_request_user_role,
    visit_request_application_source,
    visit_request_source_unified,
    first_supply_answer_channel,
    first_supply_answer,
    first_tenant_living_answer,
    first_tenant_living_answer_channel,
    visit_first_confirmed_channel,
    visit_first_confirmed_user_role,
    visit_finalization_agent_channel,
    nbr_reschedule,
    nbr_agent,
    journey_days,
    hours_waiting_for_answers,
    days_waiting_for_answers,
    has_more_one_agent,
    is_confirmed,
    is_confirmed_last_schedule,
    is_registered,
    is_fitted,
    is_completed,
    is_reschedule,
    is_canceled,
    is_unsuccessful,
    has_fup_collected,
    is_stalled,
    has_finisher_status,
    has_tenant_living,
    is_waiting_for_response,
    is_vbba,
    has_entrance_problem,
    has_supply_answered,
    has_supply_confirmed,
    has_tenant_answered,
    has_tenant_confirmed,
    is_cancelled_by_expiration,
    has_unsuccessful_demand_not_attended,
    has_unsuccessful_agent_not_attended,
    has_unsuccessful_supply_not_attended,
    is_visit_same_day_first_schedule,
    is_visit_same_day_last_schedule,
    is_completed_visit_contested_by_demand,
    is_canceled_visit_contested_by_demand,
    is_visit_contested_by_demand,
    dt_visit,
    ts_visit_local_tz,
    ts_created,
    ts_updated,
    ts_visit,
    ts_first_event,
    ts_last_event,
    ts_visit_requested,
    ts_visit_registered,
    ts_visit_rescheduled,
    ts_visit_first_rescheduled,
    ts_visit_supply_answer,
    ts_visit_demand_answer,
    ts_visit_agent_answer,
    ts_visit_tenant_answer,
    ts_visit_supply_confirmed,
    ts_visit_demand_confirmed,
    ts_visit_agent_confirmed,
    ts_visit_tenant_confirmed,
    ts_visit_confirmed,
    ts_visit_first_confirmed,
    ts_visit_last_confirmed,
    ts_visit_fup_collected,
    ts_visit_canceled,
    ts_visit_done,
    ts_visit_unsuccessful,
    ts_visit_stalled,
    ts_first_visit,
    ts_visit_last_visit_done_of_house,
    ts_visit_last_visit_done_of_visitor,
    ts_visit_last_visit_done_of_house_and_visitor
FROM
    window_visits
