WITH json_select AS (
  SELECT
      id AS id_house_platform,
      CONCAT(id, 'loft') AS id_house,
      COALESCE(origin, 'loft') AS platform,
      city,
      TO_JSON(address) AS address,
      TO_JSON(geolocation) AS geolocation,
      listing_name AS listing_name,      
      TO_JSON(crawl_metadata) AS crawl_metadata,
      TO_JSON(house_info) AS house_info,
      TO_JSON(type) AS type,
      property_type,
      contract_type,
      TO_JSON(contact_information) AS contact_information,
      agency_id AS advertiser_id,
      agency_name AS advertiser_name,
      agency_email AS advertiser_email,
      agency_cnpj AS advertiser_cnpj,
      agency_location AS advertiser_location,
      has_agency AS has_advertiser,
      is_marketplace,
      TO_JSON(price) AS price,
      installments_price,
      TO_JSON(date_info) AS date_info,
      year,
      month,
      day
  FROM
    datalake_crawler_loft_clean.loft
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  )
SELECT 
  id_house_platform,
  id_house,
  platform,
  GET_JSON_OBJECT(address,'$.country') AS country,
  GET_JSON_OBJECT(address,'$.state') AS state,
  CASE
    WHEN GET_JSON_OBJECT(address,'$.city') REGEXP '\,'
      THEN COALESCE(REGEXP_EXTRACT(REGEXP_REPLACE(GET_JSON_OBJECT(address,'$.city'), "\'", ""), ', +(.*)'), city)
    WHEN GET_JSON_OBJECT(address,'$.city') REGEXP "\'"
      THEN REGEXP_REPLACE(GET_JSON_OBJECT(address,'$.city'), "\'", "")
    ELSE COALESCE(GET_JSON_OBJECT(address,'$.city'), city)
  END AS address_city,
  GET_JSON_OBJECT(address,'$.neighborhood') AS neighborhood,
  GET_JSON_OBJECT(address,'$.street') AS street,
  GET_JSON_OBJECT(geolocation,'$.latitude') AS latitude,
  GET_JSON_OBJECT(geolocation,'$.longitude') AS longitude,
  listing_name,
  GET_JSON_OBJECT(crawl_metadata,'$.listing_url') AS listing_url,
  CAST(GET_JSON_OBJECT(house_info,'$.total_area') AS INTEGER) AS total_area,
  CAST(GET_JSON_OBJECT(house_info,'$.area') AS INTEGER) AS area,      
  CAST(GET_JSON_OBJECT(house_info,'$.bathrooms') AS INTEGER) AS bathrooms,
  CAST(GET_JSON_OBJECT(house_info,'$.bedrooms') AS INTEGER) AS bedrooms,
  CAST(GET_JSON_OBJECT(house_info,'$.suites') AS INTEGER) AS suites,
  CAST(GET_JSON_OBJECT(house_info,'$.floor') AS INTEGER) AS floor,
  CAST(GET_JSON_OBJECT(house_info,'$.parking_spaces') AS INTEGER) AS parking_spaces,
  CAST(GET_JSON_OBJECT(house_info,'$.unit_type') AS STRING) AS unit_type,
  CAST(GET_JSON_OBJECT(house_info,'$.usage_type[0]') AS STRING) AS usage_type,
  GET_JSON_OBJECT(house_info,'$.amenities') AS amenities, 
  GET_JSON_OBJECT(house_info,'$.infrastructure') AS infrastructure, 
  property_type,
  contract_type,
  advertiser_id,
  advertiser_name,
  advertiser_email,
  advertiser_cnpj,
  advertiser_location,
  has_advertiser,
  is_marketplace,  
  GET_JSON_OBJECT(contact_information, '$.advertiser_phones[0]') AS advertiser_phone,
  CASE  
    WHEN CAST(GET_JSON_OBJECT(type,'$.rentable') AS BOOLEAN) = TRUE THEN CAST(GET_JSON_OBJECT(price,'$.rent.condo_fee') AS DOUBLE)
    ELSE CAST(GET_JSON_OBJECT(price,'$.sale.condo_fee') AS DOUBLE)
  END AS condo_fee,
  CASE  
    WHEN CAST(GET_JSON_OBJECT(type,'$.rentable') AS BOOLEAN) = TRUE THEN CAST(GET_JSON_OBJECT(price,'$.rent.iptu_month') AS DOUBLE)
    ELSE CAST(GET_JSON_OBJECT(price,'$.sale.iptu_month') AS DOUBLE)
  END AS iptu,
  CAST(GET_JSON_OBJECT(price,'$.rent.price') AS DOUBLE) AS rent_price,
  CAST(GET_JSON_OBJECT(price,'$.sale.price') AS DOUBLE) AS sale_price,
  ROUND(CAST(GET_JSON_OBJECT(price,'$.rent.price') AS DOUBLE)/CAST(GET_JSON_OBJECT(house_info,'$.total_area') AS INTEGER), 2) AS price_m2_rental,
  ROUND(CAST(GET_JSON_OBJECT(price,'$.sale.price') AS DOUBLE)/CAST(GET_JSON_OBJECT(house_info,'$.total_area') AS INTEGER), 2) AS price_m2_sale,
  installments_price,
  CAST(GET_JSON_OBJECT(type,'$.rentable') AS BOOLEAN) AS is_for_rent, 
  CAST(GET_JSON_OBJECT(type,'$.buyable') AS BOOLEAN) AS is_for_sale,
  CASE
    WHEN GET_JSON_OBJECT(type,'$.rentable') = TRUE
      AND GET_JSON_OBJECT(type,'$.buyable') = TRUE THEN TRUE
    ELSE FALSE
  END AS is_hybrid,
  GET_JSON_OBJECT(date_info,'$.created_at') AS ts_created,
  year,
  month,
  day
FROM
  json_select