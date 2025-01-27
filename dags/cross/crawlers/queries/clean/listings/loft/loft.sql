SELECT
    id,
    address,
    agency_name,
    contact_information,
    crawl_metadata,
    date_info,
    geolocation,
    house_info,
    image_urls,
    metadata,
    name AS listing_name,
    origin,
    price,
    installments_price,
    region,
    contract_type,
    type,
    property_type,
    city,
    status,
    has_agency,
    is_marketplace,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_crawlers_listings_raw.loft
WHERE
    year={year}
    AND month={month}
    AND day={day}
