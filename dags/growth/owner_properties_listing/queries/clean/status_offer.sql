SELECT
    id,
    version,
    property_id AS id_property,
    status AS offer_status,
    offers,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_owner_properties_listing_raw.tb_status_offer
