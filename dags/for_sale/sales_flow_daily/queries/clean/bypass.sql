SELECT
    id,
    house_id AS id_house,
    register_number,
    rating,
    status,
    filepath_s3 AS file_path_s3,
    message,
    found_data,
    bypass_confirmation AS is_bypass,
    processing_date AS dt_processing,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.bypass

