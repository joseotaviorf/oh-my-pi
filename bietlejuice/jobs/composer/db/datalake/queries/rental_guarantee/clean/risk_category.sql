SELECT 
    id,  
    category_level, 
    factor,
    allow_guarantee AS is_guarantee_allowed,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_rental_guarantee_raw.risk_category
