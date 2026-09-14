WITH dim_agent_identity_crosswalk AS (
    SELECT DISTINCT
        id_agent_data,
        id_user,
        uuid_person
    FROM datalake_ebdb_agent_events.agent_unified_identity
    WHERE id_agent_data IS NOT NULL
),

agent_lead_history AS (
    SELECT 
        aud.id AS id_referral, 
        aud.id_agent AS id_agent_data_referring,
        cw.id_user AS id_user_referring_agent,
        cw.uuid_person AS uuid_person_referring_agent,
        aud.id_lead,
        aud.rev,
        aud.status,
        LAG(aud.status) OVER (PARTITION BY aud.id ORDER BY aud.rev ASC) AS previous_status,
        CASE WHEN DATE(ts_created) <= "2026-06-17" THEN "SALE" ELSE aud.business_context END as business_context, -- Only SALE existed before that date and the backfill was never made
        aud.origin,
        aud.ts_created AS valid_from,
        LEAD(aud.ts_created) OVER (PARTITION BY aud.id ORDER BY aud.rev ASC) AS valid_to
    FROM datalake_ebdb_clean.agent_lead_referral_aud aud
    LEFT JOIN dim_agent_identity_crosswalk cw 
        ON CAST(aud.id_agent AS STRING) = CAST(cw.id_agent_data AS STRING)
),

unified_demand_events AS (
    -- SALE: sde.id_agent is id_agent_data, joining via cross-walk
    SELECT 
        sde.id_buyer AS id_lead, 
        sde.id_agent AS id_event_agent,
        cw.id_user AS id_user_event_agent,
        cw.uuid_person AS uuid_person_event_agent,
        sde.id_sale_flow AS id_flow,
        sde.id_booking, 
        sde.id_offer, 
        NULL AS id_contract, 
        sde.sk_event_type AS id_event_type, 
        'SALE' AS event_business_context,
        sde.ts_event
    FROM datalake_sale_demand_events.sale_demand_events sde
    LEFT JOIN dim_agent_identity_crosswalk cw 
        ON CAST(sde.id_agent AS STRING) = CAST(cw.id_agent_data AS STRING)
        
    UNION ALL
    
    -- RENT: rde.id_agent IS id_user directly
    SELECT 
        rde.id_tenant_prospect AS id_lead, 
        CAST(NULL AS STRING) AS id_event_agent,
        CAST(rde.id_agent AS BIGINT) AS id_user_event_agent,
        CAST(NULL AS STRING) AS uuid_person_event_agent,
        rde.id_rent_flow AS id_flow,
        rde.id_booking, 
        rde.id_offer, 
        rde.id_contract, 
        rde.id_event_type,
        'RENT' AS event_business_context,
        rde.ts_event
    FROM datalake_rent_demand_events.rent_demand_events rde
    WHERE rde.id_event_type IN (1, 2, 3, 9) 
),

