-- Grain: one row per house (same as enrich house_development). Adds id_region
-- (raw FK), city_group (resolved), incorporadora company_name (from company_clean
-- via enrich uuid_company), and min/max price (from enrich listing_sale_type,
-- which already joins the SALE listing_sale_model) so consumers don't repeat those joins.
SELECT
    hd.id_house,
    hd.id_development,
    hd.id_development_typology,
    hd.uuid_company,
    hd.development_name,
    c.company_name,
    hd.construction_status,
    hd.provider,
    hd.postal_code,
    hd.street,
    hd.street_number,
    hd.neighborhood,
    hd.city,
    hd.state,
    hd.latitude,
    hd.longitude,
    hd.typology_type,
    hd.bedrooms,
    hd.bathrooms,
    hd.suites,
    hd.parking_spaces,
    hd.total_area,
    hd.amenities,
    hd.typology_attributes,
    hd.active_contact_uuid_person,
    hd.active_contact_status,
    h.id_region,
    r.city_group,
    lp.min_price,
    lp.max_price
FROM
    datalake_sale_primary_market.house_development AS hd
LEFT JOIN
    datalake_company_clean.company AS c
        ON c.uuid_company = hd.uuid_company
LEFT JOIN
    datalake_ebdb_clean.house AS h
        ON h.id = hd.id_house
LEFT JOIN
    datalake_region.region AS r
        ON r.id = h.id_region
LEFT JOIN
    datalake_sale_primary_market.listing_sale_type AS lp
        ON lp.id_house = hd.id_house
