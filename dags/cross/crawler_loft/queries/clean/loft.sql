SELECT
  id,
  origin,
  address,
  city,
  geolocation,  
  name AS listing_name,
  crawl_metadata,
  house_info,
  status,
  type,  
  property_type,  
  contract_type,  
  image_urls,
  contact_information,
  agency_name,
  has_agency,
  is_marketplace,
  price,
  installments_price,
  created_at AS ts_created,
  date_info,
  year,
  month,
  day    
FROM
    datalake_crawler_loft_raw.loft
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')