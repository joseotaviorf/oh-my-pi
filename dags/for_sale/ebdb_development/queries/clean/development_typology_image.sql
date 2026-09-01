SELECT
    development_image_asset_id AS id_development_image_asset,
    development_typology_id AS id_development_typology,
    created_at AS ts_created
FROM
    datalake_ebdb_raw.DevelopmentTypologyImage
