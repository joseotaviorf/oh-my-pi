SELECT
    id,
    image_urls,
    geolocation,
    name AS listing_name,
    address,
    crawl_metadata,
    metadata,
    price,
    type,
    house_info,
    date_info,
    city,
    year,
    month,
    day
FROM
    datalake_crawlers_listings_raw.emcasa
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}