flat_aggregations AS (
    SELECT 
        alh.id_referral, alh.rev, alh.id_lead, alh.status, alh.previous_status, 
        alh.business_context, alh.origin, alh.valid_from, alh.valid_to,
        alh.id_agent_data_referring, alh.id_user_referring_agent, alh.uuid_person_referring_agent,
        
        MIN_BY(
            NAMED_STRUCT('ts', ude.ts_event, 'id_agent', ude.id_event_agent, 'id_user', ude.id_user_event_agent, 'uuid_person', ude.uuid_person_event_agent, 'id_flow', ude.id_flow, 'id_booking', ude.id_booking),
            CASE WHEN ude.event_business_context = 'SALE' AND ude.id_event_type = 1 THEN ude.ts_event END
        ) AS sale_visit,
        
        MIN_BY(
            NAMED_STRUCT('ts', ude.ts_event, 'id_agent', ude.id_event_agent, 'id_user', ude.id_user_event_agent, 'uuid_person', ude.uuid_person_event_agent, 'id_flow', ude.id_flow, 'id_offer', ude.id_offer),
            CASE WHEN ude.event_business_context = 'SALE' AND ude.id_event_type = 3 THEN ude.ts_event END
        ) AS sale_offer,

        MIN_BY(
            NAMED_STRUCT('ts', ude.ts_event, 'id_agent', ude.id_event_agent, 'id_user', ude.id_user_event_agent, 'uuid_person', ude.uuid_person_event_agent, 'id_flow', ude.id_flow, 'id_offer', ude.id_offer),
            CASE WHEN ude.event_business_context = 'SALE' AND ude.id_event_type = 6 THEN ude.ts_event END
        ) AS sale_agreement_signed,

        MIN_BY(
            NAMED_STRUCT('ts', ude.ts_event, 'id_agent', ude.id_event_agent, 'id_user', ude.id_user_event_agent, 'uuid_person', ude.uuid_person_event_agent, 'id_flow', ude.id_flow, 'id_booking', ude.id_booking),
            CASE WHEN ude.event_business_context = 'RENT' AND ude.id_event_type = 1 THEN ude.ts_event END
        ) AS rent_visit,
        
        MIN_BY(
            NAMED_STRUCT('ts', ude.ts_event, 'id_agent', ude.id_event_agent, 'id_user', ude.id_user_event_agent, 'uuid_person', ude.uuid_person_event_agent, 'id_flow', ude.id_flow, 'id_offer', ude.id_offer),
            CASE WHEN ude.event_business_context = 'RENT' AND ude.id_event_type = 3 THEN ude.ts_event END
        ) AS rent_offer,

        MIN(CASE WHEN ude.event_business_context = 'SALE' AND ude.id_event_type = 2 THEN ude.ts_event END) AS ts_sale_visit_completed,
        MIN(CASE WHEN ude.event_business_context = 'SALE' AND ude.id_event_type = 4 THEN ude.ts_event END) AS ts_sale_offer_accepted,
        MIN(CASE WHEN ude.event_business_context = 'RENT' AND ude.id_event_type = 2 THEN ude.ts_event END) AS ts_rent_visit_completed,
        
        MIN_BY(ude.id_contract, CASE WHEN ude.event_business_context = 'RENT' AND ude.id_event_type = 9 THEN ude.ts_event END) AS id_rent_contract,
        MIN(CASE WHEN ude.event_business_context = 'RENT' AND ude.id_event_type = 9 THEN ude.ts_event END) AS ts_rent_contract_signed,

        MIN(CASE WHEN ude.event_business_context = 'SALE' AND ude.id_event_type = 1 AND alh.id_user_referring_agent = ude.id_user_event_agent THEN ude.ts_event END) AS ts_sale_ref_visit,
        MIN(CASE WHEN ude.event_business_context = 'SALE' AND ude.id_event_type = 3 AND alh.id_user_referring_agent = ude.id_user_event_agent THEN ude.ts_event END) AS ts_sale_ref_offer,
        MIN(CASE WHEN ude.event_business_context = 'SALE' AND ude.id_event_type = 6 AND alh.id_user_referring_agent = ude.id_user_event_agent THEN ude.ts_event END) AS ts_sale_ref_agreement_signed,
        MIN(CASE WHEN ude.event_business_context = 'RENT' AND ude.id_event_type = 1 AND alh.id_user_referring_agent = ude.id_user_event_agent THEN ude.ts_event END) AS ts_rent_ref_visit,
        MIN(CASE WHEN ude.event_business_context = 'RENT' AND ude.id_event_type = 3 AND alh.id_user_referring_agent = ude.id_user_event_agent THEN ude.ts_event END) AS ts_rent_ref_offer,

        MIN_BY(os.id_user_agent_lead_referral, CASE WHEN ude.id_event_type = 3 THEN ude.ts_event END) AS spec_id_user
    FROM agent_lead_history alh
    LEFT JOIN unified_demand_events ude 
        ON alh.id_lead = ude.id_lead AND alh.status IN ('CONFIRMED', 'INACTIVE') 
        AND ude.ts_event >= alh.valid_from AND (ude.ts_event < alh.valid_to OR alh.valid_to IS NULL)
    LEFT JOIN datalake_sale_offer_flows.offer_specialists os 
        ON ude.event_business_context = 'SALE' AND CAST(ude.id_offer AS STRING) = CAST(os.id_offer AS STRING)
    GROUP BY 
        alh.id_referral, alh.rev, alh.id_lead, alh.status, alh.previous_status, alh.business_context, alh.origin, alh.valid_from, alh.valid_to,
        alh.id_agent_data_referring, alh.id_user_referring_agent, alh.uuid_person_referring_agent
)

