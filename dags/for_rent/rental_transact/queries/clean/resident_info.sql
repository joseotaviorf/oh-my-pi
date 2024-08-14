SELECT 
    id,
    tenant_external_id AS id_tenant_external,
    introduction,
    number_of_cohabitants,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_transact_raw.resident_info