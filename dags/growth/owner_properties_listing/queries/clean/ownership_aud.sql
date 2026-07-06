SELECT
    id,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    house_listing_relation_id AS id_house_listing_relation,
    source_type_id AS id_source_type,
    related_as_id AS id_related_as,
    related_id AS id_related,
    property_id AS id_property,
    listing_business_context,
    updated_at AS ts_updated,
    house_listing_relation_id_mod AS mod_id_house_listing_relation,
    source_type_id_mod AS mod_id_source_type,
    related_as_id_mod AS mod_id_related_as,
    related_id_mod AS mod_id_related,
    property_id_mod AS mod_id_property,
    listing_business_context_mod AS mod_listing_business_context,
    year,
    month,
    day
FROM
    datalake_owner_properties_listing_raw.tb_ownership_aud
