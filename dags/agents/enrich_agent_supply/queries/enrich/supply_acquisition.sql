WITH supply_acquisition AS (
    SELECT
        XXHASH64(sf.id, "SUPPLY_ACQUISITION") AS id_acquisition,
        sf.id AS id_supply_acquisition,
        sf.id_property AS id_house,
        au.id_agent,
        au.id_user,
        "SUPPLY_ACQUISITION" AS source,
        ap.product_name AS agent_profile,
        COALESCE(sf.status = "ACTIVE", FALSE) AS is_active,
        sf.ts_start AS ts_started,
        sf.ts_end AS ts_ended,
        sf.ts_created,
        sf.ts_updated
    FROM
        datalake_ebdb_clean.supply_acquisition AS sf
    JOIN
        datalake_ebdb_agent_events.agent_unified_identity AS au
            ON au.uuid_agent = sf.uuid_agent
    JOIN
        datalake_ebdb_agent_events.agent_product AS ap
            ON ap.id_unified_agent = au.id_unified_agent
            AND ap.is_lastest IS TRUE
            AND ap.is_valid_product IS TRUE
    WHERE
        DATE(sf.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
legacy_supply_acquisition AS (
    SELECT
        XXHASH64(legacy.id_agency, "LEGACY_AGENCY") AS id_acquisition,
        -1 AS id_supply_acquisition,
        legacy.id_house,
        au.id_agent,
        COALESCE(au.id_user, legacy.id_user) AS id_user,
        "LEGACY_AGENCY" AS source,
        CASE
            WHEN legacy.consultant_type = "CIQ_FULL" THEN "AUTONOMOUS_BROKERAGE_AGENT"
            ELSE legacy.consultant_type
        END AS agent_profile,
        legacy.ts_enrollment_ended IS NULL AS is_active,
        ROW_NUMBER() OVER (PARTITION BY legacy.id_house, legacy.consultant_type ORDER BY legacy.ts_enrollment_started ASC, legacy.ts_enrollment_ended DESC) = 1 AS is_first_enrollment,
        legacy.ts_enrollment_started AS ts_started,
        legacy.ts_enrollment_ended AS ts_ended,
        legacy.ts_agency_created AS ts_created,
        COALESCE(legacy.ts_enrollment_ended, legacy.ts_enrollment_started) AS ts_updated
    FROM
        datalake_big_agent.house_consultant_history AS legacy
    LEFT JOIN
        datalake_ebdb_agent_events.agent_unified_identity AS au
            ON au.id_partner = legacy.id_partner
            AND au.is_partner_replace_key IS TRUE
    LEFT JOIN
        supply_acquisition AS current
            ON current.id_house = legacy.id_house
            AND current.id_user = COALESCE(au.id_user, legacy.id_user)
    WHERE
        current.id_house IS NULL
        AND legacy.is_last_status_of_day IS TRUE
        AND legacy.consultant_type IN ("PRO_ACQUIRER", "CIQ_FULL")
        AND legacy.ts_enrollment_started < DATE('2026-09-01')
        AND DATE(COALESCE(legacy.ts_enrollment_ended, legacy.ts_enrollment_started)) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
union_supply_acquisition AS (
    SELECT
        sf.id_acquisition,
        sf.id_supply_acquisition,
        sf.id_house,
        sf.id_agent,
        sf.id_user,
        sf.source,
        sf.agent_profile,
        sf.is_active,
        sf.ts_started,
        sf.ts_ended,
        sf.ts_created,
        sf.ts_updated,
        YEAR(sf.ts_updated) AS year,
        MONTH(sf.ts_updated) AS month,
        DAY(sf.ts_updated) AS day
    FROM
        supply_acquisition AS sf
    UNION ALL
    SELECT
        sf.id_acquisition,
        sf.id_supply_acquisition,
        sf.id_house,
        sf.id_agent,
        sf.id_user,
        sf.source,
        sf.agent_profile,
        sf.is_active,
        sf.ts_started,
        sf.ts_ended,
        sf.ts_created,
        sf.ts_updated,
        YEAR(sf.ts_updated) AS year,
        MONTH(sf.ts_updated) AS month,
        DAY(sf.ts_updated) AS day
    FROM
        legacy_supply_acquisition AS sf
    WHERE
        sf.is_first_enrollment IS TRUE
),
house_business_context AS (
    SELECT
        sf.id_house,
        MIN(COALESCE(lbc.ts_first_publication, lbc.ts_created)) FILTER (WHERE lbc.business_context = "RENT") AS ts_first_publication_on_rent,
        MIN(COALESCE(lbc.ts_first_publication, lbc.ts_created)) FILTER (WHERE lbc.business_context = "SALE") AS ts_first_publication_on_sale
    FROM
        union_supply_acquisition AS sf
    JOIN
        datalake_ebdb_clean.listing_business_context AS lbc
            ON lbc.id_house = sf.id_house
    GROUP BY 1 
)
SELECT
    sf.id_acquisition,
    sf.id_supply_acquisition,
    sf.id_house,
    sf.id_agent,
    sf.id_user,
    sf.source,
    sf.agent_profile,
    CASE
        WHEN hbc.ts_first_publication_on_rent = hbc.ts_first_publication_on_sale THEN "HYBRID"
        WHEN hbc.ts_first_publication_on_sale IS NULL AND hbc.ts_first_publication_on_rent IS NOT NULL THEN "RENT"
        WHEN hbc.ts_first_publication_on_sale IS NOT NULL AND hbc.ts_first_publication_on_rent IS NULL THEN "SALE"
    END AS acquisition_business_context,
    sf.is_active,
    sf.ts_started,
    sf.ts_ended,
    LEAST(hbc.ts_first_publication_on_rent, hbc.ts_first_publication_on_sale) AS ts_first_publication,
    h.ts_created AS ts_house_created,
    sf.ts_created,
    sf.ts_updated,
    sf.year,
    sf.month,
    sf.day
FROM
    union_supply_acquisition AS sf
JOIN
    core_house.house AS h
        ON h.id_house = sf.id_house
LEFT JOIN
    house_business_context AS hbc
        ON hbc.id_house = sf.id_house