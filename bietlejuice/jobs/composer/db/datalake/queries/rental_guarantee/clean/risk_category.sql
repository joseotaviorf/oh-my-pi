SELECT 
    id,  
    category_description,
    category_level, 
    deposit_factor,
    factor AS guarantee_factor,
    allow_deposit AS is_deposit_allowed,
    allow_guarantee AS is_guarantee_allowed,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_rental_guarantee_raw.risk_category