SELECT 
    id_referral,
    rev, 
    id_lead, 
    id_agent_data_referring, 
    id_user_referring_agent, 
    uuid_person_referring_agent,
    status AS referral_status, 
    valid_from, 
    valid_to, 
    previous_status, 
    business_context, 
    origin, 
    
    COALESCE(sale_visit.id_flow, sale_offer.id_flow) AS id_first_sale_flow,
    COALESCE(rent_visit.id_flow, rent_offer.id_flow) AS id_first_rent_flow,
    
    CASE WHEN sale_visit.ts IS NOT NULL OR rent_visit.ts IS NOT NULL THEN TRUE ELSE FALSE END AS has_any_visits,
    CASE WHEN sale_offer.ts IS NOT NULL OR rent_offer.ts IS NOT NULL THEN TRUE ELSE FALSE END AS has_any_offers,
    
    CASE 
        WHEN (sale_visit.id_user IS NOT NULL AND sale_visit.id_user = id_user_referring_agent) 
          OR (rent_visit.id_user IS NOT NULL AND rent_visit.id_user = id_user_referring_agent) THEN TRUE 
        WHEN sale_visit.id_user IS NOT NULL OR rent_visit.id_user IS NOT NULL THEN FALSE ELSE NULL 
    END AS is_visit_same_agent,
    
    CASE
        WHEN (sale_offer.id_user IS NOT NULL AND sale_offer.id_user = id_user_referring_agent)
          OR (rent_offer.id_user IS NOT NULL AND rent_offer.id_user = id_user_referring_agent) THEN TRUE
        WHEN sale_offer.id_user IS NOT NULL OR rent_offer.id_user IS NOT NULL THEN FALSE ELSE NULL
    END AS is_offer_same_agent,

    CASE
        WHEN sale_agreement_signed.id_user IS NOT NULL AND sale_agreement_signed.id_user = id_user_referring_agent THEN TRUE
        WHEN sale_agreement_signed.id_user IS NOT NULL THEN FALSE ELSE NULL
    END AS is_agreement_same_agent,

    NAMED_STRUCT(
        'has_handled_visit', CASE WHEN ts_sale_ref_visit IS NOT NULL OR ts_rent_ref_visit IS NOT NULL THEN TRUE ELSE FALSE END,
        'has_handled_offer', CASE WHEN ts_sale_ref_offer IS NOT NULL OR ts_rent_ref_offer IS NOT NULL THEN TRUE ELSE FALSE END,
        'has_handled_agreement_signed', CASE WHEN ts_sale_ref_agreement_signed IS NOT NULL THEN TRUE ELSE FALSE END,
        'ts_sale_visit', ts_sale_ref_visit,
        'ts_sale_offer', ts_sale_ref_offer,
        'ts_sale_agreement_signed', ts_sale_ref_agreement_signed,
        'ts_rent_visit', ts_rent_ref_visit,
        'ts_rent_offer', ts_rent_ref_offer
    ) AS invitation_agent_interactions,
    
    NAMED_STRUCT(
        'id_booking', sale_visit.id_booking,
        'ts_visit_booked', sale_visit.ts,
        'ts_visit_completed', ts_sale_visit_completed,
        'visit_id_agent', sale_visit.id_agent,
        'visit_id_user', sale_visit.id_user,
        'visit_uuid_person', sale_visit.uuid_person,
        'id_offer', sale_offer.id_offer,
        'ts_offer_submitted', sale_offer.ts,
        'ts_offer_accepted', ts_sale_offer_accepted,
        'offer_id_agent', sale_offer.id_agent,
        'offer_id_user', sale_offer.id_user,
        'offer_uuid_person', sale_offer.uuid_person,
        'ts_agreement_signed', sale_agreement_signed.ts,
        'agreement_id_agent', sale_agreement_signed.id_agent,
        'agreement_id_user', sale_agreement_signed.id_user,
        'agreement_uuid_person', sale_agreement_signed.uuid_person
    ) AS sale_first_events,
    
    NAMED_STRUCT(
        'id_booking', rent_visit.id_booking,
        'ts_visit_booked', rent_visit.ts,
        'ts_visit_completed', ts_rent_visit_completed,
        'visit_id_agent', rent_visit.id_agent,
        'visit_id_user', rent_visit.id_user,
        'visit_uuid_person', rent_visit.uuid_person,
        'id_offer', rent_offer.id_offer,
        'ts_offer_submitted', rent_offer.ts,
        'id_contract', id_rent_contract,
        'ts_contract_signed', ts_rent_contract_signed,
        'offer_id_agent', rent_offer.id_agent,
        'offer_id_user', rent_offer.id_user,
        'offer_uuid_person', rent_offer.uuid_person
    ) AS rent_first_events,
    
    NAMED_STRUCT(
        'id_user', spec_id_user, 
        'has_mismatch', CASE WHEN spec_id_user IS NOT NULL AND id_user_referring_agent != spec_id_user THEN TRUE ELSE FALSE END
    ) AS offer_specialist

FROM flat_aggregations
