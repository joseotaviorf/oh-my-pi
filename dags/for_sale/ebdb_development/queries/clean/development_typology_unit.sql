SELECT
    id,
    imovel_id AS id_house,
    development_id AS id_development,
    development_typology_id AS id_development_typology,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.DevelopmentTypologyUnit
