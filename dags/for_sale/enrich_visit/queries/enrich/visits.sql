WITH
    visit_log AS (
        SELECT
            id_visit,
            MAX_BY(id_schedule, ts_created) AS last_id_schedule,
            SUM(1) FILTER (WHERE event_type = 'VISIT_RESCHEDULED') AS nbr_reschedule,
            MIN(ts_created) FILTER (WHERE event_type = 'VISIT_REQUESTED') AS ts_visit_requested,
            MAX(ts_created) FILTER (WHERE event_type = 'VISIT_RESCHEDULED') AS ts_visit_rescheduled,
            MIN(ts_created) FILTER (WHERE event_type IN ('VISIT_REQUEST_CANCELED', 'VISIT_CANCELED')) AS ts_visit_canceled,
            MIN(ts_created) FILTER (WHERE event_type = 'VISIT_DONE') AS ts_visit_done,
            MIN(ts_created) FILTER (WHERE event_type = 'VISIT_UNSUCCESSFUL') AS ts_visit_unsuccessful,
            MIN(ts_created) FILTER (WHERE event_type = 'VISIT_REGISTERED') AS ts_visit_registered,
            MIN(ts_created) FILTER (WHERE event_type = 'FOLLOW_UP_COLLECTED') AS ts_visit_fup_collected,
            MIN(ts_created) FILTER (WHERE event_type IN ('ANSWER_CONFIRMED', 'ANSWER_REJECTED') AND on_behalf_of = 'SUPPLY') AS ts_visit_supply_answer,
            MIN(ts_created) FILTER (WHERE event_type IN ('ANSWER_CONFIRMED', 'ANSWER_REJECTED') AND on_behalf_of = 'DEMAND') AS ts_visit_demand_answer,
            MIN(ts_created) FILTER (WHERE event_type IN ('ANSWER_CONFIRMED', 'ANSWER_REJECTED') AND on_behalf_of = 'AGENT') AS ts_visit_agent_answer,
            MIN(ts_created) FILTER (WHERE event_type IN ('ANSWER_CONFIRMED', 'ANSWER_REJECTED') AND on_behalf_of = 'TENANT_LIVING') AS ts_visit_tenant_answer,
            MIN(ts_created) FILTER (WHERE event_type = 'ANSWER_CONFIRMED' AND on_behalf_of = 'SUPPLY') AS ts_visit_supply_confirmed,
            MIN(ts_created) FILTER (WHERE event_type = 'ANSWER_CONFIRMED' AND on_behalf_of = 'DEMAND') AS ts_visit_demand_confirmed,
            MIN(ts_created) FILTER (WHERE event_type = 'ANSWER_CONFIRMED' AND on_behalf_of = 'AGENT') AS ts_visit_agent_confirmed,
            MIN(ts_created) FILTER (WHERE event_type = 'ANSWER_CONFIRMED' AND on_behalf_of = 'TENANT_LIVING') AS ts_visit_tenant_confirmed,
            MIN(ts_created) FILTER (WHERE event_type = 'VISIT_BOOKED' OR event_type = 'VISIT_CONFIRMED') AS ts_visit_confirmed,
            MIN(ts_created) FILTER (WHERE event_type IN ('VISIT_REQUEST_CANCELED', 'VISIT_CANCELED') AND on_behalf_of = 'SUPPLY') AS ts_visit_supply_canceled,
            MIN(ts_created) FILTER (WHERE event_type IN ('VISIT_REQUEST_CANCELED', 'VISIT_CANCELED') AND on_behalf_of = 'DEMAND') AS ts_visit_demand_canceled,
            MIN(ts_created) FILTER (WHERE event_type IN ('VISIT_REQUEST_CANCELED', 'VISIT_CANCELED') AND on_behalf_of = 'AGENT') AS ts_visit_agent_canceled,
            MIN(ts_created) FILTER (WHERE event_type IN ('VISIT_REQUEST_CANCELED', 'VISIT_CANCELED') AND on_behalf_of = 'TENANT_LIVING') AS ts_visit_tenant_canceled,
            MAX(ts_created) FILTER (WHERE event_type = 'ANSWER_PENDING' AND on_behalf_of = 'TENANT_LIVING') AS ts_visit_pending_tenant_answer,
            MIN(ts_created) AS ts_first_event,
            MAX(ts_created) AS ts_last_event,
            MIN_BY(event_type, ts_created) AS first_event,
            MAX_BY(event_type, ts_created) AS last_event
        FROM
            datalake_ebdb_clean.visit_status_log
        GROUP BY
            id_visit
    ),
    entrance_method AS (
        SELECT
          heh.id_house AS sk_house,
          DATE(heh.ts_entrance_started) AS date_start,
          DATE(COALESCE(heh.ts_entrance_ended, NOW())) AS date_end,
          MAX(heh.key_location) AS method,
          MAX(heh.key_type) AS key_type
        FROM
          datalake_ebdb_listing.house_entrance_history heh
        WHERE
          heh.is_last_status_of_day
          AND heh.ts_entrance_started < NOW()
          AND COALESCE(heh.ts_entrance_ended, NOW()) >= DATE_SUB(NOW(), 400)
        GROUP BY ALL
),
    entrance_method_treatment(
        SELECT
            l.id AS id_house,
            DATE(COALESCE(em.date_start, l.dt_creation)) AS start_date,
            DATE(COALESCE(em.date_end, l.ts_updated)) AS end_date,
            TRIM(LOWER(MAX(COALESCE(em.method, l.key_location)))) AS method
        FROM
           datalake_ebdb_listing.house AS l
        LEFT JOIN
            entrance_method AS em
                ON l.id = em.sk_house
        GROUP BY ALL
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
    visit_cancellation.id AS id_cancellation_detail,
    -1 AS id_follow_up,
    -1 AS id_entrance_type,
    visit.code,
    hl.country_code,
    lh.partner_3p_supply,
    visit_demand.partner_3p_demand,
    visit.status,
    visit.computed_status,
    visit.behavior,
    visit.business_model,
    visit_log.first_event,
    CASE emt.method
        WHEN 'frontdoor' THEN 'Front Door'
        WHEN 'keyswithagent' THEN 'Keys with Agent'
        WHEN 'lockbox' THEN 'Lockbox'
        WHEN 'password' THEN 'Password'
        WHEN 'keyslocker' THEN 'Keys Locker'
        ELSE 'Owner Present'
    END AS method,
    CASE
        WHEN visit_log.ts_visit_fup_collected IS NOT NULL THEN 'FOLLOW_UP_COLLECTED'
        WHEN visit_log.ts_visit_fup_collected IS NULL
             AND visit_log.ts_visit_registered IS NOT NULL THEN 'VISIT_REGISTERED'
        ELSE visit_log.last_event
    END AS last_event,
    visit.slot,
    business_context,
    COALESCE(ct.default_timezone, 'UTC') AS default_timezone,
    visit_cancellation.reason AS cancellation_reason,
    visit_cancellation.on_behalf_of AS cancellation_on_behalf_of,
    CASE
      WHEN visit_log.nbr_reschedule IS NULL THEN 0
      ELSE visit_log.nbr_reschedule
    END AS nbr_reschedule,
    DATEDIFF(DAY, visit_log.ts_first_event, visit_log.ts_last_event) AS journey_days,
    DATEDIFF(HOUR, visit_log.ts_first_event, visit_log.ts_visit_supply_answer) AS hours_waiting_for_answers,
    DATEDIFF(DAY, visit_log.ts_first_event, visit_log.ts_visit_supply_answer) AS days_waiting_for_answers,
    visit_log.ts_visit_confirmed IS NOT NULL AS is_confirmed,
    visit.computed_status = 'DONE'  AS is_completed,
    IF(nbr_reschedule >= 1, TRUE, FALSE) AS is_reschedule,
    visit.status = 'Canceled' AS is_canceled,
    visit.computed_status = 'UNSUCCESSFUL' AS is_unsuccessful,
    IF(visit_demand.id_visit IS NOT NULL, TRUE, FALSE) AS is_3p_demand,
    FALSE AS is_3p_supply,
    visit.is_fixed_agent,
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
    TO_UTC_TIMESTAMP(
        (
            CAST(visit.dt_visit AS TIMESTAMP)
            + FLOOR((visit.slot * 15 / 60)+8) * INTERVAL 1 HOURS
            + ABS(visit.slot * 15 % 60) * INTERVAL 1 MINUTES
        ),
        COALESCE(ct.default_timezone, 'UTC')
    ) AS ts_visit_local_tz,
    visit_log.ts_first_event AS ts_created,
    visit_log.ts_last_event AS ts_updated,
    visit_log.ts_visit_requested,
    visit_log.ts_visit_registered,
    visit_log.ts_visit_rescheduled,
    visit_log.ts_visit_supply_answer,
    visit_log.ts_visit_demand_answer,
    visit_log.ts_visit_agent_answer,
    visit_log.ts_visit_tenant_answer,
    visit_log.ts_visit_supply_confirmed,
    visit_log.ts_visit_demand_confirmed,
    visit_log.ts_visit_agent_confirmed,
    visit_log.ts_visit_tenant_confirmed,
    visit_log.ts_visit_confirmed,
    visit_log.ts_visit_fup_collected,
    visit_log.ts_visit_canceled,
    visit_log.ts_visit_done,
    visit_log.ts_visit_unsuccessful
FROM
    datalake_ebdb_clean.visit AS visit
INNER JOIN
    visit_log
        ON visit.id = visit_log.id_visit
LEFT JOIN
    datalake_ebdb_listing.house AS lh
        ON lh.id = visit.id_house
LEFT JOIN
    datalake_ebdb_listing.house_listing AS hl
      ON visit.id_house = hl.id_house
      AND DATE(visit.ts_created) >= DATE(hl.ts_listing_version_start)
      AND (DATE(visit.ts_created) <= DATE(hl.ts_listing_version_end) OR hl.ts_listing_version_end IS NULL)
LEFT JOIN
    visit_3p_demand_agent AS visit_demand
        ON visit.id = visit_demand.id_visit
LEFT JOIN
    datalake_ebdb_clean.visit_cancellation_details AS visit_cancellation
        ON visit.id = visit_cancellation.id_visit
LEFT JOIN
    datalake_ebdb_clean.country AS ct
        ON ct.code = hl.country_code
LEFT JOIN
    entrance_method_treatment AS emt
        ON visit.id_house = emt.id_house
        AND visit.dt_visit >= emt.start_date
        AND visit.dt_visit < emt.end_date
WHERE
    DATE(visit.ts_created) >= '2024-11-01'
