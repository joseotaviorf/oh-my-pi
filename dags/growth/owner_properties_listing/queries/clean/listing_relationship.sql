SELECT
    id,
    user_id AS id_user,
    property_id AS id_property,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_owner_properties_listing_raw.tb_listing_relationship
