WITH rent_flow_type AS (
    /** This info should be added on the table that would consolidate the base for rent flows,
        which today is the rent demand events. A refactor is expected for the future. **/
  SELECT
    id_rent_flow,
    id_rent_flow_type
  FROM
    datalake_rent_flows.rent_flows AS rf
  JOIN
    datalake_rent_flows.rent_flows_types AS rt
        ON rf.country_code <=> rt.country_code
        AND rf.first_touchpoint <=> rt.first_touchpoint
        AND rf.status <=> rt.status
        AND rf.is_step_rejected <=> rt.is_step_rejected
        AND rf.is_valid_rent_flow <=> rt.is_valid_rent_flow
        AND rf.has_visit_flow <=> rt.has_visit_flow
        AND rf.has_offer_flow <=> rt.has_offer_flow
        AND rf.has_direct_offer_flow <=> rt.has_direct_offer_flow
        AND rf.has_tta_flow <=> rt.has_tta_flow
        AND IF(rf.ts_contract_signed IS NOT NULL, TRUE, FALSE) <=> rt.had_contract_signed
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_rent_flow ORDER BY ts_rent_flow_event DESC) = 1
)
SELECT
    rde.id_event || '.' || rde.id_event_type || '.' || rde.id_tenant_prospect AS pk_rent_demand_event,
    rde.id_event AS sk_event,
    COALESCE(rde.id_booking, -1) AS sk_booking,
    COALESCE(rde.id_offer, -1) AS sk_offer,
    COALESCE(rde.id_proposal, -1) AS sk_proposal,
    COALESCE(rde.id_contract, -1) AS sk_contract,
    rde.id_event_type AS sk_event_type,
    COALESCE(rde.id_tenant_prospect, -1) AS sk_tenant_prospect,
    COALESCE(rde.id_house, -1) AS sk_house,
    COALESCE(rde.id_agent, -1) AS sk_agent,
    COALESCE(rde.id_rent_flow, -1) AS sk_rent_flow,
    COALESCE(rt.id_rent_flow_type, -1) AS sk_rent_flow_type,
    COALESCE(rde.id_house_listing, -1) AS sk_house_listing,
    COALESCE(rde.id_region, -1) AS sk_region,
    COALESCE(rde.id_owner, -1) AS sk_owner,
    COALESCE(rde.id_owner_category, -1) AS sk_owner_category,
    COALESCE(cs_supply.sk_company, -1) AS sk_company_supply,
    COALESCE(CAST(DATE_FORMAT(rde.ts_event, "yyyyMMdd") AS BIGINT), -1) AS sk_event_date,
    rde.country_code,
    rde.is_during_termination,
    rde.ts_event,
    YEAR(rde.ts_event) AS year,
    MONTH(rde.ts_event) AS month,
    DAY(rde.ts_event) AS day,
    NOW() AS ts_load
FROM
    datalake_rent_demand_events.rent_demand_events AS rde
LEFT JOIN
    rent_flow_type AS rt
        ON rt.id_rent_flow = rde.id_rent_flow
LEFT JOIN
    datalake_rede_company.company_sks AS cs_supply
        ON (
            rde.uuid_company IS NOT NULL
            AND rde.uuid_company = cs_supply.uuid_company
        ) OR (
            rde.uuid_company IS NULL
            AND rde.id_company_hubspot IS NOT NULL
            AND rde.id_company_hubspot = cs_supply.id_hubspot
        ) OR (
            rde.uuid_company IS NULL
            AND rde.id_company_hubspot IS NULL
            AND rde.partner_3p_supply = cs_supply.extracted_3p_tag
        )