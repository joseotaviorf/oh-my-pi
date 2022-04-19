WITH json_select AS(
    SELECT
        id AS id_house_platform,
        CONCAT(id, 'VivaReal') AS id_house,
        COALESCE(origin, 'VivaReal') AS platform,
        city,
        TO_JSON(address) AS address,
        TO_JSON(geolocation) AS geolocation,
        listing_name AS listing_name,
        TO_JSON(house_info) AS house_info,
        TO_JSON(type) AS type,
        TO_JSON(contact_information) AS contact_information,
        price,
        TO_JSON(date_info) AS date_info,
        year,
        month,
        day
    FROM
        datalake_crawlers_listings_clean.viva_real
)
    SELECT
        id_house_platform,
        id_house,
        platform,
        GET_JSON_OBJECT(address,'$.country') AS country,
        GET_JSON_OBJECT(address,'$.state') AS state,
        CASE
            WHEN GET_JSON_OBJECT(address,'$.city') REGEXP '\,' 
                THEN COALESCE(REGEXP_EXTRACT(GET_JSON_OBJECT(address,'$.city'), ',\s(.*)'), city)
            ELSE COALESCE(GET_JSON_OBJECT(address,'$.city'), city)
        END AS address_city,
        city AS city,
        GET_JSON_OBJECT(address,'$.neighborhood') AS neighborhood,
        GET_JSON_OBJECT(address,'$.street') AS street,
        GET_JSON_OBJECT(address,'$.number') AS st_number,
        GET_JSON_OBJECT(address,'$.zip_code') AS zip_code,
        GET_JSON_OBJECT(geolocation,'$.latitude') AS latitude,
        GET_JSON_OBJECT(geolocation,'$.longitude') AS longitude,
        listing_name,
        CAST(GET_JSON_OBJECT(house_info,'$.area') AS INTEGER) AS total_area,
        GET_JSON_OBJECT(house_info,'$.amenities') AS amenities,
        CAST(GET_JSON_OBJECT(house_info,'$.bathrooms') AS INTEGER) AS bathrooms,
        CAST(GET_JSON_OBJECT(house_info,'$.bedrooms') AS INTEGER) AS bedrooms,
        CAST(GET_JSON_OBJECT(house_info,'$.floor') AS INTEGER) AS floors,
        CAST(GET_JSON_OBJECT(house_info,'$.parking_spaces') AS INTEGER) AS parking_spaces,
        CAST(GET_JSON_OBJECT(house_info,'$.suites') AS INTEGER) AS suites,
        GET_JSON_OBJECT(house_info,'$.unit_type') AS unit_type,
        GET_JSON_OBJECT(house_info,'$.usage_type') AS usage_type,
        CAST(GET_JSON_OBJECT(type,'$.rentable') AS BOOLEAN) AS is_for_rent,
        CAST(GET_JSON_OBJECT(type,'$.buyable') AS BOOLEAN)AS is_for_sale,
        CASE
            WHEN GET_JSON_OBJECT(type,'$.rentable') = TRUE
                AND GET_JSON_OBJECT(type,'$.buyable') = TRUE THEN TRUE
            ELSE FALSE
        END AS is_hybrid,
        GET_JSON_OBJECT(contact_information,'$.advertiser_name') AS advertiser_name,
        GET_JSON_OBJECT(contact_information,'$.advertiser_phone') AS advertiser_phone,
        CAST(COALESCE(price.rent.condo_fee, price.sale.condo_fee) AS DOUBLE) AS condo_fee,
        CAST(COALESCE(price.rent.iptu, price.sale.iptu) AS DOUBLE) AS iptu,
        CAST(price.rent.price AS DOUBLE) AS price_rental,
        CAST(price.sale.price AS DOUBLE) AS price_sale,
        ROUND(price.rent.price/GET_JSON_OBJECT(house_info,'$.area'), 2) AS price_m2_rental,
        ROUND(price.sale.price/GET_JSON_OBJECT(house_info,'$.area'), 2) AS price_m2_sale,
        GET_JSON_OBJECT(date_info,'$.created_at') AS ts_created,
        GET_JSON_OBJECT(date_info,'$.updated_at') AS ts_updated,
        year,
        month,
        day
    FROM
        json_select
    WHERE 
        year = {year}
        AND month = {month}
        AND day = {day}
