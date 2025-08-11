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
  datalake_crawler_zap_imoveis_raw.zap_imoveis
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
