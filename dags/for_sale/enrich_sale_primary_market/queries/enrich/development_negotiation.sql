-- One row per primary-market pré-OS negotiation. Visit is the shell listing
-- (Approach A). Unit house is the typology unit linked to the negotiation
-- (offer / published apt). Product is 1 negotiation → 1 unit; if CDC attaches
-- more than one unit, keep the latest link only.
WITH latest_negotiation_unit AS (
    SELECT
        id,
        id_development_negotiation,
        id_development_typology_unit,
        ts_created,
        ts_updated
    FROM (
        SELECT
            id,
            id_development_negotiation,
            id_development_typology_unit,
            ts_created,
            ts_updated,
            ROW_NUMBER() OVER (
                PARTITION BY id_development_negotiation
                ORDER BY ts_updated DESC
            ) AS _w
        FROM
            datalake_ebdb_clean.development_negotiation_unit
    ) AS _negotiation_unit
    WHERE
        _w = 1
),
latest_listing_unit AS (
    SELECT
        id,
        id_development_typology_unit,
        id_listing_business_context,
        id_development_typology
    FROM (
        SELECT
            id,
            id_development_typology_unit,
            id_listing_business_context,
            id_development_typology,
            ROW_NUMBER() OVER (
                PARTITION BY id_development_typology_unit
                ORDER BY ts_updated DESC
            ) AS _w
        FROM
            datalake_ebdb_clean.development_listing_unit
    ) AS _listing_unit
    WHERE
        _w = 1
)
SELECT
    n.id AS id_development_negotiation,
    n.id_development,
    n.id_visit,
    v.id_house AS id_house_shell,
    v.id_visitor,
    n.id_demand,
    n.id_agent,
    nu.id AS id_development_negotiation_unit,
    nu.id_development_typology_unit,
    dtu.id_house,
    CAST(NULL AS BIGINT) AS id_offer,
    CAST(NULL AS BIGINT) AS id_sales_flow,
    dtu.id_development_typology,
    dlu.id AS id_development_listing_unit,
    dlu.id_listing_business_context,
    d.id_development_contact,
    n.uuid_event,
    n.actor,
    CASE
        WHEN dtu.id IS NULL THEN NULL
        ELSE dlu.id IS NOT NULL
    END AS is_published_unit,
    n.ts_created,
    n.ts_updated
FROM
    datalake_ebdb_clean.development_negotiation AS n
LEFT JOIN
    datalake_ebdb_clean.visit AS v
        ON v.id = n.id_visit
LEFT JOIN
    latest_negotiation_unit AS nu
        ON nu.id_development_negotiation = n.id
LEFT JOIN
    datalake_ebdb_clean.development_typology_unit AS dtu
        ON dtu.id = nu.id_development_typology_unit
LEFT JOIN
    latest_listing_unit AS dlu
        ON dlu.id_development_typology_unit = dtu.id
LEFT JOIN
    datalake_ebdb_clean.development AS d
        ON d.id = n.id_development
