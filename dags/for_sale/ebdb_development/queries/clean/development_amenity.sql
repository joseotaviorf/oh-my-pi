SELECT
    development_id AS id_development,
    amenity,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.DevelopmentAmenity
