SELECT
    id,
    development_id AS id_development,
    development_typology_uuid,
    type,
    total_units,
    available_units,
    total_area,
    bedrooms,
    bathrooms,
    suites,
    parking_spaces,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.DevelopmentTypology
