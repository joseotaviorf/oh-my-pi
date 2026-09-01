SELECT
    id,
    development_typology_unit_id AS id_development_typology_unit,
    development_negotiation_id AS id_development_negotiation,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.DevelopmentNegotiationUnit
