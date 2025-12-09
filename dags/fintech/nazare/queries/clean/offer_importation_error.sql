SELECT
    id AS id_offer_importation_error,
    sales_flow_id AS id_sales_flow,
    external_id AS id_external,
    error_messages,
    original_value,
    TIMESTAMP(created_at) AS ts_created
FROM
    datalake_nazare_raw.offer_importation_error
