SELECT
    id_house AS sk_house,
    id_user AS sk_user,
    id_user_registrant AS sk_user_registrant,
    id_state AS sk_state,
    city_name,
    address,
    complement,
    number,
    zipcode,
    country_code,
    type,
    registry_name,
    registration,
    total_area,
    sale_price,
    is_verified,
    is_in_negotiation,
    is_in_external_negotiation,
    dt_creation
FROM 
    datalake_money_laundering_prevention.house