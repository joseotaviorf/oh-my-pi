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
)
SELECT
    ht.id_house,
    dt.id_development,
    ht.id_development_typology,
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
    dt.total_area
FROM
    house_typology AS ht
INNER JOIN
    datalake_ebdb_clean.development_typology AS dt
        ON dt.id = ht.id_development_typology
INNER JOIN
    datalake_ebdb_clean.development AS d
        ON d.id = dt.id_development
