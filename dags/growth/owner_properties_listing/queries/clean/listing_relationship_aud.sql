SELECT
    id,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    user_id AS id_user,
    property_id AS id_property,
    updated_at AS ts_updated,
    user_id_mod AS mod_id_user,
    property_id_mod AS mod_id_property,
    year,
    month,
    day
FROM
    datalake_owner_properties_listing_raw.tb_listing_relationship_aud
