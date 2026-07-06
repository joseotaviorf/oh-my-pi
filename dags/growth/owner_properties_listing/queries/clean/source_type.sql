SELECT
    id,
    `type` AS source_type_code,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_owner_properties_listing_raw.tb_source_type
