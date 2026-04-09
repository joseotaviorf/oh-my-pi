SELECT
    id_house_platform,
    id_house,
    platform,
    advertiser_listing_id,
    country,
    state,
    address_city,
    neighborhood,
    street,
    street_number,
    zip_code,
    latitude,
    longitude,
    listing_name,
    total_area,
    amenities,
    bathrooms,
    bedrooms,
    floors,
    parking_spaces,
    suites,
    unit_type,
    usage_type,
    advertiser_id,
    advertiser_name,
    advertiser_phone,
    condo_fee,
    iptu,
    price_rental,
    price_sale,
    price_m2_rental,
    price_m2_sale,
    is_for_rent,
    is_for_sale,
    is_hybrid,
    ts_created::TIMESTAMP AS ts_created,
    ts_updated::TIMESTAMP AS ts_updated
FROM
    datalake_crawler_zap_imoveis.zap_imoveis
WHERE
    ts_updated IS NOT NULL
    AND MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_house ORDER BY ts_updated DESC) = 1
