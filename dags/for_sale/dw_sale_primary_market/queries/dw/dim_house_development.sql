-- Grain: one row per house (same as enrich house_development). Adds id_region
-- (raw FK), city_group (resolved), and min/max price so consumers don't repeat
-- the region join or the latest-SALE-listing_sale_model join (same dedup
-- pattern as enrich listing_sale_type, but that table only carries sale_type).
WITH latest_lsm_price AS (
    SELECT
        id_house,
        min_price,
        max_price
    FROM (
        SELECT
            lbc.id_house,
            lsm.min_price,
            lsm.max_price,
            ROW_NUMBER() OVER (PARTITION BY lbc.id_house ORDER BY lbc.ts_updated DESC) AS _w
        FROM
            datalake_ebdb_clean.listing_business_context AS lbc
        INNER JOIN
            datalake_ebdb_clean.listing_sale_model AS lsm
                ON lbc.id = lsm.id_listing_business_context
        WHERE
            lbc.business_context = 'SALE'
    ) AS _t
    WHERE
        _w = 1
)
SELECT
    hd.id_house,
    hd.id_development,
    hd.id_development_typology,
    hd.development_name,
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
    datalake_ebdb_clean.house AS h
        ON h.id = hd.id_house
LEFT JOIN
    datalake_region.region AS r
        ON r.id = h.id_region
LEFT JOIN
    latest_lsm_price AS lp
        ON lp.id_house = hd.id_house
