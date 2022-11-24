SELECT
    id_house_partner,
    partner,
    address,
    CAST(REGEXP_REPLACE(number,'([^0-9])','') AS INT) AS number,
    complement,
    CAST(REGEXP_REPLACE(complement,'([^0-9])','') AS INT) AS complement_number,
    CAST(REPLACE(lat,',','.') AS FLOAT) AS lat,
    CAST(REPLACE(lng,',','.')  AS FLOAT) AS lng,
    CONCAT(CAST(REPLACE(lat,',','.') AS FLOAT), CAST(REPLACE(lng,',','.') AS FLOAT)) AS lat_lng,
    cep AS zip_code
FROM
  datalake_gsheets_raw.deduplicate_batch_listings_forsale
