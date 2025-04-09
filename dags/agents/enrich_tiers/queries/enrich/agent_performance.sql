WITH filter_bimester AS (
    SELECT
        ad.bimester_name,
        ad.date,
        ad.bimester,
        ad.bimester_start,
        ad.bimester_end,
        ad.year
    FROM 
        datalake_quintoandar.aux_date AS ad
    WHERE
        ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
offer_signed AS (
    SELECT
        oa.id_user,
        COUNT(DISTINCT oa.id_offer) AS total_offer_signed,
        COUNT(DISTINCT oa.id_offer) FILTER (WHERE oa.has_tqc IS TRUE) AS total_offer_signed_with_tqc,
        SUM(oa.sale_price_agreed) AS total_gross_merchandise_volume, 
        fb.year,
        fb.bimester
    FROM
        datalake_tiers.agent_offers AS oa
    JOIN
        filter_bimester AS fb
            ON fb.bimester = oa.bimester
            AND fb.year = oa.year
    WHERE
        oa.is_contract_signed IS TRUE
    GROUP BY ALL
),
offer_submitted AS (
    SELECT
        oa.id_user,
        COUNT(DISTINCT oa.id_offer) AS total_offer_submitted,
        COUNT(DISTINCT oa.id_buyer) AS total_buyer_with_offer_submitted,
        fb.year,
        fb.bimester
    FROM
        datalake_tiers.agent_offers AS oa
    JOIN
        filter_bimester AS fb
            ON fb.date = DATE(oa.ts_offer_submitted)
    GROUP BY ALL
),
ciq_offer_signed AS (
    SELECT
        oa.id_user_ciq AS id_user,
        COUNT(DISTINCT oa.id_offer) AS total_offer_signed_with_ciq,
        fb.year,
        fb.bimester
    FROM
        datalake_tiers.agent_offers AS oa
    JOIN
        filter_bimester AS fb
            ON fb.bimester = oa.bimester
            AND fb.year = oa.year
    WHERE
        oa.is_contract_signed IS TRUE
        AND oa.is_ciq_first_listing IS TRUE
    GROUP BY ALL
),
ciq_first_listing AS (
    SELECT
        cfl.id_user,
        COUNT(DISTINCT cfl.id_house) AS total_first_listing,
        fb.year,
        fb.bimester
    FROM
        datalake_tiers.ciq_first_listing AS cfl
    JOIN
        filter_bimester AS fb
            ON fb.bimester = cfl.bimester
            AND fb.year = cfl.year
    WHERE
        cfl.has_first_listing IS TRUE
    GROUP BY ALL
),
member_profile AS (
    SELECT
        fb.bimester_name,
        u.id_main_user,
        u.id_agent,
        mp.id_business_unit,
        bu.hub_name,
        bu.business_context,
        CASE
            WHEN mp.profile = 'AGENT' THEN 'Broker'
            WHEN mp.profile = 'NEGOTIATION_EXECUTIVE' THEN "Negotiation Executive"
        END AS profile,
        u.name,
        u.email,
        u.cpf,
        u.phone_number,
        mp.is_active,
        mp.ts_relationship_started,
        COALESCE(mp.ts_relationship_ended, mp.ts_load) AS ts_relationship_ended,
        fb.bimester,
        fb.year
    FROM
        datalake_hub_services.member_profile AS mp
    JOIN
        datalake_hub_services.users AS u
            ON u.id_user = mp.id_user
    JOIN
        datalake_hub_services_clean.business_unit AS bu
            ON bu.id = mp.id_business_unit
    JOIN 
        filter_bimester AS fb
            ON (DATE(mp.ts_relationship_ended) BETWEEN fb.bimester_start AND fb.bimester_end)
            OR mp.ts_relationship_ended IS NULL
    WHERE
        mp.profile IN ('AGENT', 'NEGOTIATION_EXECUTIVE')
),
user_with_multiple_roles AS (
    SELECT
        mp.id_main_user,
        COUNT(DISTINCT business_context) AS total_business_contexts
    FROM
        member_profile AS mp
    WHERE
        mp.is_active IS TRUE
    GROUP BY 1
    HAVING total_business_contexts > 1
)
SELECT 
    mp.id_agent,
    mp.id_main_user AS id_user,
    mp.id_business_unit,
    mp.business_context,
    mp.bimester_name,
    mp.name,
    mp.email,
    mp.cpf,
    mp.phone_number,
    mp.profile,
    mp.hub_name,
    COALESCE(osu.total_offer_submitted, 0) AS total_offer_submitted,
    COALESCE(os.total_offer_signed, 0) AS total_regular_offer_signed,
    COALESCE(osu.total_buyer_with_offer_submitted, 0) AS total_buyer_with_offer_submitted,
    (
        COALESCE(os.total_offer_signed, 0) 
        + COALESCE(cos.total_offer_signed_with_ciq, 0)
    ) AS total_offer_signed_with_agent_intermediation,
    (
        COALESCE(os.total_offer_signed_with_tqc, 0) 
        + COALESCE(cos.total_offer_signed_with_ciq, 0)
    ) AS total_offer_signed_with_demand_supply_capture,
    COALESCE(os.total_offer_signed_with_tqc, 0) AS total_offer_signed_with_tqc,
    COALESCE(cos.total_offer_signed_with_ciq, 0) AS total_offer_signed_with_ciq,
    COALESCE(cql.total_first_listing, 0) AS total_first_listing,
    COALESCE(os.total_gross_merchandise_volume, 0) AS total_gross_merchandise_volume,
    ROUND(COALESCE(os.total_offer_signed/ osu.total_buyer_with_offer_submitted, 0), 2) AS ratio_offer_submitted_to_signed,
    mp.year,
    mp.bimester
FROM
    member_profile AS mp
LEFT JOIN
    user_with_multiple_roles AS uwmr
        ON uwmr.id_main_user = mp.id_main_user
LEFT JOIN
    offer_signed AS os
        ON os.id_user = mp.id_main_user
        AND os.bimester = mp.bimester
        AND os.year = mp.year
LEFT JOIN
    offer_submitted AS osu
        ON osu.id_user = mp.id_main_user
        AND osu.bimester = mp.bimester
        AND osu.year = mp.year
LEFT JOIN
    ciq_offer_signed AS cos
        ON cos.id_user = mp.id_main_user
        AND cos.bimester = mp.bimester
        AND cos.year = mp.year
LEFT JOIN
    ciq_first_listing AS cql
        ON cql.id_user = mp.id_main_user 
        AND cql.bimester = mp.bimester
        AND cql.year = mp.year
WHERE
    NOT (uwmr.id_main_user IS NOT NULL AND mp.business_context = 'RENT')
QUALIFY
    1 = ROW_NUMBER() OVER (PARTITION BY mp.id_main_user, mp.bimester, mp.year ORDER BY mp.ts_relationship_started DESC, mp.ts_relationship_ended DESC)