SELECT 
    id, 
    description, 
    created_at AS ts_created, 
    updated_at AS ts_updated,
    year,
    month,
    day
FROM 
    datalake_sales_flow_raw.clause_subject