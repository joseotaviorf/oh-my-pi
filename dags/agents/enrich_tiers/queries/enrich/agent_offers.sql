-- Do not reprocess the table, as the source tables are still fully loaded
WITH filter_bimester AS (
    SELECT DISTINCT
        ad.bimester_start,
        ad.bimester_end,
        ad.bimester,
        ad.year
    FROM 
        datalake_quintoandar.aux_date AS ad
    WHERE
        ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
offer_agents AS (
    SELECT DISTINCT
        so.id_offer,
        so.id_user_consultant AS id_user_negotiation_executive,
        u.id_agent AS id_agent_negotiation_executive,
        so.id_user_agent AS id_user_broker,
        COALESCE(so.id_agent, os.id_agent) AS id_agent_broker,
        cfl.id_user AS id_user_ciq,
        so.sale_price_agreed,
        os.id_offer IS NOT NULL AS has_broker_tqc,
        os2.id_offer IS NOT NULL AS has_negotiation_executive_tqc,
        so.dt_sale_agreement_signed AS ts_sale_agreement_signed,
        GREATEST(so.dt_sale_agreement_signed, os.ts_agent_lead_referral_updated, os2.ts_agent_lead_referral_updated) AS ts_updated
    FROM
        datalake_offer.sale_offer AS so
    LEFT JOIN
        datalake_sale_offer_flows.offer_specialists AS os
            ON os.id_user_agent_lead_referral = so.id_user_agent
            AND os.id_offer = so.id_offer
    LEFT JOIN
        datalake_sale_offer_flows.offer_specialists AS os2
            ON os2.id_user_agent_lead_referral = so.id_user_consultant
            AND os2.id_offer = so.id_offer
    LEFT JOIN
        datalake_ebdb_user.user AS u
            ON u.id = so.id_user_consultant
    LEFT JOIN
        datalake_tiers.ciq_first_listing AS cfl 
            ON cfl.id_house = so.id_house
),
union_offer_agents AS (
    SELECT
        oa.id_offer,
        oa.id_user_broker AS id_user,
        oa.id_agent_broker AS id_agent,
        oa.id_user_ciq,
        "Broker" AS agent_profile,
        oa.sale_price_agreed,
        oa.has_broker_tqc AS has_tqc,
        oa.id_user_ciq IS NOT NULL AS is_ciq_first_listing,
        oa.ts_sale_agreement_signed,
        oa.ts_updated
    FROM
        offer_agents AS oa
    WHERE 
        oa.id_user_broker IS NOT NULL
    UNION ALL
    SELECT
        oa.id_offer,
        oa.id_user_negotiation_executive AS id_user,
        oa.id_agent_negotiation_executive AS id_agent,
        oa.id_user_ciq,
        "Negotiation Executive" AS agent_profile,
        oa.sale_price_agreed,
        oa.has_negotiation_executive_tqc AS has_tqc,
        oa.id_user_ciq IS NOT NULL AS is_ciq_first_listing,
        oa.ts_sale_agreement_signed,
        oa.ts_updated
    FROM
        offer_agents AS oa
    WHERE 
        oa.id_user_negotiation_executive IS NOT NULL
)
SELECT
    uoa.id_offer,
    uoa.id_user,
    uoa.id_agent,
    uoa.id_user_ciq,
    uoa.agent_profile,
    uoa.sale_price_agreed,
    uoa.has_tqc,
    uoa.is_ciq_first_listing,
    uoa.ts_sale_agreement_signed IS NOT NULL AS is_contract_signed,
    uoa.ts_sale_agreement_signed,
    uoa.ts_updated,
    fb.year,
    fb.bimester
FROM
    union_offer_agents AS uoa
JOIN
    filter_bimester AS fb
        ON DATE(uoa.ts_updated) BETWEEN fb.bimester_start AND fb.bimester_end