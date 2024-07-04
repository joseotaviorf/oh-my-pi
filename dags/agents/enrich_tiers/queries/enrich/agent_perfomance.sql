WITH bimester AS (
    SELECT DISTINCT
        ad.bimester_name,
        ad.bimester_months,
        ad.bimester_start,
        ad.bimester_end,
        ad.year,
        ad.bimester
    FROM 
        datalake_quintoandar.aux_date AS ad
    WHERE
        ad.bimester_start >= DATE_TRUNC('MONTH', DATE('{load_start_date}')) 
        AND ad.bimester_end <= LAST_DAY(DATE('{load_end_date}'))
        OR ARRAY_CONTAINS(ad.bimester_months, MONTH(DATE('{load_start_date}')))
        OR ARRAY_CONTAINS(ad.bimester_months, MONTH(DATE('{load_end_date}')))
),
offer_signed AS (
    SELECT
        oa.id_user,
        COUNT(DISTINCT oa.id_offer) AS total_offer_signed,
        COUNT(DISTINCT oa.id_offer) FILTER (WHERE oa.has_tqc IS TRUE) AS total_offer_signed_with_tqc,
        b.bimester,
        b.year
    FROM
        datalake_tiers.agent_offers_signed AS oa
    JOIN
        bimester AS b
            ON DATE(oa.ts_sale_agreement_signed) BETWEEN b.bimester_start AND b.bimester_end
    GROUP BY 1, 4, 5
),
ciq_first_listing AS (
    SELECT
        cfl.id_user,
        COUNT(DISTINCT cfl.id_house) AS total_first_listing,
        b.bimester,
        b.year
    FROM
        datalake_tiers.ciq_first_listing AS cfl
    JOIN
        bimester AS b
            ON DATE(cfl.ts_first_listing) BETWEEN b.bimester_start AND b.bimester_end
    GROUP BY 1, 3, 4
),
hub_users AS (
    SELECT
        u.id_user,
        u.id_main_user,
        u.id_agent,
        u.name,
        u.email,
        u.phone_number,
        ROW_NUMBER() OVER(PARTITION BY u.id_main_user ORDER BY u.ts_updated DESC) = 1 AS is_last_updated
    FROM
        datalake_hub_services.users AS u
),
business_unit AS (
    SELECT
        u.id_main_user,
        mp.id_business_unit,
        bu.hub_name
    FROM
        datalake_hub_services.member_profile AS mp
    JOIN
        hub_users AS u
            ON u.id_user = mp.id_user
    JOIN
        datalake_hub_services_clean.business_unit AS bu 
            ON bu.id = mp.id_business_unit
    WHERE
        bu.business_context = 'SALE'
    QUALIFY 
        ROW_NUMBER() OVER(PARTITION BY u.id_main_user ORDER BY COALESCE(mp.ts_relationship_ended, mp.ts_load) DESC) = 1
),
member_profile AS (
    SELECT DISTINCT
        u.id_main_user,
        mp.profile,
        b.bimester_name,
        b.bimester,
        b.year
    FROM
        datalake_hub_services.member_profile AS mp
    JOIN
        hub_users AS u
            ON u.id_user = mp.id_user
    JOIN
        bimester AS b
            ON b.bimester_start >= DATE(mp.ts_relationship_started) 
            AND b.bimester_end <= DATE(COALESCE(mp.ts_relationship_ended, mp.ts_load))
            OR (YEAR(mp.ts_relationship_started) = b.year AND ARRAY_CONTAINS(b.bimester_months, MONTH(mp.ts_relationship_started)))
            OR (YEAR(mp.ts_relationship_ended) = b.year AND ARRAY_CONTAINS(b.bimester_months, MONTH(mp.ts_relationship_ended)))
    WHERE
        mp.profile IN ('AGENT', 'NEGOTIATION_EXECUTIVE')
)
SELECT
    u.id_agent,
    u.id_main_user AS id_user,
    bu.id_business_unit,
    mp.bimester_name,
    u.name,
    u.email,
    u.phone_number,
    mp.profile,
    bu.hub_name,
    COALESCE(aos.total_offer_signed, 0) AS total_offer_signed,
    COALESCE(aos.total_offer_signed_with_tqc, 0) AS total_offer_signed_with_tqc,
    COALESCE(aos.total_offer_signed - aos.total_offer_signed_with_tqc, 0) AS total_offer_signed_without_tqc,
    COALESCE(cql.total_first_listing, 0) AS total_first_listing,
    mp.year,
    mp.bimester
FROM
    member_profile AS mp
JOIN
    hub_users AS u
        ON u.id_main_user = mp.id_main_user
        AND u.is_last_updated IS TRUE
JOIN
    business_unit AS bu 
        ON bu.id_main_user = mp.id_main_user
LEFT JOIN
    offer_signed AS aos
        ON aos.id_user = u.id_main_user
        AND aos.bimester = mp.bimester
        AND aos.year = mp.year
LEFT JOIN
    ciq_first_listing AS cql
        ON cql.id_user = u.id_main_user 
        AND cql.bimester = mp.bimester
        AND cql.year = mp.year