SELECT
    id AS id_ccv_termination,
    sales_flow_id AS id_sales_flow,
    condition,
    reason,
    document_token,
    payer_type,
    payment_value,
    approval_email,
    zendesk_link,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.ccv_termination

