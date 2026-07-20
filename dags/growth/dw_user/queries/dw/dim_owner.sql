SELECT 
    id_user AS sk_owner,
    country_code,
    contact_email,
    contact_phone_1,
    contact_phone_2,
    NOW() AS ts_load
FROM 
    datalake_ebdb_listing.house