SELECT 
    CAST(house.id AS INT)                    AS sk_house,
    CAST(house.id_address AS INT)            AS sk_address,
    CAST(house.id_real_estate_agency AS INT) AS sk_real_estate_agency,
    CAST(house.id_condo AS INT)              AS sk_condo,
    CAST(house.id_neighborhood AS INT)       AS sk_neighborhood,
    CAST(house.id_type AS INT)               AS sk_type,
    CAST(house.id AS INT)                    AS id_house,
    house.goal,
    house.price,
    house.address,
    house.zip_code,
    house.lat,
    house.lng,
    house.is_duplicated,
    house.ts_created,
    house.ts_disabled,
    NOW() AS ts_load
FROM   
    datalake_casa_mineira_portal_clean.house AS house 
WHERE
    house.id IS NOT NULL
    AND house.id NOT REGEXP '[a-zA-Z]'