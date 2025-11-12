SELECT
    id,
    name,
    product_id AS id_product,
    start_date AS dt_start,
    end_date AS dt_end,
    status,
    customizations,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_lending_raw.offer_cohort