SELECT
    id AS id_buyer,
    sales_flow_id AS id_sales_flow,
    docx_folder_id AS id_docx_folder,
    name,
    email,
    holding_value,
    ccv_role,
    signer_status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.buyer_data

