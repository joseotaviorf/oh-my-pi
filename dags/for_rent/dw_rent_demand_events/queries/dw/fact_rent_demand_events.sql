SELECT
    id_event || '.' || id_event_type || '.' || id_tenant_prospect AS pk_rent_demand_event,
    id_event AS sk_event,
    COALESCE(id_booking, -1) AS sk_booking,
    COALESCE(id_offer, -1) AS sk_offer,
    COALESCE(id_proposal, -1) AS sk_proposal,
    COALESCE(id_contract, -1) AS sk_contract,
    id_event_type AS sk_event_type,
    COALESCE(id_tenant_prospect, -1) AS sk_tenant_prospect,
    COALESCE(id_house, -1) AS sk_house,
    COALESCE(id_agent, -1) AS sk_agent,
    COALESCE(id_rent_flow, -1) AS sk_rent_flow,
    COALESCE(id_house_listing, -1) AS sk_house_listing,
    COALESCE(id_region, -1) AS sk_region,
    COALESCE(id_owner, -1) AS sk_owner,
    COALESCE(CAST(DATE_FORMAT(ts_event, "yyyyMMdd") AS BIGINT), -1) AS sk_event_date,
    country_code,
    is_during_termination,
    NOW() AS ts_load
FROM
    datalake_rent_demand_events.rent_demand_events
