SELECT
  id, 
  origin, 
  address, 
  city, 
  geolocation, 
  name AS listing_name, 
  description AS listing_description, 
  crawl_metadata, 
  house_info, 
  type, 
  image_urls, 
  advertiser, 
  price, 
  date_info, 
  year,
  month,
  day
FROM
  datalake_crawler_chaves_na_mao_raw.chaves_na_mao
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')