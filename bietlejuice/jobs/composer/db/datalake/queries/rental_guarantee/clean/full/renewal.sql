SELECT 
    id, 
    guarantee_id AS id_guarantee, 
    charge_id AS id_charge,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_rental_guarantee_raw.renewal
