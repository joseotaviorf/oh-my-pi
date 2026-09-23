WITH supply_conversion_consultancy AS (
    SELECT
        XXHASH64(sf.id, "SUPPLY_CONVERSION_CONSULTANCY") AS id_consultancy,
        sf.id AS id_supply_conversion_consultancy,
        sf.id_property AS id_house,
        au.id_agent,
        au.id_user,
        au.id_unified_agent,
        au.uuid_agent,
        "SUPPLY_CONVERSION_CONSULTANCY" AS source,
        ap.product_name AS agent_profile,
        COALESCE(sf.status = "ACTIVE", FALSE) AS is_active,
        sf.ts_start AS ts_started,
        sf.ts_end AS ts_ended,
        sf.ts_created,
        sf.ts_updated
    FROM
        datalake_ebdb_clean.supply_conversion_consultancy AS sf
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
legacy_supply_conversion_consultancy AS (
    SELECT
        XXHASH64(legacy.id_agency, "LEGACY_AGENCY") AS id_consultancy,
        -1 AS id_supply_conversion_consultancy,
        legacy.id_house,
        au.id_agent,
        au.id_unified_agent,
        au.uuid_agent,
        COALESCE(au.id_user, legacy.id_user) AS id_user,
        "LEGACY_AGENCY" AS source,
        CASE
            WHEN legacy.consultant_type = "CIQ_FULL" THEN "AUTONOMOUS_BROKERAGE_AGENT"
            ELSE UPPER(legacy.consultant_type)
        END AS agent_profile,
        legacy.ts_enrollment_ended IS NULL AS is_active,
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
    WHERE
        legacy.is_last_status_of_day IS TRUE
        AND legacy.consultant_type <> "PRO_ACQUIRER" -- exception: PRO_ACQUIRER is a acquisition agent, not a consultancy agent
        AND legacy.ts_enrollment_started < DATE('2026-09-01')
        AND DATE(COALESCE(legacy.ts_enrollment_ended, legacy.ts_enrollment_started)) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    sf.id_consultancy,
    sf.id_supply_conversion_consultancy,
    sf.id_house,
    sf.id_agent,
    sf.id_user,
    sf.id_unified_agent,
    sf.uuid_agent,
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
    supply_conversion_consultancy AS sf
UNION
SELECT
    sf.id_consultancy,
    sf.id_supply_conversion_consultancy,
    sf.id_house,
    sf.id_agent,
    sf.id_user,
    sf.id_unified_agent,
    sf.uuid_agent,
    sf.source,
    sf.agent_profile,
    sf.is_active,
    CAST(sf.ts_started AS TIMESTAMP) AS ts_started,
    CAST(sf.ts_ended AS TIMESTAMP) AS ts_ended,
    sf.ts_created,
    sf.ts_updated,
    YEAR(sf.ts_updated) AS year,
    MONTH(sf.ts_updated) AS month,
    DAY(sf.ts_updated) AS day
FROM
    legacy_supply_conversion_consultancy AS sf
LEFT JOIN
    datalake_ebdb_agent_events.agent_unified_identity AS au
        ON au.id_user = sf.id_user
        AND au.uuid_agent IS NOT NULL
LEFT JOIN
    datalake_ebdb_clean.supply_conversion_consultancy AS current
        ON current.id_property = sf.id_house
        AND current.uuid_agent = COALESCE(sf.uuid_agent, au.uuid_agent)
WHERE
    current.id_property IS NULL