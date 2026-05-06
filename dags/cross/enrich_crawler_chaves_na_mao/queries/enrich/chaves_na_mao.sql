WITH json_select AS (
  SELECT
      id AS id_house_platform,
      CONCAT(id, 'chaves-na-mao') AS id_house,
      COALESCE(origin, 'chaves-na-mao') AS platform,
      city,
      TO_JSON(address) AS address,
      TO_JSON(geolocation) AS geolocation,
      listing_name AS listing_name,
      TO_JSON(crawl_metadata) AS crawl_metadata,
      TO_JSON(house_info) AS house_info,
      TO_JSON(type) AS type,
      TO_JSON(advertiser) AS advertiser,
      TO_JSON(price) AS price,
      TO_JSON(date_info) AS date_info,
      year,
      month,
      day
  FROM
    datalake_crawler_chaves_na_mao_clean.chaves_na_mao
  WHERE 
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT 
  id_house_platform,
  id_house,
  platform,
  GET_JSON_OBJECT(house_info, '$.external_id') AS advertiser_listing_id,
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
  GET_JSON_OBJECT(address,'$.number') AS number,
  GET_JSON_OBJECT(address,'$.zip_code') AS zip_code,
  GET_JSON_OBJECT(geolocation,'$.latitude') AS latitude,
  GET_JSON_OBJECT(geolocation,'$.longitude') AS longitude,
  listing_name,
  GET_JSON_OBJECT(crawl_metadata,'$.listing_url') AS listing_url,
  CAST(GET_JSON_OBJECT(house_info,'$.total_area') AS INTEGER) AS total_area,
  CAST(GET_JSON_OBJECT(house_info,'$.area') AS INTEGER) AS area,      
  GET_JSON_OBJECT(house_info,'$.commonItems') AS common_items,
  GET_JSON_OBJECT(house_info,'$.privativeItems') AS privative_items,
  CAST(GET_JSON_OBJECT(house_info,'$.bathrooms') AS INTEGER) AS bathrooms,
  CAST(GET_JSON_OBJECT(house_info,'$.bedrooms') AS INTEGER) AS bedrooms,
  CAST(GET_JSON_OBJECT(house_info,'$.suites') AS INTEGER) AS suites,
  CAST(GET_JSON_OBJECT(house_info,'$.parking_spaces') AS INTEGER) AS parking_spaces,
  GET_JSON_OBJECT(type,'$.publication_type') AS publication_type,
  GET_JSON_OBJECT(type,'$.unit_type') AS unit_type,
  GET_JSON_OBJECT(type,'$.usage_type') AS usage_type,      
  CASE
    WHEN GET_JSON_OBJECT(type,'$.operation_type') = 'rent' THEN TRUE
    ELSE FALSE
  END AS is_for_rent,       
  CASE
    WHEN GET_JSON_OBJECT(type,'$.operation_type') = 'sale' THEN TRUE
    ELSE FALSE
  END AS is_for_sale,             
  CASE
    WHEN is_for_rent AND is_for_sale THEN TRUE
    ELSE FALSE
  END AS is_hybrid, 
  REGEXP_EXTRACT(SPLIT_PART(GET_JSON_OBJECT(advertiser,'$.url'), '-', -1), '([0-9]+)', 1) AS advertiser_id,
  GET_JSON_OBJECT(advertiser,'$.name') AS advertiser_name,   
  GET_JSON_OBJECT(advertiser,'$.phone') AS advertiser_phone,
  GET_JSON_OBJECT(advertiser,'$.address.creci') AS advertiser_creci,      
  GET_JSON_OBJECT(advertiser,'$.url') AS advertiser_url,
  GET_JSON_OBJECT(advertiser,'$.address.state') AS advertiser_address_state,
  GET_JSON_OBJECT(advertiser,'$.address.city') AS advertiser_address_city,
  GET_JSON_OBJECT(advertiser,'$.address.postalCode') AS advertiser_address_zip_code,
  GET_JSON_OBJECT(advertiser,'$.address.addressLocality') AS advertiser_address_neighborhood,
  GET_JSON_OBJECT(advertiser,'$.address.streetAddress') AS advertiser_address_street,
  GET_JSON_OBJECT(advertiser,'$.address.number') AS advertiser_address_street_number,
  CASE  
    WHEN GET_JSON_OBJECT(type,'$.operation_type') = 'rent' THEN CAST(GET_JSON_OBJECT(price,'$.rent.condo_fee') AS DOUBLE)
    ELSE CAST(GET_JSON_OBJECT(price,'$.sale.condo_fee') AS DOUBLE)
  END AS condo_fee,
  CASE  
    WHEN GET_JSON_OBJECT(type,'$.operation_type') = 'rent' THEN CAST(GET_JSON_OBJECT(price,'$.rent.iptu') AS DOUBLE)
    ELSE CAST(GET_JSON_OBJECT(price,'$.sale.iptu') AS DOUBLE)
  END AS iptu,
  CAST(GET_JSON_OBJECT(price,'$.rent.price') AS DOUBLE) AS rent_price,
  CAST(GET_JSON_OBJECT(price,'$.sale.price') AS DOUBLE) AS sale_price,         
  ROUND(CAST(GET_JSON_OBJECT(price,'$.rent.price') AS DOUBLE)/CAST(GET_JSON_OBJECT(house_info,'$.total_area') AS INTEGER), 2) AS price_m2_rental,
  ROUND(CAST(GET_JSON_OBJECT(price,'$.sale.price') AS DOUBLE)/CAST(GET_JSON_OBJECT(house_info,'$.total_area') AS INTEGER), 2) AS price_m2_sale,
  CAST(GET_JSON_OBJECT(date_info,'$.publication_created_at') AS TIMESTAMP) AS ts_created,
  CAST(GET_JSON_OBJECT(date_info,'$.updated_at') AS TIMESTAMP) AS ts_updated,
  year,
  month,
  day
FROM
    json_select