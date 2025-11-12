SELECT  
    id,
    uuid,
    name,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_lending_raw.product