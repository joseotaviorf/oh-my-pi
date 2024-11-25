SELECT 
    id,
    business_unit_id AS id_business_unit,
    region_id AS id_region,
    business_context,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM    
    datalake_hub_services_raw.business_unit_region
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1