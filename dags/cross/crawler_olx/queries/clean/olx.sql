SELECT
  id,
  origin,
  address,
  city,
  region,
  name AS listing_name,
  crawl_metadata,
  house_info,
  type,
  image_urls,
  advertiser AS contact_information,
  price,
  date_info,
  year,
  month,
  day
FROM
  datalake_crawler_olx_raw.olx
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')