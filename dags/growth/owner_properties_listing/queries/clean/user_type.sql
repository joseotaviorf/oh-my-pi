SELECT
    id,
    `type` AS user_type_code,
    year,
    month,
    day
FROM
    datalake_owner_properties_listing_raw.tb_user_type
