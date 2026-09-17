-- One row per house that has a development link, either as an offer-created
-- unit (development_typology_unit) or as the typology "shell" listing
-- (house.id_development_typology). Denormalizes Development + DevelopmentTypology
-- onto the house grain so consumers don't need to know the two link paths.
WITH latest_typology_unit AS (
    -- id_house is a FK on development_typology_unit, not its PK (id) — dedup
    -- to the latest row per house so this join can't fan out the house grain.
    SELECT
        id_house,
        id_development_typology
    FROM (
        SELECT
            id_house,
            id_development_typology,
            ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_updated DESC) AS _w
        FROM
            datalake_ebdb_clean.development_typology_unit
    ) AS _t
    WHERE
        _w = 1
),
house_typology AS (
    SELECT
        h.id AS id_house,
        COALESCE(dtu.id_development_typology, h.id_development_typology) AS id_development_typology
    FROM
        datalake_ebdb_clean.house AS h
    LEFT JOIN
        latest_typology_unit AS dtu
            ON dtu.id_house = h.id
    WHERE
        dtu.id_development_typology IS NOT NULL
        OR h.id_development_typology IS NOT NULL
),
-- Amenities are multi-valued per development — pre-aggregate to one row per
-- id_development so the join below can't fan out the house grain.
development_amenities AS (
    SELECT
        id_development,
        COLLECT_SET(amenity) AS amenities
    FROM
        datalake_ebdb_clean.development_amenity
    GROUP BY
        id_development
),
-- Typology attributes are multi-valued per typology — same pre-aggregation.
development_typology_attributes AS (
    SELECT
        id_development_typology,
        COLLECT_SET(attribute) AS typology_attributes
    FROM
        datalake_ebdb_clean.development_typology_attribute
    GROUP BY
        id_development_typology
)
SELECT
    ht.id_house,
    dt.id_development,
    ht.id_development_typology,
    d.company_uuid AS uuid_company,
    d.name AS development_name,
    d.construction_status,
    d.provider,
    d.postal_code,
    d.street,
    d.street_number,
    d.neighborhood,
    d.city,
    d.state,
    d.latitude,
    d.longitude,
    dt.type AS typology_type,
    dt.bedrooms,
    dt.bathrooms,
    dt.suites,
    dt.parking_spaces,
    dt.total_area,
    da.amenities,
    dta.typology_attributes,
    -- development.id_development_contact is already a single FK to the current
    -- active contact, so this join is 1:1 by construction — no aggregation needed.
    dc.uuid_person AS active_contact_uuid_person,
    dc.status AS active_contact_status
FROM
    house_typology AS ht
INNER JOIN
    datalake_ebdb_clean.development_typology AS dt
        ON dt.id = ht.id_development_typology
INNER JOIN
    datalake_ebdb_clean.development AS d
        ON d.id = dt.id_development
LEFT JOIN
    development_amenities AS da
        ON da.id_development = dt.id_development
LEFT JOIN
    development_typology_attributes AS dta
        ON dta.id_development_typology = ht.id_development_typology
LEFT JOIN
    datalake_ebdb_clean.development_contact AS dc
        ON dc.id = d.id_development_contact
