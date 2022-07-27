SELECT
    id AS id_house,
    id_user,
    id_user_registrant,
    id_state,
    city AS city_name,
    address,
    complement,
    number,
    zipcode,
    type,
    registry AS registry_name,
    registration,
    total_area,
    sale_price,
    rent AS rent_value,
    is_verified,
    is_in_negotiation,
    is_in_external_negotiation,
    dt_creation
FROM 
    datalake_ebdb_clean.house