WITH sale_offer_agents AS (
    SELECT DISTINCT
        so.id_offer,
        so.id_house,
        so.id_buyer AS id_prospect,
        so.id_user_consultant AS id_user_negotiation_executive,
        so.id_user_agent AS id_user_broker,
        COALESCE(so.id_agent, os.id_agent) AS id_agent_broker,
        cfl.id_user AS id_user_ciq,
        so.sale_price_agreed AS agreement_value,
        os.id_offer IS NOT NULL AS has_broker_tqc,
        os2.id_offer IS NOT NULL AS has_negotiation_executive_tqc,
        IF(
            DATE(so.ts_sale_agreement_signed) <= so.ts_sale_agreement_canceled,
            so.ts_sale_agreement_canceled,
            NULL
        ) AS dt_contract_cancelled,
        so.ts_offer_submitted,
        so.ts_sale_agreement_signed AS ts_contract_signed,
        GREATEST(
            so.ts_updated,
            so.ts_offer_submitted, 
            so.ts_sale_agreement_signed, 
            os.ts_agent_lead_referral_updated, 
            os2.ts_agent_lead_referral_updated
        ) AS ts_updated
    FROM
        datalake_sale_offer.sale_offer AS so
    LEFT JOIN
        datalake_sale_offer_flows.offer_specialists AS os
            ON os.id_user_agent_lead_referral = so.id_user_agent
            AND os.id_offer = so.id_offer
    LEFT JOIN
        datalake_sale_offer_flows.offer_specialists AS os2
            ON os2.id_user_agent_lead_referral = so.id_user_consultant
            AND os2.id_offer = so.id_offer
    LEFT JOIN
        datalake_tiers.ciq_first_listing AS cfl 
            ON cfl.id_house = so.id_house
            AND cfl.business_context = "SALE"
            AND cfl.consultant_type = "CIQ_FULL"
),
rent_offer_agents AS (
    SELECT
        COALESCE(rde.id_offer, -1) AS id_offer,
        COALESCE(rde.id_contract, -1) AS id_contract,
        rde.id_house,
        rde.id_tenant_prospect AS id_prospect,
        rde.id_agent AS id_user,
        cfl.id_user AS id_user_ciq,
        cfl.id_agent AS id_agent_ciq,
        MIN(rde.ts_event) FILTER(WHERE rde.id_event_type = 3) AS ts_offer_submitted,
        MIN(rde.ts_event) FILTER(WHERE rde.id_event_type = 9) AS ts_contract_signed,
        MAX(rde.ts_event) AS ts_updated
    FROM
        datalake_rent_demand_events.rent_demand_events AS rde
    LEFT JOIN
        datalake_tiers.ciq_first_listing AS cfl 
            ON cfl.id_house = rde.id_house
            AND cfl.business_context = "RENT"
            AND cfl.consultant_type = "CIQ_FULL"
    WHERE 
        rde.id_event_type IN (3, 9)
        AND rde.id_agent IS NOT NULL
    GROUP BY ALL
),
union_offer_agents AS (
    SELECT
        oa.id_offer,
        oa.id_contract,
        oa.id_house,
        oa.id_prospect,
        oa.id_user,
        NULL AS id_agent,
        oa.id_user_ciq,
        "AGENT" AS agent_profile,
        "RENT" AS business_context,
        NULL AS agreement_value,
        oa.id_user_ciq IS NOT NULL AS is_ciq_first_listing,
        NULL AS has_tqc,
        NULL AS dt_contract_cancelled,
        oa.ts_offer_submitted,
        oa.ts_contract_signed,
        oa.ts_updated
    FROM
        rent_offer_agents AS oa
    UNION ALL
    SELECT
        oa.id_offer,
        NULL AS id_contract,
        oa.id_house,
        oa.id_prospect,
        oa.id_user_broker AS id_user,
        oa.id_agent_broker AS id_agent,
        oa.id_user_ciq,
        "AGENT" AS agent_profile,
        "SALE" AS business_context,
        oa.agreement_value,
        oa.id_user_ciq IS NOT NULL AS is_ciq_first_listing,
        oa.has_broker_tqc AS has_tqc,
        oa.dt_contract_cancelled,
        oa.ts_offer_submitted,
        oa.ts_contract_signed,
        GREATEST(
            oa.ts_updated,
            oa.dt_contract_cancelled
        ) AS ts_updated
    FROM
        sale_offer_agents AS oa
    WHERE 
        oa.id_user_broker IS NOT NULL
    UNION ALL
    SELECT
        oa.id_offer,
        NULL AS id_contract,
        oa.id_house,
        oa.id_prospect,
        oa.id_user_negotiation_executive AS id_user,
        NULL AS id_agent,
        oa.id_user_ciq,
        "NEGOTIATION_EXECUTIVE" AS agent_profile,
        "SALE" AS business_context,
        oa.agreement_value,
        oa.id_user_ciq IS NOT NULL AS is_ciq_first_listing,
        oa.has_negotiation_executive_tqc AS has_tqc,
        oa.dt_contract_cancelled,
        oa.ts_offer_submitted,
        oa.ts_contract_signed,
        GREATEST(
            oa.ts_updated,
            oa.dt_contract_cancelled
        ) AS ts_updated
    FROM
        sale_offer_agents AS oa
    WHERE 
        oa.id_user_negotiation_executive IS NOT NULL
)
SELECT
    uoa.id_offer,
    uoa.id_contract,
    uoa.id_house,
    uoa.id_prospect,
    uoa.id_user,
    u.id_agent,
    u.uuid_person,
    uoa.id_user_ciq,
    uoa.agent_profile,
    uoa.business_context,
    uoa.agreement_value,
    uoa.has_tqc,
    uoa.is_ciq_first_listing,
    uoa.dt_contract_cancelled IS NOT NULL AS is_contract_cancelled,
    uoa.ts_contract_signed IS NOT NULL AS is_contract_signed,
    uoa.dt_contract_cancelled,
    uoa.ts_contract_signed,
    uoa.ts_offer_submitted,
    uoa.ts_updated,
    YEAR(uoa.ts_updated) AS year,
    MONTH(uoa.ts_updated) AS month,
    DAY(uoa.ts_updated) AS day
FROM
    union_offer_agents AS uoa
LEFT JOIN
    datalake_ebdb_user.user AS u
        ON u.id = uoa.id_user
WHERE
    DATE(uoa.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')