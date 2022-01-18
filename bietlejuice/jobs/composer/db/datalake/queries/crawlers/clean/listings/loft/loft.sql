SELECT 
    id,
    address,
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
    region,
    type,
    city,
    year,
    month,
    day
FROM
    datalake_crawlers_listings_raw.loft
WHERE
    year={year}
    AND month={month}
    AND day={day}