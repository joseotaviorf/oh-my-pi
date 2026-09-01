SELECT
    id,
    development_id AS id_development,
    external_id,
    type,
    storage_key,
    caption,
    display_order,
    is_cover,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.DevelopmentImageAsset
