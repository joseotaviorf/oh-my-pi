SELECT
    id,
    `type` AS listing_status_type,
    priority AS listing_status_priority,
    year,
    month,
    day
FROM
    datalake_owner_properties_listing_raw.tb_listing_status
