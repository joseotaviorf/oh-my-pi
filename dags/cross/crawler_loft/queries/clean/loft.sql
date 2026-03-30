SELECT
  id,
  origin,
  address,
  city,
  geolocation,  
  name AS listing_name,
  crawl_metadata,
  house_info,
  type,  
  property_type,  
  contract_type,  
  image_urls,
  contact_information,
  agency_id,
  agency_name,
  agency_email,
  agency_cnpj,
  agency_address AS agency_location,
  has_agency,
  is_marketplace,
  price,
  installments_price,
  date_info,
  year,
  month,
  day    
FROM
    datalake_crawler_loft_raw.loft
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')