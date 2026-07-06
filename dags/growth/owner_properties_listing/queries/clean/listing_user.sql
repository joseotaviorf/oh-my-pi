SELECT
    id,
    external_id AS id_external,
    user_type_id AS id_user_type,
    year,
    month,
    day
FROM
    datalake_owner_properties_listing_raw.tb_user
