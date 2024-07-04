-- Do not reprocess the table, as the source tables are still fully loaded
WITH offer_agents AS (
    SELECT DISTINCT
        so.id_offer,
        so.id_user_consultant AS id_user_negotiation_executive,
        u.id_agent AS id_agent_negotiation_executive,
        so.id_user_agent AS id_user_broker,
        COALESCE(so.id_agent, os.id_agent) AS id_agent_broker,
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
),
union_offer_agents AS (
    SELECT
        oa.id_offer,
        oa.id_user_broker AS id_user,
        oa.id_agent_broker AS id_agent,
        "Broker" AS agent_profile,
        oa.has_broker_tqc AS has_tqc,
        oa.ts_sale_agreement_signed,
        oa.ts_updated,
        DAY(oa.ts_updated) AS day,
        MONTH(oa.ts_updated) AS month,
        YEAR(oa.ts_updated) AS year
    FROM
        offer_agents AS oa
    UNION ALL
    SELECT
        oa.id_offer,
        oa.id_user_negotiation_executive AS id_user,
        oa.id_agent_negotiation_executive AS id_agent,
        "Negotiation Executive" AS agent_profile,
        oa.has_negotiation_executive_tqc AS has_tqc,
        oa.ts_sale_agreement_signed,
        oa.ts_updated,
        DAY(oa.ts_updated) AS day,
        MONTH(oa.ts_updated) AS month,
        YEAR(oa.ts_updated) AS year
    FROM
        offer_agents AS oa
)
SELECT
    uoa.id_offer,
    uoa.id_user,
    uoa.id_agent,
    uoa.agent_profile,
    uoa.has_tqc,
    uoa.ts_sale_agreement_signed,
    uoa.ts_updated,
    uoa.day,
    uoa.month,
    uoa.year
FROM
    union_offer_agents AS uoa
WHERE 
    uoa.ts_sale_agreement_signed IS NOT NULL
    AND uoa.id_user IS NOT NULL
    AND uoa.ts_updated BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
       
    