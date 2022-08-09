SELECT 
    id_house AS sk_house,
    id_sale_listing AS sk_sale_listing,
    id_user AS sk_user,
    id_user_registrant AS sk_user_registrant,  
    listing_value,
    calculator_price,
    country_code,
    status,
    status_closing,
    compare_price_with_average,
    is_for_rent,
    is_for_sale,
    is_3p_supply,
    is_imovel_v3,
    is_photographer_job_pending,
    is_verified,
    dt_created,
    ts_first_sale_listing,
    ts_last_sale_listing
FROM
    datalake_money_laundering_prevention.listing