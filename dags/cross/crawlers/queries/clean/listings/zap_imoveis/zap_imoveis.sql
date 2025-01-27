SELECT
    id,
    origin,
    address,
    region,
    geolocation,
    name AS listing_name,
    crawl_metadata,
    house_info,
    type,
    image_urls,
    contact_information,
    price,
    date_info,
    city,
    year,
    month,
    day
FROM
    datalake_crawlers_listings_raw.zapimoveis
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}