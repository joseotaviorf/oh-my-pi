SELECT
    development_typology_id AS id_development_typology,
    attribute,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.DevelopmentTypologyAttribute
