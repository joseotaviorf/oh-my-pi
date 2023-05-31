SELECT 
    id, 
    created_at, 
    updated_at, 
    house_lead_id, 
    property_id,
    DATE(updated_at) AS dt    
FROM 
    house_lead_conversion
WHERE
    DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')