SELECT
    id AS id_seller,
    sales_flow_id AS id_sales_flow,
    docx_folder_id AS id_docx_folder,
    name,
    email,
    CAST(share_percentage AS VARCHAR(10)) AS share_percentage,
    holding_value,
    is_ccv_signer,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.seller_data

