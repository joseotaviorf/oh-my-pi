SELECT
    id,
    property_id AS id_property,
    demand_score_sale,
    demand_score_rent,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_owner_properties_listing_raw.tb_listing_score
