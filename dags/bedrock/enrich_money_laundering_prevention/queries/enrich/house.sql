SELECT
    h.id AS id_house,
    h.id_user,
    h.id_user_registrant,
    h.id_state,
    h.city AS city_name,
    h.address,
    h.complement,
    h.number,
    h.zipcode,
    lh.country_code,
    h.type,
    h.registry AS registry_name,
    h.registration,
    h.total_area,
    h.sale_price,
    h.rent AS rent_value,
    h.is_verified,
    h.is_in_negotiation,
    h.is_in_external_negotiation,
    h.dt_creation
FROM 
    datalake_ebdb_clean.house AS h
LEFT JOIN datalake_ebdb_listing.house AS lh
    ON lh.id = h.id