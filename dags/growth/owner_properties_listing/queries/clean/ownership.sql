SELECT
    id,
    house_listing_relation_id AS id_house_listing_relation,
    source_type_id AS id_source_type,
    related_as_id AS id_related_as,
    related_id AS id_related,
    property_id AS id_property,
    listing_business_context,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_owner_properties_listing_raw.tb_ownership
