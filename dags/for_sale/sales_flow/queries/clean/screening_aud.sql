SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    sales_flow_id AS id_sales_flow,
    sales_flow_id_mod AS mod_id_sales_flow,
    legal_pendency_status,
    legal_pendency_status_mod AS mod_legal_pendency_status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.screening_aud
