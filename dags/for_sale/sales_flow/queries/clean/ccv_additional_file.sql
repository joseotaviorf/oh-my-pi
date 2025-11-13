SELECT
    id,
    ccv_flow_id AS id_ccv_flow,
    name,
    storage_hash_token,
    deleted_at AS ts_deleted,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.ccv_additional_file
