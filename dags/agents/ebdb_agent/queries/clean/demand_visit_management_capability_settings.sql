SELECT
    id,
    capability_id AS id_capability,
    business_context,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_ebdb_raw.DemandVisitManagementCapabilitySettings