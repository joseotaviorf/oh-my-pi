SELECT
    id,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    property_id AS id_property,
    demand_score_sale,
    demand_score_rent,
    property_id_mod AS mod_id_property,
    demand_score_sale_mod AS mod_demand_score_sale,
    demand_score_rent_mod AS mod_demand_score_rent,
    year,
    month,
    day
FROM
    datalake_owner_properties_listing_raw.tb_listing_score_aud
