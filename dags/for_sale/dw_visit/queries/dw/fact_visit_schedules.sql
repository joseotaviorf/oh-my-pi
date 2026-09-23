SELECT
    es.id_schedule AS sk_schedule,
    es.id_visit AS sk_visit,
    es.id_region AS sk_region,
    es.id_visitor AS sk_visitor,
    es.id_owner AS sk_owner,
    es.id_house AS sk_house,
    bc.sk_business_context,
    vm.sk_visit_model,
    svh.id_business_unit AS sk_business_unit,
    COALESCE(es.sk_broker_supply, -1) AS sk_broker_supply,
    COALESCE(es.sk_broker_demand, -1) AS sk_broker_demand,
    es.id_agent AS sk_agent,
    es.id_user_agent AS sk_user_agent,
    es.id_first_agent AS sk_first_agent,
    es.id_first_user_agent AS sk_first_user_agent,
    svh.id_user_en AS sk_user_en,
    pfa.id_agent AS sk_fixed_agent,
    pfa.id_user_agent AS sk_user_fixed_agent,
    ppa.id_house_listing_relation AS sk_ppa_relation,
    es.id_user_creation AS sk_author_creator,
    es.id_user_cancelation AS sk_author_cancelation,
    es.visit_code,
    dim_heh.sk_house_entrance,
    dim_heh_entrance.sk_house_entrance AS sk_house_entrance_visit,
    es.id_succeed_schedule AS sk_succeed_schedule,
    es.days_visit_cancelled_to_visit,
    es.days_visit_booked_to_visit,
    es.days_visit_booked_to_cancelled,
    es.days_visit_booked_to_visit_completed,
    CASE WHEN es.has_tenant_living IS TRUE THEN 1 ELSE 0 END AS has_tenant_living,
    es.is_3p_supply,
    es.is_3p_demand,
    es.is_3p_lead_gen,
    es.has_3p_access_control,
    CASE
        WHEN es.business_context = 'SALE' THEN lst.sale_type
    END AS sale_type,
    1 AS is_booking,
    CASE WHEN es.ts_schedule_rescheduled IS NOT NULL THEN 1 ELSE 0 END AS is_reschedule,
    CASE WHEN es.ts_schedule_confirmed IS NOT NULL THEN 1 ELSE 0 END AS is_confirmed,
    CASE WHEN es.ts_schedule_completed IS NOT NULL THEN 1 ELSE 0 END AS is_completed,
    CASE WHEN es.ts_schedule_canceled IS NOT NULL THEN 1 ELSE 0 END AS is_canceled,
    CASE WHEN es.ts_schedule_unsuccessful IS NOT NULL THEN 1 ELSE 0 END AS is_unsuccessful,
    IF(es.channel_creation IN ('AGENT_PWA', 'AGENT_NATIVE') OR es.application_source_creation = 'AGENT_SCHEDULING_LINK' OR v.is_registered, 1, 0) AS is_schedule_vbba,
    COALESCE(CAST(REPLACE(SUBSTRING(ts_schedule_created, 1, 10), '-', '') AS BIGINT), -1) AS sk_schedule_created,
    COALESCE(CAST(REPLACE(SUBSTRING(ts_schedule_confirmed, 1, 10), '-', '') AS BIGINT), -1) AS sk_schedule_confirmed,
    COALESCE(CAST(REPLACE(SUBSTRING(ts_schedule_completed, 1, 10), '-', '') AS BIGINT), -1) AS sk_schedule_completed,
    COALESCE(CAST(REPLACE(SUBSTRING(ts_schedule_canceled, 1, 10), '-', '') AS BIGINT), -1) AS sk_schedule_canceled,
    COALESCE(CAST(REPLACE(SUBSTRING(ts_schedule_unsuccessful, 1, 10), '-', '') AS BIGINT), -1) AS sk_schedule_unsuccessful,
    ts_schedule_created,
    ts_schedule_confirmed,
    ts_schedule_completed,
    ts_schedule_canceled,
    ts_schedule_unsuccessful,
    ts_schedule_rescheduled,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    datalake_visit.visit_schedules AS es
LEFT JOIN
    datalake_visit.visits AS v
        ON v.id_visit = es.id_visit
LEFT JOIN
    dw_visit.dim_business_context AS bc
        ON es.business_context = bc.business_context
LEFT JOIN
    dw_visit.dim_visit_model AS vm
        ON es.visit_model = vm.visit_model
LEFT JOIN
    dw_house.dim_house_entrance_history AS dim_heh
        ON es.id_house = dim_heh.sk_house
        AND es.ts_schedule_created >= dim_heh.ts_entrance_started
        AND es.ts_schedule_created < COALESCE(dim_heh.ts_entrance_ended, CURRENT_TIMESTAMP())
LEFT JOIN
    dw_house.dim_house_entrance_history AS dim_heh_entrance
        ON es.id_house = dim_heh_entrance.sk_house
        AND es.ts_schedule_visit >= dim_heh_entrance.ts_entrance_started
        AND es.ts_schedule_visit < COALESCE(dim_heh_entrance.ts_entrance_ended, CURRENT_TIMESTAMP())
LEFT JOIN
    datalake_ebdb_agents.preferred_property_agent_relation_history AS ppa
        ON ppa.id_house = es.id_house
        AND es.business_context = ppa.business_context
        AND es.ts_schedule_created BETWEEN ppa.ts_relation_started AND COALESCE(ppa.ts_relation_ended, CURRENT_TIMESTAMP())
LEFT JOIN
    datalake_sale_visit_hubs.sale_visit_hubs AS svh
        ON svh.id_booking = es.id_schedule
LEFT JOIN
    datalake_region.region AS r
        ON es.id_region = r.id
LEFT JOIN
    datalake_ebdb_agents.preferred_fixed_agent_history AS pfa
        ON es.id_visitor = pfa.id_visitor
        AND r.id_city = pfa.id_region
        AND es.business_context = pfa.business_context
        AND es.ts_schedule_created BETWEEN pfa.ts_status_started AND COALESCE(pfa.ts_status_ended, NOW())
LEFT JOIN
    datalake_sale_primary_market.listing_sale_type AS lst
        ON lst.id_house = es.id_house
