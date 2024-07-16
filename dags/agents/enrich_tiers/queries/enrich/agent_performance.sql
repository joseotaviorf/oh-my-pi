WITH bimester AS (
    WITH filter_bimester AS (
        SELECT DISTINCT
            ad.bimester,
            ad.year
        FROM 
            datalake_quintoandar.aux_date AS ad
        WHERE
            ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    )
    SELECT
        ad.bimester_name,
        ad.bimester_months,
        ad.bimester_start,
        ad.bimester_end,
        ad.date,
        ad.bimester,
        ad.year
    FROM 
        datalake_quintoandar.aux_date AS ad
    JOIN
        filter_bimester AS fb
            ON fb.bimester = ad.bimester 
            AND fb.year = ad.year
),
offer_signed AS (
    SELECT
        oa.id_user,
        -- agent_profile,
        COUNT(DISTINCT oa.id_offer) AS total_offer_signed,
        COUNT(DISTINCT oa.id_offer) FILTER (WHERE oa.has_tqc IS TRUE) AS total_offer_signed_with_tqc,
        COUNT(DISTINCT oa.id_offer) FILTER (WHERE oa.has_ciq IS TRUE) AS total_offer_signed_with_ciq,
        b.bimester,
        b.year
    FROM
        datalake_tiers.agent_offers_signed AS oa
    JOIN
        bimester AS b
            ON DATE(oa.ts_sale_agreement_signed) BETWEEN b.bimester_start AND b.bimester_end
    GROUP BY 1, 5, 6
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
member_profile AS (
    SELECT
        b.bimester_name,
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
        b.year,
        b.bimester
    FROM
        datalake_hub_services.member_profile AS mp
    JOIN
        datalake_hub_services.users AS u
            ON u.id_user = mp.id_user
    JOIN
        datalake_hub_services_clean.business_unit AS bu
            ON bu.id = mp.id_business_unit
    JOIN
        bimester AS b
            ON b.date BETWEEN DATE(mp.ts_relationship_started) 
            AND DATE(COALESCE(mp.ts_relationship_ended, mp.ts_load))
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
    mp.bimester_name,
    mp.name,
    mp.email,
    mp.cpf,
    mp.phone_number,
    mp.profile,
    mp.hub_name,
    COALESCE(aos.total_offer_signed, 0) AS total_offer_signed,
    COALESCE(aos.total_offer_signed_with_tqc, 0) AS total_offer_signed_with_tqc,
    COALESCE(aos.total_offer_signed - aos.total_offer_signed_with_tqc, 0) AS total_offer_signed_without_tqc,
    COALESCE(aos.total_offer_signed_with_ciq, 0) AS total_offer_signed_with_ciq,
    COALESCE(cql.total_first_listing, 0) AS total_first_listing,
    mp.year,
    mp.bimester
FROM
    member_profile AS mp
LEFT JOIN
    user_with_multiple_roles AS uwmr
        ON uwmr.id_main_user = mp.id_main_user
LEFT JOIN
    offer_signed AS aos
        ON aos.id_user = mp.id_main_user
        AND aos.bimester = mp.bimester
        AND aos.year = mp.year
LEFT JOIN
    ciq_first_listing AS cql
        ON cql.id_user = mp.id_main_user 
        AND cql.bimester = mp.bimester
        AND cql.year = mp.year
WHERE
    NOT (uwmr.id_main_user IS NOT NULL AND mp.business_context = 'RENT')
QUALIFY
    1 = ROW_NUMBER() OVER (PARTITION BY mp.id_main_user, mp.bimester, mp.year ORDER BY mp.ts_relationship_started DESC, mp.ts_relationship_ended DESC)