SELECT
    id,
    development_typology_unit_id AS id_development_typology_unit,
    listing_business_context_id AS id_listing_business_context,
    development_typology_id AS id_development_typology,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.DevelopmentListingUnit
