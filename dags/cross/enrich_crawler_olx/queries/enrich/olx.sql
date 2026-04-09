 WITH json_select AS (
      SELECT
          id AS id_house_platform,
          CONCAT(id, 'olx') AS id_house,
          COALESCE(origin, 'olx') AS platform,
          city,
          TO_JSON(address) AS address,
          listing_name AS listing_name,
          TO_JSON(house_info) AS house_info,
          TO_JSON(type) AS type,
          TO_JSON(contact_information) AS contact_information,
          TO_JSON(advertiser) AS advertiser,
          TO_JSON(price) AS price,
          TO_JSON(date_info) AS date_info,
          year,
          month,
          day
      FROM
          datalake_crawler_olx_clean.olx 
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
    GET_JSON_OBJECT(address,'$.address') AS street,
    GET_JSON_OBJECT(address,'$.zip_code') AS zip_code,
    listing_name,
    CAST(GET_JSON_OBJECT(house_info,'$.size') AS INTEGER) AS total_area,
    GET_JSON_OBJECT(house_info,'$.re_features') AS amenities,
    CAST(GET_JSON_OBJECT(house_info,'$.bathrooms') AS INTEGER) AS bathrooms,
    CAST(GET_JSON_OBJECT(house_info,'$.rooms') AS INTEGER) AS bedrooms,
    CAST(GET_JSON_OBJECT(house_info,'$.garage_spaces') AS INTEGER) AS parking_spaces,
    CAST(GET_JSON_OBJECT(house_info,'$.unit_type') AS STRING) AS unit_type,
    CAST(GET_JSON_OBJECT(house_info,'$.re_types') AS STRING) AS unit_subtype,
    CAST(GET_JSON_OBJECT(advertiser,'$.id') AS STRING) AS advertiser_id,
    COALESCE(GET_JSON_OBJECT(contact_information,'$.advertiser_name'),
             GET_JSON_OBJECT(advertiser,'$.name')) AS advertiser_name,
    COALESCE(GET_JSON_OBJECT(contact_information,'$.advertiser_phones[0]'),
             GET_JSON_OBJECT(advertiser,'$.phones.primary')) AS advertiser_phone,
    CAST(REPLACE(REGEXP_EXTRACT(GET_JSON_OBJECT(house_info,'$.condominio'), '([0-9]+(?:[.,][0-9]+)?)', 1), '.', '') AS DOUBLE) AS condo_fee,
    CAST(REPLACE(REGEXP_EXTRACT(GET_JSON_OBJECT(house_info,'$.iptu'), '([0-9]+(?:[.,][0-9]+)?)', 1), '.', '') AS DOUBLE) AS iptu,
    CAST(GET_JSON_OBJECT(price,'$.rent.price') AS DOUBLE) AS rent_price,
    CAST(GET_JSON_OBJECT(price,'$.sale.price') AS DOUBLE) AS sale_price,
    ROUND(CAST(GET_JSON_OBJECT(price,'$.rent.price') AS DOUBLE)/CAST(GET_JSON_OBJECT(house_info,'$.size') AS INTEGER), 2) AS price_m2_rental,
    ROUND(CAST(GET_JSON_OBJECT(price,'$.sale.price') AS DOUBLE)/CAST(GET_JSON_OBJECT(house_info,'$.size') AS INTEGER), 2) AS price_m2_sale,
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