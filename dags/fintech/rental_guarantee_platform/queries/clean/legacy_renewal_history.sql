SELECT 
    renewal_id                  AS id_renewal,
    propose_id                  AS id_propose,
    previous_monthly_amount,
    updated_monthly_amount,
    price_index,
    price_index_type,
    due_date                    AS dt_due,
    created_renewal_at          AS ts_renewal_created,
    updated_renewal_at          AS ts_renewal_updated,
    created_at                  AS ts_created,
    updated_at                  AS ts_updated
FROM 
    datalake_rental_guarantee_platform_raw.legacy_renewal_history
